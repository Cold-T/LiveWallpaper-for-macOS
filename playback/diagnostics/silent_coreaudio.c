// Diagnostic-only silent output for the task's Wine process. Keeps a real
// render endpoint/clock; never changes a device or another process's volume.
#include <AudioUnit/AudioUnit.h>
#include <AudioToolbox/AudioToolbox.h>
#include <dlfcn.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>

typedef struct SilentOutput {
    AudioUnit unit;
    int active;
    AURenderCallbackStruct producer;
    unsigned char silence;
    _Atomic unsigned long callbacks;
    struct SilentOutput *next;
} SilentOutput;
static SilentOutput *outputs;
static pthread_mutex_t output_lock = PTHREAD_MUTEX_INITIALIZER;

// Fixed, bounded diagnostics only on control paths. Never called by SilentRender.
// Preserve errno so an unavailable/full stderr cannot change the guarded API result.
static void SilentMark(const char *message, size_t length) {
    int saved_errno = errno;
    (void)write(STDERR_FILENO, message, length);
    errno = saved_errno;
}
#define SILENT_MARK(message) SilentMark("[LWSilent] " message "\n", sizeof("[LWSilent] " message "\n") - 1)
// Hex words avoid stdio/locale/dyld formatting on this loader diagnostic path.
static void SilentWord(const char *label, size_t labelLength, UInt32 value) {
    char digits[11] = "0x00000000\n";
    static const char hex[] = "0123456789abcdef";
    for (unsigned i = 0; i < 8; ++i) digits[2 + i] = hex[(value >> (28 - 4 * i)) & 15];
    SilentMark(label, labelLength);
    SilentMark(digits, sizeof(digits));
}
#define SILENT_WORD(label, value) SilentWord("[LWSilent] " label "=", sizeof("[LWSilent] " label "=") - 1, (UInt32)(value))
static void SilentOwnerPath(const char *path) {
    static const char prefix[] = "[LWSilent] render owner path=";
    SilentMark(prefix, sizeof(prefix) - 1);
    SilentMark(path, strnlen(path, 512));
    SilentMark("\n", 1);
}
static int KeyProperty(AudioUnitPropertyID id) {
    return id == kAudioOutputUnitProperty_EnableIO || id == kAudioOutputUnitProperty_CurrentDevice ||
        id == kAudioUnitProperty_StreamFormat || id == kAudioUnitProperty_SetRenderCallback ||
        id == kAudioOutputUnitProperty_SetInputCallback;
}

