/* Offline-contract probe: compiled here, never run automatically. A fixture
 * opt-in is explicit in the caller environment. It does not send AppleEvents,
 * touch the registry, or alter any media player's state. */
#define COBJMACROS
#include <windows.h>
#include <roapi.h>
#include <winstring.h>
#include <inspectable.h>
#include <stdio.h>
#include <wchar.h>
#include <string.h>
#include "generated-iids.h"
typedef struct Interface {void **v;} Interface;
typedef HRESULT (WINAPI *Factory)(HSTRING,IActivationFactory **);
typedef HRESULT (WINAPI *Query)(void *,REFIID,void **);
typedef HRESULT (WINAPI *BridgeGetObject)(void *,void **);
typedef HRESULT (WINAPI *GetString)(void *,HSTRING *);
static void drop(void *p){if(p)IUnknown_Release((IUnknown *)p);}
static const GUID statics_iid={0x2050c4ee,0x11a0,0x57de,{0xae,0xd7,0xc9,0x7c,0x70,0x33,0x82,0x45}};
static HRESULT obj(void *p,int slot,void **out){return ((BridgeGetObject)((Interface *)p)->v[slot])(p,out);}
#include "probe-contracts.inc"
int wmain(int argc,WCHAR **argv) {
    if(argc<2){fprintf(stderr,"usage: lwmedia-contract-probe.exe <bridge.dll> [--watch-ms N]\n");return 2;}
    setvbuf(stdout,NULL,_IONBF,0);
    DWORD watch_ms=argc==4&&!wcscmp(argv[2],L"--watch-ms")?(DWORD)_wtoi(argv[3]):0;
    HRESULT hr=RoInitialize(RO_INIT_MULTITHREADED);
    if(FAILED(hr)){fprintf(stderr,"RoInitialize 0x%08lx\n",hr);return 3;}
    HMODULE dll=LoadLibraryW(argv[1]);
    if(!dll){fprintf(stderr,"LoadLibrary %lu\n",GetLastError());RoUninitialize();return 4;}
    Factory factory=(Factory)GetProcAddress(dll,"DllGetActivationFactory");
    const WCHAR *class_name=L"Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager";
    HSTRING name=NULL,title=NULL;IActivationFactory *activation=NULL;
    void *statics=NULL,*async=NULL,*manager=NULL,*session=NULL,*props_async=NULL,*props=NULL;
    WindowsCreateString(class_name,(UINT32)wcslen(class_name),&name);
    hr=factory?factory(name,&activation):E_NOTIMPL;
    if(SUCCEEDED(hr))hr=((Query)((Interface *)activation)->v[0])(activation,&statics_iid,&statics);
    if(SUCCEEDED(hr))hr=obj(statics,6,&async);
    if(SUCCEEDED(hr))hr=obj(async,8,&manager);
    if(SUCCEEDED(hr))hr=obj(manager,6,&session);
    if(SUCCEEDED(hr))printf("current_session_available_before_event_subscription=%s\n",session?"true":"false");
    if(SUCCEEDED(hr)&&session)hr=obj(session,7,&props_async);
    if(SUCCEEDED(hr)&&props_async)hr=obj(props_async,8,&props);
    if(SUCCEEDED(hr)&&props)hr=((GetString)((Interface *)props)->v[6])(props,&title);
    if(FAILED(hr))fprintf(stderr,"contract probe failed 0x%08lx\n",hr);
    else if(!session)puts("session=null (no accepted broker snapshot)");
    else {
        const WCHAR *text=WindowsGetStringRawBuffer(title,NULL);
        int length=WideCharToMultiByte(CP_UTF8,0,text,-1,NULL,0,NULL,NULL);
        char *utf8=HeapAlloc(GetProcessHeap(),0,length);
        if(utf8){WideCharToMultiByte(CP_UTF8,0,text,-1,utf8,length,NULL,NULL);printf("title=%s\n",utf8);HeapFree(GetProcessHeap(),0,utf8);}
        hr=full_contracts(factory,manager,session,props,watch_ms);
        if(FAILED(hr))fprintf(stderr,"extended contract failed 0x%08lx\n",hr);
    }
    WindowsDeleteString(title);WindowsDeleteString(name);
    drop(props);drop(props_async);drop(session);drop(manager);drop(async);drop(statics);drop(activation);
    FreeLibrary(dll);RoUninitialize();return FAILED(hr)?5:0;
}
