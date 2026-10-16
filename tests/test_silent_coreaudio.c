// Stub every hardware-facing API: these tests never open an audio device.
#include <AudioUnit/AudioUnit.h>
#include <AudioToolbox/AudioToolbox.h>
#include <dlfcn.h>
#include <assert.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
static char marks[32768];
static size_t marksLength;
static int markCalls;
static ssize_t FakeWrite(int fd, const void *bytes, size_t length) {
    assert(fd == STDERR_FILENO);
    assert(marksLength + length < sizeof(marks));
    memcpy(marks + marksLength, bytes, length); marksLength += length; marks[marksLength] = 0;
    markCalls++; errno = EIO; return -1; // Diagnostics failure must not alter API behavior.
}
static AudioStreamBasicDescription fakeFormat;
static int noComponent, badDescription, badType, badSubtype, badManufacturer, failDladdr, nilOwner;
static OSType fakeSubtype = kAudioUnitSubType_HALOutput;
static const char *fakeOwner = "/test/winecoreaudio.so";
static AURenderCallbackStruct installed;
static int setCalls, initCalls, startCalls, disposeCalls, failRegistration;
static OSStatus FakeSet(AudioUnit u,AudioUnitPropertyID p,AudioUnitScope s,AudioUnitElement e,const void*d,UInt32 n) {
    setCalls++; if(p==kAudioUnitProperty_SetRenderCallback) {if(failRegistration)return -1;installed=*(const AURenderCallbackStruct*)d;}return noErr;
}
static OSStatus FakeGet(AudioUnit u,AudioUnitPropertyID p,AudioUnitScope s,AudioUnitElement e,void*d,UInt32*n) {*(AudioStreamBasicDescription*)d=fakeFormat;return noErr;}
static AudioComponent FakeComponent(AudioComponentInstance u) {return noComponent ? NULL : (AudioComponent)(uintptr_t)2;}
static OSStatus FakeDescription(AudioComponent c,AudioComponentDescription*d) {*d=(AudioComponentDescription){kAudioUnitType_Output,fakeSubtype,kAudioUnitManufacturer_Apple,0,0};if(badType)d->componentType=0;if(badSubtype)d->componentSubType=0;if(badManufacturer)d->componentManufacturer=0;return badDescription ? -50 : noErr;}
static int FakeDladdr(const void*p,Dl_info*d) {d->dli_fname=nilOwner?NULL:fakeOwner;return !failDladdr;}
static OSStatus FakeInitialize(AudioUnit u) {initCalls++;return noErr;}
static OSStatus FakeStart(AudioUnit u) {startCalls++;return noErr;}
static OSStatus FakeDispose(AudioComponentInstance u) {disposeCalls++;return noErr;}
#define LW_SILENT_TEST
#define AudioUnitSetProperty FakeSet
#define AudioUnitGetProperty FakeGet
#define AudioComponentInstanceGetComponent FakeComponent
#define AudioComponentGetDescription FakeDescription
#define AudioUnitInitialize FakeInitialize
#define AudioOutputUnitStart FakeStart
#define AudioComponentInstanceDispose FakeDispose
#define dladdr FakeDladdr
#define write FakeWrite
#include "../playback/diagnostics/silent_coreaudio.c"
static OSStatus Produce(void *ref,AudioUnitRenderActionFlags*f,const AudioTimeStamp*t,UInt32 b,UInt32 n,AudioBufferList*d) {
    for(UInt32 i=0;i<d->mNumberBuffers;i++)memset(d->mBuffers[i].mData,0x55,d->mBuffers[i].mDataByteSize);return *(OSStatus*)ref;
}
int main(void) {
    assert(LWSilentOutputCallbackCount()==0&&LWSilentOutputActiveCount()==0);
    errno = EBUSY; SILENT_MARK("stub probe"); assert(errno == EBUSY);
    AudioUnit unit=(AudioUnit)(uintptr_t)1;UInt32 on=1,off=0;int before=setCalls;
    assert(SilentSetProperty(unit,kAudioOutputUnitProperty_EnableIO,kAudioUnitScope_Input,1,&on,sizeof(on))!=noErr);
    assert(SilentSetProperty(unit,kAudioOutputUnitProperty_SetInputCallback,kAudioUnitScope_Output,1,NULL,0)!=noErr);
    assert(setCalls==before);assert(SilentStart(unit)!=noErr&&startCalls==0);assert(SilentInitialize(unit)!=noErr&&initCalls==0);
    assert(SilentSetProperty(unit,kAudioOutputUnitProperty_EnableIO,kAudioUnitScope_Input,1,&off,sizeof(off))==noErr);
    fakeFormat.mFormatID=kAudioFormatLinearPCM;fakeFormat.mFormatFlags=kAudioFormatFlagIsFloat;fakeFormat.mBitsPerChannel=32;
    OSStatus status=-7;AURenderCallbackStruct producer={Produce,&status};
    int *rejectCases[]={&noComponent,&badDescription,&badType,&badSubtype,&badManufacturer,&failDladdr,&nilOwner};
    const char *rejectLabels[]={"no component","description\n","type\n","subtype\n","manufacturer\n","dladdr\n","nil owner path"};
    for(unsigned i=0;i<sizeof(rejectCases)/sizeof(rejectCases[0]);++i) {
        before=setCalls;*rejectCases[i]=1;
        assert(SilentSetProperty(unit,kAudioUnitProperty_SetRenderCallback,kAudioUnitScope_Input,0,&producer,sizeof(producer))==kAudioUnitErr_FormatNotSupported);
        assert(setCalls==before&&!Protected(unit));assert(strstr(marks,rejectLabels[i]));*rejectCases[i]=0;
    }
    AURenderCallbackStruct nilProducer={NULL,&status};
    assert(SilentSetProperty(unit,kAudioUnitProperty_SetRenderCallback,kAudioUnitScope_Input,0,&nilProducer,sizeof(nilProducer))==kAudioUnitErr_FormatNotSupported);
    assert(strstr(marks,"nil callback"));
    fakeOwner="/test/other.so";before=setCalls;
    assert(SilentSetProperty(unit,kAudioUnitProperty_SetRenderCallback,kAudioUnitScope_Input,0,&producer,sizeof(producer))==kAudioUnitErr_FormatNotSupported);
    assert(setCalls==before&&!Protected(unit));assert(strstr(marks,"reject RenderCallback owner path"));
    assert(strstr(marks,"component type=0x61756f75"));assert(strstr(marks,"render owner path=/test/other.so"));
    fakeOwner="/test/winecoreaudio.so";failRegistration=1;
    assert(SilentSetProperty(unit,kAudioUnitProperty_SetRenderCallback,kAudioUnitScope_Input,0,&producer,sizeof(producer))!=noErr);
    assert(!Protected(unit));failRegistration=0;
    assert(SilentSetProperty(unit,kAudioUnitProperty_SetRenderCallback,kAudioUnitScope_Input,0,&producer,sizeof(producer))==noErr);
    assert(Protected(unit));assert(LWSilentOutputActiveCount()==1);assert(SilentInitialize(unit)==noErr&&initCalls==1);assert(SilentStart(unit)==noErr&&startCalls==1);
    before=setCalls;
    assert(SilentSetProperty(unit,kAudioUnitProperty_StreamFormat,kAudioUnitScope_Input,0,&fakeFormat,sizeof(fakeFormat))!=noErr);
    assert(SilentSetProperty(unit,kAudioUnitProperty_SetRenderCallback,kAudioUnitScope_Output,0,&producer,sizeof(producer))!=noErr);assert(setCalls==before);
    unsigned char a[16],b[8],value;struct {UInt32 count;AudioBuffer buffer[2];} storage={2,{{1,sizeof(a),a},{1,sizeof(b),b}}};AudioBufferList*d=(AudioBufferList*)&storage;
    AudioTimeStamp time={0};AudioUnitRenderActionFlags flags=0;int marksBeforeRender=markCalls;assert(installed.inputProc(installed.inputProcRefCon,&flags,&time,0,4,d)==-7);
    for(int i=0;i<16;i++)assert(a[i]==0);for(int i=0;i<8;i++)assert(b[i]==0);assert(flags&kAudioUnitRenderAction_OutputIsSilence);
    SilentOutput*out=installed.inputProcRefCon;assert(out->callbacks==1);assert(markCalls==marksBeforeRender);fakeFormat.mFormatFlags=0;fakeFormat.mBitsPerChannel=8;
    assert(SilenceByte(&fakeFormat,&value)&&value==128);out->silence=value;assert(SilentRender(out,&flags,&time,0,4,d)==-7);
    for(int i=0;i<16;i++)assert(a[i]==128);for(int i=0;i<8;i++)assert(b[i]==128);
    assert(LWSilentOutputCallbackCount()==2);assert(SilentDispose(unit)==noErr&&disposeCalls==1);assert(LWSilentOutputActiveCount()==0&&LWSilentOutputCallbackCount()==2);assert(!Protected(unit));assert(SilentStart(unit)!=noErr&&startCalls==1);assert(SilentInitialize(unit)!=noErr&&initCalls==1);
    // Address reuse is authorized only by a fresh, verified DefaultOutput registration.
    fakeSubtype=kAudioUnitSubType_DefaultOutput;
    fakeFormat.mFormatFlags=kAudioFormatFlagIsFloat;fakeFormat.mBitsPerChannel=32;
    assert(SilentSetProperty(unit,kAudioUnitProperty_SetRenderCallback,kAudioUnitScope_Input,0,&producer,sizeof(producer))==noErr);
    assert(Protected(unit));assert(SilentInitialize(unit)==noErr&&initCalls==2);assert(SilentStart(unit)==noErr&&startCalls==2);
    marksBeforeRender=markCalls;
    assert(installed.inputProc(installed.inputProcRefCon,&flags,&time,0,4,d)==-7);
    for(int i=0;i<16;i++)assert(a[i]==0);for(int i=0;i<8;i++)assert(b[i]==0);
    assert(markCalls==marksBeforeRender);
    assert(LWSilentOutputActiveCount()==1&&LWSilentOutputCallbackCount()==3);
    before=setCalls;
    assert(SilentSetProperty(unit,kAudioOutputUnitProperty_EnableIO,kAudioUnitScope_Input,1,&on,sizeof(on))!=noErr);
    assert(SilentSetProperty(unit,kAudioOutputUnitProperty_SetInputCallback,kAudioUnitScope_Output,1,NULL,0)!=noErr);
    assert(setCalls==before);assert(SilentDispose(unit)==noErr&&disposeCalls==2);assert(!Protected(unit));
    assert(SilentStart(unit)!=noErr&&startCalls==2);assert(SilentInitialize(unit)!=noErr&&initCalls==2);
    fakeFormat.mFormatFlags=0;
    fakeFormat.mBitsPerChannel=16;assert(!SilenceByte(&fakeFormat,&value));fakeFormat.mFormatID=kAudioFormatULaw;assert(!SilenceByte(&fakeFormat,&value));
    assert(SilentSetProperty(unit,kAudioUnitProperty_SetRenderCallback,kAudioUnitScope_Input,0,&producer,sizeof(producer))!=noErr);
    assert(SilentGraphStart(NULL)!=noErr);
    assert(LWSilentOutputActiveCount()==0&&LWSilentOutputCallbackCount()==3);
    assert(strstr(marks,"set enter EnableIO\n"));
    assert(strstr(marks,"reject capture EnableIO\n"));
    assert(strstr(marks,"render install original error\n"));
    assert(strstr(marks,"protected Apple output\n"));
    assert(strstr(marks,"initialize original ok\n"));
    assert(strstr(marks,"start original ok\n"));
    assert(strstr(marks,"dispose original ok\n"));
    assert(strstr(marks,"reject start unprotected\n"));
    assert(strstr(marks,"reject GraphStart\n"));
    puts("PASS: capture/start/register/format/dispose guards; first callback/all buffers; producer errors; unsigned8; HAL/DefaultOutput allowlist; split owner/component guards; control-path markers/errno; no RT logging; cumulative/active metadata getters; no hardware APIs");
}
