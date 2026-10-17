// Per-Wine-process output gain. No device/master-volume changes. The producer
// keeps rendering at volume zero so media clocks and audio reactions continue.
#include <AudioUnit/AudioUnit.h>
#include <AudioToolbox/AudioToolbox.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <math.h>

typedef struct {
    AURenderCallbackStruct producer;
    AudioStreamBasicDescription format;
} LWVolumeOutput;
static _Atomic float gain;
static const char *volumePath;
static dispatch_source_t volumeTimer;

static int SupportedFormat(const AudioStreamBasicDescription *f) {
    if (f->mFormatID != kAudioFormatLinearPCM || !f->mChannelsPerFrame ||
        (f->mFormatFlags & kAudioFormatFlagIsBigEndian)) return 0;
    // Wine omits IsPacked even for tightly packed PCM; validate stride instead.
    unsigned bytes = f->mBitsPerChannel / 8;
    if (f->mBitsPerChannel != bytes * 8) return 0;
    unsigned channels = (f->mFormatFlags & kAudioFormatFlagIsNonInterleaved) ? 1 : f->mChannelsPerFrame;
    if (f->mBytesPerFrame != bytes * channels) return 0;
    if (f->mFormatFlags & kAudioFormatFlagIsFloat) return f->mBitsPerChannel == 32 || f->mBitsPerChannel == 64;
    if (f->mFormatFlags & kAudioFormatFlagIsSignedInteger) return bytes == 1 || bytes == 2 || bytes == 3 || bytes == 4;
    return f->mBitsPerChannel == 8;
}
static void ApplyGain(AudioBufferList *data, const AudioStreamBasicDescription *f, float value) {
    if (!data || value == 1) return;
    unsigned bytes = f->mBitsPerChannel / 8;
    for (UInt32 b = 0; b < data->mNumberBuffers; ++b) {
        unsigned char *p = data->mBuffers[b].mData;
        if (!p) continue;
        for (UInt32 i = 0; i + bytes <= data->mBuffers[b].mDataByteSize; i += bytes) {
            if (f->mFormatFlags & kAudioFormatFlagIsFloat) {
                if (bytes == 4) { float x; memcpy(&x,p+i,4); x = value == 0 ? 0 : x * value; memcpy(p+i,&x,4); }
                else { double x; memcpy(&x,p+i,8); x = value == 0 ? 0 : x * value; memcpy(p+i,&x,8); }
            } else if (!(f->mFormatFlags & kAudioFormatFlagIsSignedInteger)) {
                p[i] = (unsigned char)(128 + ((int)p[i] - 128) * value);
            } else {
                int32_t x = 0;
                // Explicit sign extension supports packed 24-bit without alignment assumptions.
                for (unsigned j = 0; j < bytes; ++j) x |= (uint32_t)p[i+j] << (8*j);
                if (bytes < 4 && (p[i+bytes-1] & 128)) x |= (uint32_t)-1 << (8*bytes);
                int64_t scaled = (int64_t)((double)x * value);
                for (unsigned j = 0; j < bytes; ++j) p[i+j] = (uint64_t)scaled >> (8*j);
            }
        }
    }
}
static OSStatus VolumeRender(void *ref, AudioUnitRenderActionFlags *flags,
    const AudioTimeStamp *time, UInt32 bus, UInt32 frames, AudioBufferList *data) {
    LWVolumeOutput *out = ref;
    OSStatus result = out->producer.inputProc(out->producer.inputProcRefCon, flags, time, bus, frames, data);
    float value = atomic_load_explicit(&gain, memory_order_relaxed);
    ApplyGain(data, &out->format, value);
    if (flags && value == 0) *flags |= kAudioUnitRenderAction_OutputIsSilence;
    return result;
}
static OSStatus VolumeSetProperty(AudioUnit unit, AudioUnitPropertyID id,
    AudioUnitScope scope, AudioUnitElement element, const void *data, UInt32 size) {
    if (!volumePath || id != kAudioUnitProperty_SetRenderCallback ||
        scope != kAudioUnitScope_Input || element != 0 || !data || size != sizeof(AURenderCallbackStruct))
        return AudioUnitSetProperty(unit,id,scope,element,data,size);
    const AURenderCallbackStruct *producer = data;
    Dl_info owner = {0};
    if (!producer->inputProc || !dladdr((const void *)producer->inputProc,&owner) ||
        !owner.dli_fname || !strstr(owner.dli_fname,"/winecoreaudio.so"))
        return AudioUnitSetProperty(unit,id,scope,element,data,size);
    AudioComponentDescription description = {0};
    AudioComponent component = AudioComponentInstanceGetComponent(unit);
    if (!component || AudioComponentGetDescription(component,&description) != noErr ||
        description.componentType != kAudioUnitType_Output)
        return AudioUnitSetProperty(unit,id,scope,element,data,size);
    AudioStreamBasicDescription format = {0}; UInt32 formatSize = sizeof(format);
    if (AudioUnitGetProperty(unit,kAudioUnitProperty_StreamFormat,kAudioUnitScope_Input,0,&format,&formatSize) != noErr || !SupportedFormat(&format)) {
        fprintf(stderr,"[LWVolume] unsupported Wine output format\n");
        return kAudioUnitErr_FormatNotSupported;
    }
    LWVolumeOutput *out = calloc(1,sizeof(*out));
    if (!out) return kAudioUnitErr_FailedInitialization;
    out->producer = *producer; out->format = format;
    AURenderCallbackStruct callback = {VolumeRender,out};
    OSStatus result = AudioUnitSetProperty(unit,id,scope,element,&callback,sizeof(callback));
    if (result != noErr) free(out);
    // Retain small contexts until process exit: callbacks may still be in flight
    // at disposal/re-registration. No locks, I/O or allocation on audio thread.
    else fprintf(stderr,"[LWVolume] attached Wine output (%u-bit)\n",(unsigned)format.mBitsPerChannel);
    return result;
}
static void ReadVolume(void) {
    if (!volumePath) return;
    FILE *file = fopen(volumePath,"r");
    if (!file) return; // Keep last valid setting across atomic replacement.
    float value; char extra;
    int count = fscanf(file,"%f %c",&value,&extra); fclose(file);
    if (count == 1 && isfinite(value) && value >= 0 && value <= 1) {
        float old = atomic_exchange_explicit(&gain,value,memory_order_relaxed);
        if (old != value) fprintf(stderr,"[LWVolume] gain=%.3f\n",value);
    }
}
#ifndef LW_VOLUME_TEST
__attribute__((used)) static struct { const void *replacement; const void *original; }
volumeInterpose __attribute__((section("__DATA,__interpose"))) = {(const void *)VolumeSetProperty,(const void *)AudioUnitSetProperty};
__attribute__((constructor)) static void StartVolume(void) {
    volumePath = getenv("LW_WINE_VOLUME_FILE");
    if (!volumePath || !*volumePath) { volumePath = NULL; return; }
    ReadVolume(); // Initial silence if the setting is unavailable; never a full-volume startup burst.
    volumeTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_global_queue(QOS_CLASS_UTILITY,0));
    dispatch_source_set_timer(volumeTimer,dispatch_time(DISPATCH_TIME_NOW,0),100*NSEC_PER_MSEC,20*NSEC_PER_MSEC);
    dispatch_source_set_event_handler(volumeTimer,^{ ReadVolume(); });
    dispatch_resume(volumeTimer);
}
#endif
