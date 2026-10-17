// Stub every hardware-facing API: these tests never open an audio device.
#include <AudioUnit/AudioUnit.h>
#include <AudioToolbox/AudioToolbox.h>
#include <dlfcn.h>
#include <assert.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
static AudioStreamBasicDescription fakeFormat;
static int noComponent, badDescription, badType, badSubtype, badManufacturer, failDladdr, nilOwner;
static OSType fakeSubtype = kAudioUnitSubType_HALOutput;
static const char *fakeOwner = "/test/winecoreaudio.so";
static AURenderCallbackStruct installed;
static int setCalls, failRegistration;
static OSStatus FakeSet(AudioUnit u,AudioUnitPropertyID p,AudioUnitScope s,AudioUnitElement e,const void*d,UInt32 n) {
    setCalls++; if(p==kAudioUnitProperty_SetRenderCallback) {if(failRegistration)return -1;installed=*(const AURenderCallbackStruct*)d;}return noErr;
}
static OSStatus FakeGet(AudioUnit u,AudioUnitPropertyID p,AudioUnitScope s,AudioUnitElement e,void*d,UInt32*n) {*(AudioStreamBasicDescription*)d=fakeFormat;return noErr;}
static AudioComponent FakeComponent(AudioComponentInstance u) {return noComponent ? NULL : (AudioComponent)(uintptr_t)2;}
static OSStatus FakeDescription(AudioComponent c,AudioComponentDescription*d) {*d=(AudioComponentDescription){kAudioUnitType_Output,fakeSubtype,kAudioUnitManufacturer_Apple,0,0};if(badType)d->componentType=0;if(badSubtype)d->componentSubType=0;if(badManufacturer)d->componentManufacturer=0;return badDescription ? -50 : noErr;}
static int FakeDladdr(const void*p,Dl_info*d) {d->dli_fname=nilOwner?NULL:fakeOwner;return !failDladdr;}
#define LW_VOLUME_TEST
#define AudioUnitSetProperty FakeSet
#define AudioUnitGetProperty FakeGet
#define AudioComponentInstanceGetComponent FakeComponent
#define AudioComponentGetDescription FakeDescription
#define dladdr FakeDladdr
#include "../playback/wine_volume.c"
static int produced;
static OSStatus Produce(void *r,AudioUnitRenderActionFlags*f,const AudioTimeStamp*t,UInt32 b,UInt32 n,AudioBufferList*d) {
    produced++; return -7;
}
int main(void) {
    fakeFormat=(AudioStreamBasicDescription){.mFormatID=kAudioFormatLinearPCM,.mFormatFlags=kAudioFormatFlagIsFloat,.mBitsPerChannel=32,.mChannelsPerFrame=2,.mBytesPerFrame=8};
    assert(SupportedFormat(&fakeFormat));
    AudioUnit unit=(AudioUnit)(uintptr_t)1;
    AURenderCallbackStruct producer={Produce,0};
    volumePath="/unused";
    assert(VolumeSetProperty(unit,kAudioUnitProperty_SetRenderCallback,kAudioUnitScope_Input,0,&producer,sizeof(producer))==0);
    float samples[]={1,-1,0.5,-0.5};
    AudioBufferList data={1,{{2,sizeof(samples),samples}}};
    atomic_store(&gain,0.25f); AudioUnitRenderActionFlags flags=0; AudioTimeStamp timestamp={0};
    assert(installed.inputProc(installed.inputProcRefCon,&flags,&timestamp,0,2,&data)==-7);
    assert(produced==1 && samples[0]==0.25f && samples[1]==-0.25f && samples[2]==0.125f);
    atomic_store(&gain,0); installed.inputProc(installed.inputProcRefCon,&flags,&timestamp,0,2,&data);
    assert(produced==2 && samples[0]==0 && (flags&kAudioUnitRenderAction_OutputIsSilence));
    free(installed.inputProcRefCon);
    // Full volume preserves exact bytes; stereo/planar buffers are handled independently.
    float planarA[]={0.8f,-0.8f},planarB[]={0.4f,-0.4f};
    struct {UInt32 count;AudioBuffer buffers[2];} planar={2,{{1,sizeof(planarA),planarA},{1,sizeof(planarB),planarB}}};
    ApplyGain((AudioBufferList*)&planar,&fakeFormat,1); assert(planarA[0]==0.8f);
    ApplyGain((AudioBufferList*)&planar,&fakeFormat,0.5);assert(planarA[0]==0.4f&&planarB[1]==-0.2f);
    fakeFormat.mBitsPerChannel=64;fakeFormat.mBytesPerFrame=16;
    assert(SupportedFormat(&fakeFormat));double doubles[]={0.8,-0.8};AudioBufferList dd={1,{{2,sizeof(doubles),doubles}}};
    ApplyGain(&dd,&fakeFormat,0.5);assert(doubles[0]==0.4&&doubles[1]==-0.4);
    fakeFormat.mBitsPerChannel=31;assert(!SupportedFormat(&fakeFormat));
    for(unsigned bytes=1;bytes<=4;bytes++) {
        fakeFormat.mFormatFlags=kAudioFormatFlagIsPacked|kAudioFormatFlagIsSignedInteger;
        fakeFormat.mBitsPerChannel=bytes*8;fakeFormat.mBytesPerFrame=bytes*2;assert(SupportedFormat(&fakeFormat));
        unsigned char pcm[8]={0};pcm[bytes-1]=0x80;
        AudioBufferList d={1,{{2,bytes,pcm}}};ApplyGain(&d,&fakeFormat,0.5);assert(pcm[bytes-1]==0xc0);
        ApplyGain(&d,&fakeFormat,0);for(unsigned j=0;j<bytes;j++)assert(pcm[j]==0);
    }
    fakeFormat.mFormatFlags=kAudioFormatFlagIsPacked;fakeFormat.mBitsPerChannel=8;fakeFormat.mBytesPerFrame=2;
    unsigned char u8[]={0,128,255};AudioBufferList d={1,{{1,3,u8}}};ApplyGain(&d,&fakeFormat,0);assert(u8[0]==128&&u8[2]==128);
    fakeFormat.mFormatFlags|=kAudioFormatFlagIsBigEndian;assert(!SupportedFormat(&fakeFormat));
    int before=setCalls;assert(VolumeSetProperty(unit,kAudioUnitProperty_SetRenderCallback,kAudioUnitScope_Input,0,&producer,sizeof(producer))!=0);assert(setCalls==before);
    fakeOwner="/unrelated.so";assert(VolumeSetProperty(unit,kAudioUnitProperty_SetRenderCallback,kAudioUnitScope_Input,0,&producer,sizeof(producer))==0);assert(installed.inputProc==Produce);
    char path[]="/private/tmp/lw-volume-test-XXXXXX";int fd=mkstemp(path);assert(fd>=0);close(fd);volumePath=path;
    const char *values[]={"0.65","nan","-1","1.1","0.3 garbage","0","1"};
    const float expected[]={0.65f,0.65f,0.65f,0.65f,0.65f,0,1};
    for(unsigned i=0;i<7;i++){FILE*f=fopen(path,"w");fputs(values[i],f);fclose(f);ReadVolume();assert(atomic_load(&gain)==expected[i]);}
    unlink(path);ReadVolume();assert(atomic_load(&gain)==1);
    puts("volume tests passed (no audio device opened)");
}