static int SilenceByte(const AudioStreamBasicDescription *format, unsigned char *value) {
    if (format->mFormatID != kAudioFormatLinearPCM) return 0;
    if (format->mFormatFlags & (kAudioFormatFlagIsFloat | kAudioFormatFlagIsSignedInteger)) {
        *value = 0; return 1;
    }
    if (format->mBitsPerChannel == 8) { *value = 128; return 1; }
    return 0;
}
static OSStatus SilentRender(void *ref, AudioUnitRenderActionFlags *flags,
    const AudioTimeStamp *time, UInt32 bus, UInt32 frames, AudioBufferList *data) {
    SilentOutput *out = ref;
    OSStatus result = out->producer.inputProc(out->producer.inputProcRefCon, flags, time, bus, frames, data);
    if (data) for (UInt32 i = 0; i < data->mNumberBuffers; ++i)
        if (data->mBuffers[i].mData) memset(data->mBuffers[i].mData, out->silence, data->mBuffers[i].mDataByteSize);
    if (flags) *flags |= kAudioUnitRenderAction_OutputIsSilence;
    atomic_fetch_add_explicit(&out->callbacks, 1, memory_order_relaxed);
    return result;
}
static int Protected(AudioUnit unit) {
    int found = 0;
    pthread_mutex_lock(&output_lock);
    for (SilentOutput *out = outputs; out; out = out->next) if (out->unit == unit && out->active) { found = 1; break; }
    pthread_mutex_unlock(&output_lock);
    return found;
}
// Non-real-time metadata only: cumulative calls include disposed stream contexts.
// Contexts remain alive until process exit, and no sample buffer is inspected here.
__attribute__((visibility("default"))) unsigned long long LWSilentOutputCallbackCount(void) {
    unsigned long long total = 0;
    pthread_mutex_lock(&output_lock);
    for (SilentOutput *out = outputs; out; out = out->next)
        total += atomic_load_explicit(&out->callbacks, memory_order_relaxed);
    pthread_mutex_unlock(&output_lock);
    return total;
}
__attribute__((visibility("default"))) unsigned long long LWSilentOutputActiveCount(void) {
    unsigned long long total = 0;
    pthread_mutex_lock(&output_lock);
    for (SilentOutput *out = outputs; out; out = out->next) if (out->active) ++total;
    pthread_mutex_unlock(&output_lock);
    return total;
}
static OSStatus SilentSetProperty(AudioUnit unit, AudioUnitPropertyID id,
    AudioUnitScope scope, AudioUnitElement element, const void *data, UInt32 size) {
    if (id == kAudioOutputUnitProperty_EnableIO) SILENT_MARK("set enter EnableIO");
    else if (id == kAudioOutputUnitProperty_CurrentDevice) SILENT_MARK("set enter CurrentDevice");
    else if (id == kAudioUnitProperty_StreamFormat) SILENT_MARK("set enter StreamFormat");
    else if (id == kAudioUnitProperty_SetRenderCallback) SILENT_MARK("set enter RenderCallback");
    else if (id == kAudioOutputUnitProperty_SetInputCallback) SILENT_MARK("set enter InputCallback");
    // Input bus enabling precedes capture callback registration in Wine.
    if (id == kAudioOutputUnitProperty_EnableIO && scope == kAudioUnitScope_Input && element == 1 &&
        (!data || size != sizeof(UInt32) || *(const UInt32 *)data != 0)) { SILENT_MARK("reject capture EnableIO"); return kAudioUnitErr_CannotDoInCurrentContext; }
    if (id == kAudioUnitProperty_StreamFormat && scope == kAudioUnitScope_Input && element == 0 && Protected(unit))
        { SILENT_MARK("reject protected StreamFormat"); return kAudioUnitErr_CannotDoInCurrentContext; }
    // Reject input callbacks before Wine can initialize/start capture.
    if (id == kAudioOutputUnitProperty_SetInputCallback) { SILENT_MARK("reject InputCallback"); return kAudioUnitErr_CannotDoInCurrentContext; }
    if (id != kAudioUnitProperty_SetRenderCallback) {
        if (KeyProperty(id)) SILENT_MARK("set original enter");
        OSStatus result = AudioUnitSetProperty(unit, id, scope, element, data, size);
        if (KeyProperty(id)) { if (result == noErr) SILENT_MARK("set original ok"); else SILENT_MARK("set original error"); }
        return result;
    }
    if (scope != kAudioUnitScope_Input || element != 0) { SILENT_MARK("reject RenderCallback scope"); return kAudioUnitErr_CannotDoInCurrentContext; }
    if (!data || size != sizeof(AURenderCallbackStruct)) { SILENT_MARK("reject RenderCallback data"); return kAudio_ParamError; }
    const AURenderCallbackStruct *producer = data;
    AudioComponentDescription desc = {0};
    SILENT_MARK("render component enter");
    AudioComponent component = AudioComponentInstanceGetComponent(unit);
    Dl_info owner = {0};
    if (!component) { SILENT_MARK("reject RenderCallback no component"); return kAudioUnitErr_FormatNotSupported; }
    OSStatus descriptionResult = AudioComponentGetDescription(component, &desc);
    if (descriptionResult != noErr) {
        SILENT_WORD("description status", descriptionResult);
        SILENT_MARK("reject RenderCallback description"); return kAudioUnitErr_FormatNotSupported;
    }
    SILENT_WORD("component type", desc.componentType);
    SILENT_WORD("component subtype", desc.componentSubType);
    SILENT_WORD("component manufacturer", desc.componentManufacturer);
    if (desc.componentType != kAudioUnitType_Output) { SILENT_MARK("reject RenderCallback type"); return kAudioUnitErr_FormatNotSupported; }
    // The vendor Wine build uses DefaultOutput; upstream uses HALOutput.
    // Both are Apple output units. Input bus/callback and unprotected starts remain forbidden.
    if (desc.componentSubType != kAudioUnitSubType_HALOutput && desc.componentSubType != kAudioUnitSubType_DefaultOutput) { SILENT_MARK("reject RenderCallback subtype"); return kAudioUnitErr_FormatNotSupported; }
    if (desc.componentManufacturer != kAudioUnitManufacturer_Apple) { SILENT_MARK("reject RenderCallback manufacturer"); return kAudioUnitErr_FormatNotSupported; }
    if (!producer->inputProc) { SILENT_MARK("reject RenderCallback nil callback"); return kAudioUnitErr_FormatNotSupported; }
    if (!dladdr((const void *)producer->inputProc, &owner)) { SILENT_MARK("reject RenderCallback dladdr"); return kAudioUnitErr_FormatNotSupported; }
    if (!owner.dli_fname) { SILENT_MARK("reject RenderCallback nil owner path"); return kAudioUnitErr_FormatNotSupported; }
    SilentOwnerPath(owner.dli_fname);
    if (!strstr(owner.dli_fname, "/winecoreaudio.so")) { SILENT_MARK("reject RenderCallback owner path"); return kAudioUnitErr_FormatNotSupported; }
    SILENT_MARK("render component/owner ok");
    AudioStreamBasicDescription format = {0}; UInt32 formatSize = sizeof(format);
    unsigned char silence;
    SILENT_MARK("render get format enter");
    if (AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, &formatSize) != noErr ||
        !SilenceByte(&format, &silence)) { SILENT_MARK("reject RenderCallback format"); return kAudioUnitErr_FormatNotSupported; }
    SILENT_MARK("render get format ok");
    SilentOutput *out = calloc(1, sizeof(*out));
    if (!out) { SILENT_MARK("reject RenderCallback allocation"); return kAudioUnitErr_FailedInitialization; }
    out->unit = unit; out->active = 1; out->producer = *producer; out->silence = silence;
    AURenderCallbackStruct callback = {SilentRender, out};
    SILENT_MARK("render install original enter");
    OSStatus result = AudioUnitSetProperty(unit, id, scope, element, &callback, sizeof(callback));
    if (result != noErr) { SILENT_MARK("render install original error"); free(out); return result; }
    SILENT_MARK("render install original ok");
    // Retain callback context through process exit; no real-time allocation,
    // locks, logging or teardown race in the producer callback.
    pthread_mutex_lock(&output_lock); out->next = outputs; outputs = out; pthread_mutex_unlock(&output_lock);
    SILENT_MARK("protected Apple output");
    return noErr;
}
static OSStatus SilentInitialize(AudioUnit unit) {
    SILENT_MARK("initialize enter");
    if (!Protected(unit)) { SILENT_MARK("reject initialize unprotected"); return kAudioUnitErr_CannotDoInCurrentContext; }
    SILENT_MARK("initialize original enter");
    OSStatus result = AudioUnitInitialize(unit);
    if (result == noErr) SILENT_MARK("initialize original ok"); else SILENT_MARK("initialize original error");
    return result;
}
static OSStatus SilentStart(AudioUnit unit) {
    SILENT_MARK("start enter");
    if (!Protected(unit)) { SILENT_MARK("reject start unprotected"); return kAudioUnitErr_CannotDoInCurrentContext; }
    SILENT_MARK("start original enter");
    OSStatus result = AudioOutputUnitStart(unit);
    if (result == noErr) SILENT_MARK("start original ok"); else SILENT_MARK("start original error");
    return result;
}
static OSStatus SilentDispose(AudioComponentInstance unit) {
    SILENT_MARK("dispose enter");
    pthread_mutex_lock(&output_lock);
    for (SilentOutput *out = outputs; out; out = out->next) if (out->unit == unit) out->active = 0;
    pthread_mutex_unlock(&output_lock);
    SILENT_MARK("dispose original enter");
    OSStatus result = AudioComponentInstanceDispose(unit);
    if (result == noErr) SILENT_MARK("dispose original ok"); else SILENT_MARK("dispose original error");
    return result;
}
static OSStatus SilentGraphStart(AUGraph graph) { SILENT_MARK("reject GraphStart"); return kAudioUnitErr_CannotDoInCurrentContext; }
#ifndef LW_SILENT_TEST
#define INTERPOSE(replacement, original) \
    __attribute__((used)) static struct { const void *newp; const void *oldp; } \
    interpose_##original __attribute__((section("__DATA,__interpose"))) = {(const void *)replacement, (const void *)original}
INTERPOSE(SilentSetProperty, AudioUnitSetProperty);
INTERPOSE(SilentInitialize, AudioUnitInitialize);
INTERPOSE(SilentStart, AudioOutputUnitStart);
INTERPOSE(SilentGraphStart, AUGraphStart);
INTERPOSE(SilentDispose, AudioComponentInstanceDispose);
__attribute__((destructor)) static void SilentReceipt(void) {
    for (SilentOutput *out = outputs; out; out = out->next)
        fprintf(stderr, "[LWSilent] zeroed callbacks=%lu\n", atomic_load_explicit(&out->callbacks, memory_order_relaxed));
}
#endif
