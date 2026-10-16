/* Windows.Media.Control per-player bridge. No runtime patching or privileges.
 * Live integration still requires native player authorization and verification.
 */
#define COBJMACROS
#include <windows.h>
#include <inspectable.h>
#include <roapi.h>
#include <winstring.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <stdio.h>
#ifndef RO_E_CLOSED
#define RO_E_CLOSED ((HRESULT)0x80000013L)
#endif
#ifndef E_ILLEGAL_DELEGATE_ASSIGNMENT
#define E_ILLEGAL_DELEGATE_ASSIGNMENT ((HRESULT)0x80000018L)
#endif
#ifndef E_ILLEGAL_METHOD_CALL
#define E_ILLEGAL_METHOD_CALL ((HRESULT)0x8000000EL)
#endif

typedef struct Snapshot {
    char magic[8]; uint32_t version, size, generation, flags;
    int64_t state, duration, position, observed;
    WCHAR bundle[128], title[512], artist[256], album[256];
} Snapshot;
_Static_assert(sizeof(Snapshot)==2360, "broker ABI size");
typedef struct Obj Obj;
typedef struct Info { const void **vt; Obj *owner; } Info;
typedef struct Blob { LONG refs; DWORD length; WCHAR mime[32]; BYTE data[]; } Blob;
typedef struct EventRegistration EventRegistration;
struct Obj { const void **vt; LONG refs; int kind; GUID iid; Snapshot snapshot;
    void *result, *handler, *progress; volatile LONG closed; BOOL assigned;
    Info info, statics, iterable, ras, input, content, closable;
    CRITICAL_SECTION lock;
    IAgileReference *handler_agile;
    volatile LONG async_status; HRESULT async_error; BOOLEAN bool_result; UINT32 u32_result;
    EventRegistration *events; HANDLE stop, worker; DWORD worker_id;
    Blob *blob; UINT64 position; UINT32 iterator_index; int collection_kind;
};
enum { FACTORY, MANAGER, SESSION, PROPERTIES, PLAYBACK, CONTROLS, TIMELINE, VECTOR,
       ASYNC, ASYNC_BOOL, STRING_VECTOR, ITERATOR, EVENT_ARGS, STREAM_REFERENCE, STREAM, ASYNC_PROGRESS, ASYNC_U32 };
static const GUID iid_factory={0x00000035,0x0000,0x0000,{0xc0,0,0,0,0,0,0,0x46}};
static const GUID iid_inspectable={0xaf86e2e0,0xb12d,0x4c6a,{0x9c,0x5a,0xd7,0xaa,0x65,0x10,0x1e,0x90}};
static const GUID iid_agile={0x94ea2b94,0xe9cc,0x49e0,{0xc0,0xff,0xee,0x64,0xca,0x8f,0x5b,0x90}};
static const GUID iid_async_info={0x00000036,0,0,{0xc0,0,0,0,0,0,0,0x46}};
static const GUID iid_statics={0x2050c4ee,0x11a0,0x57de,{0xae,0xd7,0xc9,0x7c,0x70,0x33,0x82,0x45}};
static const GUID iid_manager={0xcace8eac,0xe86e,0x504a,{0xab,0x31,0x5f,0xf8,0xff,0x1b,0xce,0x49}};
static const GUID iid_session={0x7148c835,0x9b14,0x5ae2,{0xab,0x85,0xdc,0x9b,0x1c,0x14,0xe1,0xa8}};
static const GUID iid_properties={0x68856cf6,0xadb4,0x54b2,{0xac,0x16,0x05,0x83,0x79,0x07,0xac,0xb6}};
static const GUID iid_playback={0x94b4b6cf,0xe8ba,0x51ad,{0x87,0xa7,0xc1,0x0a,0xde,0x10,0x61,0x27}};
static const GUID iid_controls={0x6501a3e6,0xbc7a,0x503a,{0xbb,0x1b,0x68,0xf1,0x58,0xf3,0xfb,0x03}};
static const GUID iid_timeline={0xede34136,0x6f25,0x588d,{0x8e,0xcf,0xea,0x5b,0x67,0x35,0xaa,0xa5}};
#include "generated-iids.h"
static const void *vt_factory[], *vt_statics[], *vt_manager[], *vt_session[], *vt_properties[],
    *vt_playback[], *vt_controls[], *vt_timeline[], *vt_vector[], *vt_async[], *vt_info[],
    *vt_string_vector[], *vt_iterator[], *vt_event_args[], *vt_stream_reference[],
    *vt_stream[], *vt_ras[], *vt_input[], *vt_content[], *vt_closable[], *vt_iterable[], *vt_async_progress[];
static LONG live_objects;
static void trace_result(const char *,HRESULT);
static void trace_iid_result(const char *,REFIID,HRESULT);
static HRESULT create_agile(REFIID iid,IUnknown *object,IAgileReference **reference) {
    typedef HRESULT (WINAPI *GetAgile)(int,REFIID,IUnknown *,IAgileReference **);
    if(!reference)return E_POINTER;*reference=NULL;
    if(!object)return E_POINTER;
    /* Validate the actual requested delegate IID, not a probe-owned surrogate.
     * Never treat IUnknown or a failed marshal as a callable event handler. */
    IUnknown *typed=NULL,*agile=NULL;
    HRESULT hr=IUnknown_QueryInterface(object,iid,(void **)&typed);
    trace_iid_result("Handler.QueryInterface",iid,hr);
    if(FAILED(hr))return hr;
    IUnknown_Release(typed);
    HRESULT agile_hr=IUnknown_QueryInterface(object,&iid_agile,(void **)&agile);
    trace_iid_result("Handler.QueryInterface",&iid_agile,agile_hr);
    if(SUCCEEDED(agile_hr))IUnknown_Release(agile);
    HMODULE combase=GetModuleHandleW(L"combase.dll");
    GetAgile function=combase?(GetAgile)GetProcAddress(combase,"RoGetAgileReference"):NULL;
    hr=function?function(0,iid,object,reference):E_NOTIMPL;
    trace_iid_result("RoGetAgileReference",iid,hr);
    return hr;
}
static HRESULT special_qi(Obj *,REFIID,void **);
static ULONG required_iids(Obj *,IID *);
static void stop_events(Obj *);
static HRESULT event_register(Obj *,int,void *,INT64 *);
static HRESULT event_unregister(Obj *,INT64);
static HRESULT WINAPI thumbnail(Obj *,void **);
static HRESULT load_artwork(const Snapshot *,Blob **);
static HRESULT native_command(Obj *,UINT32,INT64,void **);
static void trace_result(const char *method,HRESULT result) {
    WCHAR enabled[8];
    if(GetEnvironmentVariableW(L"LWMEDIA_TRACE",enabled,8)&&!wcscmp(enabled,L"1")) {
        char line[160];snprintf(line,sizeof(line),"[LWMedia] %s hr=0x%08lx\n",method,(unsigned long)result);
        fputs(line,stderr);fflush(stderr);
    }
}
static void trace_iid_result(const char *method,REFIID iid,HRESULT result) {
    WCHAR enabled[8];
    if(GetEnvironmentVariableW(L"LWMEDIA_TRACE",enabled,8)&&!wcscmp(enabled,L"1")) {
        char line[240];
        snprintf(line,sizeof(line),"[LWMedia] %s iid=%08lx-%04x-%04x-%02x%02x-%02x%02x%02x%02x%02x%02x hr=0x%08lx\n",
          method,(unsigned long)iid->Data1,iid->Data2,iid->Data3,
          iid->Data4[0],iid->Data4[1],iid->Data4[2],iid->Data4[3],iid->Data4[4],iid->Data4[5],iid->Data4[6],iid->Data4[7],(unsigned long)result);
        fputs(line,stderr);fflush(stderr);
    }
}
static ULONG WINAPI addref(Obj *o) { return InterlockedIncrement(&o->refs); }
static ULONG WINAPI release(Obj *o) {
    ULONG refs=InterlockedDecrement(&o->refs);
    if (!refs) {
        stop_events(o);
        if(o->result) IUnknown_Release((IUnknown *)o->result);
        if(o->handler) IUnknown_Release((IUnknown *)o->handler);
        if(o->progress) IUnknown_Release((IUnknown *)o->progress);
        if(o->handler_agile) IAgileReference_Release(o->handler_agile);
        if(o->blob && !InterlockedDecrement(&o->blob->refs))HeapFree(GetProcessHeap(),0,o->blob);
        DeleteCriticalSection(&o->lock);
        HeapFree(GetProcessHeap(),0,o); InterlockedDecrement(&live_objects);
    }
    return refs;
}
static HRESULT WINAPI qi(Obj *o, REFIID iid, void **out) {
    if(!out) return E_POINTER; *out=NULL;
    if(IsEqualIID(iid,&IID_IUnknown)||IsEqualIID(iid,&iid_inspectable)||IsEqualIID(iid,&iid_agile)||IsEqualIID(iid,&o->iid)) *out=o;
    else if(o->kind==FACTORY && IsEqualIID(iid,&iid_statics)) {
        o->statics.vt=vt_statics;*out=&o->statics;
    } else if((o->kind==ASYNC||o->kind==ASYNC_BOOL||o->kind==ASYNC_PROGRESS||o->kind==ASYNC_U32) && IsEqualIID(iid,&iid_async_info)) *out=&o->info;
    else if(special_qi(o,iid,out)!=S_OK){trace_iid_result("Bridge.QueryInterface",iid,E_NOINTERFACE);return E_NOINTERFACE;}
    addref(o);trace_iid_result("Bridge.QueryInterface",iid,S_OK);return S_OK;
}
static HRESULT WINAPI get_iids(Obj *o,ULONG *count,IID **values) {
    if(!count||!values)return E_POINTER; *count=0;*values=NULL;
    IID *v=CoTaskMemAlloc(sizeof(IID)*8);if(!v)return E_OUTOFMEMORY;*v=o->iid;*count=1+required_iids(o,v+1);*values=v;return S_OK;
}
static HRESULT WINAPI get_name(Obj *o,HSTRING *name) {
    const WCHAR *n=L"LiveWallpaper.MediaBridge.Experimental";
    switch(o->kind) {
    case FACTORY:case MANAGER:n=L"Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager";break;
    case SESSION:n=L"Windows.Media.Control.GlobalSystemMediaTransportControlsSession";break;
    case PROPERTIES:n=L"Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties";break;
    case PLAYBACK:n=L"Windows.Media.Control.GlobalSystemMediaTransportControlsSessionPlaybackInfo";break;
    case CONTROLS:n=L"Windows.Media.Control.GlobalSystemMediaTransportControlsSessionPlaybackControls";break;
    case TIMELINE:n=L"Windows.Media.Control.GlobalSystemMediaTransportControlsSessionTimelineProperties";break;
    }
    if(!name)return E_POINTER;return WindowsCreateString(n,(UINT32)wcslen(n),name);
}
static HRESULT WINAPI get_trust(Obj *o,TrustLevel *level) { (void)o;if(!level)return E_POINTER;*level=BaseTrust;return S_OK; }
#define T(name) traced_##name
#define BASE T(qi),T(addref),T(release),T(get_iids),T(get_name),T(get_trust)
#define FACET_BASE T(info_qi),T(info_add),T(info_release),T(info_iids),T(info_name),T(info_trust)
static Obj *create(int kind,const Snapshot *s) {
    Obj *o=HeapAlloc(GetProcessHeap(),HEAP_ZERO_MEMORY,sizeof(*o));if(!o)return NULL;
    o->refs=1;o->kind=kind;if(s)o->snapshot=*s;
    InitializeCriticalSection(&o->lock);
    o->info.owner=o;o->statics.owner=o;o->iterable.owner=o;o->ras.owner=o;o->input.owner=o;o->content.owner=o;o->closable.owner=o;
    o->async_status=1;
    switch(kind) {
    case FACTORY:o->vt=vt_factory;o->iid=iid_factory;break;
    case MANAGER:o->vt=vt_manager;o->iid=iid_manager;break;
    case SESSION:o->vt=vt_session;o->iid=iid_session;break;
    case PROPERTIES:o->vt=vt_properties;o->iid=iid_properties;break;
    case PLAYBACK:o->vt=vt_playback;o->iid=iid_playback;break;
    case CONTROLS:o->vt=vt_controls;o->iid=iid_controls;break;
    case TIMELINE:o->vt=vt_timeline;o->iid=iid_timeline;break;
    case VECTOR:o->vt=vt_vector;o->iid=iid_vector;break;
    case STRING_VECTOR:o->vt=vt_string_vector;o->iid=iid_string_vector;break;
    case ITERATOR:o->vt=vt_iterator;break;
    case EVENT_ARGS:o->vt=vt_event_args;break;
    case STREAM_REFERENCE:o->vt=vt_stream_reference;break;
    case STREAM:o->vt=vt_stream;break;
    case ASYNC:case ASYNC_BOOL:case ASYNC_U32:o->vt=vt_async;o->info.vt=vt_info;break;
    case ASYNC_PROGRESS:o->vt=vt_async_progress;o->info.vt=vt_info;break;
    }
    InterlockedIncrement(&live_objects);return o;
}
static HRESULT return_object(int kind,const Snapshot *s,void **out) {
    if(!out)return E_POINTER;*out=create(kind,s);return *out?S_OK:E_OUTOFMEMORY;
}
static BOOL read_snapshot(Snapshot *s) {
    WCHAR path[32768],fixture[8]; DWORD read=0;
    if(!GetEnvironmentVariableW(L"LWMEDIA_SNAPSHOT_PATH",path,32768))return FALSE;
    HANDLE file=CreateFileW(path,GENERIC_READ,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,NULL,OPEN_EXISTING,0,NULL);
    if(file==INVALID_HANDLE_VALUE)return FALSE;
    BOOL ok=ReadFile(file,s,sizeof(*s),&read,NULL);CloseHandle(file);
    if(!ok||read!=sizeof(*s)||memcmp(s->magic,"LWMEDIA1",8)||s->version!=1||s->size!=sizeof(*s))return FALSE;
    s->bundle[127]=s->title[511]=s->artist[255]=s->album[255]=0;
    if(s->flags&2) {
        if(!GetEnvironmentVariableW(L"LWMEDIA_ALLOW_FIXTURE",fixture,8)||wcscmp(fixture,L"1"))return FALSE;
    }
    return !!(s->flags&1);
}
static HRESULT WINAPI activate(Obj *o,void **out) { (void)o;if(!out)return E_POINTER;*out=NULL;return E_NOTIMPL; }
static HRESULT make_async(void *result,const GUID *iid,void **out) {
    if(!out) {if(result)IUnknown_Release((IUnknown *)result);return E_POINTER;}
    Obj *o=create(ASYNC,NULL);if(!o){if(result)IUnknown_Release((IUnknown *)result);*out=NULL;return E_OUTOFMEMORY;}
    o->iid=*iid;o->result=result;*out=o;return S_OK;
}
static HRESULT WINAPI request(Obj *o,void **out) { (void)o;Obj *m=create(MANAGER,NULL);return m?make_async(m,&iid_async_manager,out):E_OUTOFMEMORY; }
static HRESULT WINAPI request_facet(Info *facet,void **out){return request(facet->owner,out);}
static HRESULT WINAPI current(Obj *o,void **out) {
    (void)o;if(!out)return E_POINTER;*out=NULL;Snapshot s;
    return read_snapshot(&s)?return_object(SESSION,&s,out):S_OK;
}
static HRESULT WINAPI sessions(Obj *o,void **out) { (void)o;Snapshot s={0};if(!read_snapshot(&s))memset(&s,0,sizeof(s));return return_object(VECTOR,&s,out); }
static HRESULT WINAPI event_current(Obj *o,void *h,INT64 *t){return event_register(o,0,h,t);}
static HRESULT WINAPI event_sessions(Obj *o,void *h,INT64 *t){return event_register(o,1,h,t);}
static HRESULT WINAPI event_timeline(Obj *o,void *h,INT64 *t){return event_register(o,2,h,t);}
static HRESULT WINAPI event_playback(Obj *o,void *h,INT64 *t){return event_register(o,3,h,t);}
static HRESULT WINAPI event_properties(Obj *o,void *h,INT64 *t){return event_register(o,4,h,t);}
static HRESULT WINAPI event_remove(Obj *o,INT64 token){return event_unregister(o,token);}
static HRESULT string_value(const WCHAR *text,HSTRING *out) { if(!out)return E_POINTER;return WindowsCreateString(text,(UINT32)wcslen(text),out); }
static HRESULT WINAPI source(Obj *o,HSTRING *out) {return string_value(o->snapshot.bundle,out);}
static HRESULT WINAPI title(Obj *o,HSTRING *out) {return string_value(o->snapshot.title,out);}
static HRESULT WINAPI artist(Obj *o,HSTRING *out) {return string_value(o->snapshot.artist,out);}
static HRESULT WINAPI album(Obj *o,HSTRING *out) {return string_value(o->snapshot.album,out);}
static HRESULT WINAPI empty_string(Obj *o,HSTRING *out) {(void)o;return string_value(L"",out);}
static HRESULT refresh_session(Obj *o,Snapshot *s) {
    if(!read_snapshot(s)||wcscmp(o->snapshot.bundle,s->bundle))return RO_E_CLOSED;
    return S_OK;
}
static HRESULT WINAPI properties(Obj *o,void **out) {
    if(!out)return E_POINTER;*out=NULL;Snapshot s;HRESULT h=refresh_session(o,&s);if(FAILED(h))return h;
    Obj *p=create(PROPERTIES,&s);if(!p)return E_OUTOFMEMORY;
    HRESULT artwork_result=load_artwork(&s,&p->blob);trace_result("Artwork.Load",artwork_result);
    return make_async(p,&iid_async_properties,out);
}
static HRESULT WINAPI timeline(Obj *o,void **out) {Snapshot s;HRESULT h=refresh_session(o,&s);if(FAILED(h)){if(out)*out=NULL;return h;}return return_object(TIMELINE,&s,out);}
static HRESULT WINAPI playback(Obj *o,void **out) {Snapshot s;HRESULT h=refresh_session(o,&s);if(FAILED(h)){if(out)*out=NULL;return h;}return return_object(PLAYBACK,&s,out);}
static HRESULT WINAPI controls(Obj *o,void **out) {return return_object(CONTROLS,&o->snapshot,out);}
static HRESULT WINAPI unknown_optional(Obj *o,void **out) {(void)o;if(!out)return E_POINTER;*out=NULL;return S_OK;}
static HRESULT WINAPI genres(Obj *o,void **out) {(void)o;return return_object(STRING_VECTOR,NULL,out);}
static HRESULT WINAPI zero_i32(Obj *o,INT32 *out) {(void)o;if(!out)return E_POINTER;*out=0;return S_OK;}
static HRESULT WINAPI status(Obj *o,INT32 *out) {if(!out)return E_POINTER;*out=(INT32)o->snapshot.state;return S_OK;}
static HRESULT WINAPI disabled(Obj *o,BOOLEAN *out) {(void)o;if(!out)return E_POINTER;*out=FALSE;return S_OK;}
static HRESULT WINAPI zero_time(Obj *o,INT64 *out) {(void)o;if(!out)return E_POINTER;*out=0;return S_OK;}
static HRESULT WINAPI duration(Obj *o,INT64 *out) {if(!out)return E_POINTER;*out=o->snapshot.duration;return S_OK;}
static HRESULT WINAPI position(Obj *o,INT64 *out) {if(!out)return E_POINTER;*out=o->snapshot.position;return S_OK;}
static HRESULT WINAPI observed(Obj *o,INT64 *out) {if(!out)return E_POINTER;*out=o->snapshot.observed;return S_OK;}
static HRESULT WINAPI unsupported_command(Obj *o,void **out) {
    (void)o;HRESULT h=make_async(NULL,&iid_async_bool,out);if(SUCCEEDED(h))((Obj *)*out)->kind=ASYNC_BOOL;return h;
}
static HRESULT WINAPI cmd_play(Obj *o,void **out){return native_command(o,1,0,out);}
static HRESULT WINAPI cmd_pause(Obj *o,void **out){return native_command(o,2,0,out);}
static HRESULT WINAPI cmd_next(Obj *o,void **out){return native_command(o,3,0,out);}
static HRESULT WINAPI cmd_previous(Obj *o,void **out){return native_command(o,4,0,out);}
static HRESULT WINAPI cmd_toggle(Obj *o,void **out){return native_command(o,5,0,out);}
static HRESULT WINAPI cmd_seek(Obj *o,INT64 p,void **out){return native_command(o,6,p,out);}
static HRESULT WINAPI unsupported_i32(Obj *o,INT32 value,void **out) {(void)value;return unsupported_command(o,out);}
static HRESULT WINAPI unsupported_double(Obj *o,double value,void **out) {(void)value;return unsupported_command(o,out);}
static HRESULT WINAPI at(Obj *o,UINT32 index,void **out) {if(!out)return E_POINTER;*out=NULL;if(index||!(o->snapshot.flags&1))return E_BOUNDS;return return_object(SESSION,&o->snapshot,out);}
static HRESULT WINAPI size(Obj *o,UINT32 *out) {if(!out)return E_POINTER;*out=(o->snapshot.flags&1)?1:0;return S_OK;}
static HRESULT WINAPI index_of(Obj *o,Obj *value,UINT32 *index,BOOLEAN *found) {
    if(!index||!found)return E_POINTER;*index=0;*found=FALSE;
    if(value&&(o->snapshot.flags&1)){
        IUnknown *session=NULL;HRESULT hr=IUnknown_QueryInterface((IUnknown *)value,&iid_session,(void **)&session);
        if(SUCCEEDED(hr)){
            HSTRING bundle=NULL;typedef HRESULT(WINAPI *Source)(void *,HSTRING *);
            hr=((Source)(*(void ***)session)[6])(session,&bundle);
            if(SUCCEEDED(hr))*found=!wcscmp(WindowsGetStringRawBuffer(bundle,NULL),o->snapshot.bundle);
            WindowsDeleteString(bundle);IUnknown_Release(session);
        }
    }
    return S_OK;
}
static HRESULT WINAPI many(Obj *o,UINT32 start,UINT32 capacity,void **out,UINT32 *actual) {if(!actual)return E_POINTER;*actual=0;if(start>((o->snapshot.flags&1)?1u:0u))return E_BOUNDS;if(start==0&&capacity&&(o->snapshot.flags&1)){HRESULT h=at(o,0,out);if(FAILED(h))return h;*actual=1;}return S_OK;}
static HRESULT WINAPI put_completed(Obj *o,void *handler) {
    EnterCriticalSection(&o->lock);
    if(o->closed){LeaveCriticalSection(&o->lock);return RO_E_CLOSED;}
    if(o->assigned){LeaveCriticalSection(&o->lock);return E_ILLEGAL_DELEGATE_ASSIGNMENT;}
    IAgileReference *agile=NULL;
    HRESULT hr=S_OK;
    if(handler && o->async_status==0)hr=create_agile(o->kind==ASYNC_U32?&iid_handler_u32:&iid_handler_bool,(IUnknown *)handler,&agile);
    if(FAILED(hr)){LeaveCriticalSection(&o->lock);return hr;}
    o->assigned=TRUE;o->handler=handler;o->handler_agile=agile;
    if(handler)IUnknown_AddRef((IUnknown *)handler);
    LONG status_now=o->async_status;
    LeaveCriticalSection(&o->lock);
    if(handler && status_now!=0) {
        typedef HRESULT (WINAPI *Invoke)(void *,void *,INT32);
        addref(o);((Invoke)(*(void ***)handler)[3])(handler,o,status_now);release(o);
    }
    return S_OK;
}
static HRESULT WINAPI get_completed(Obj *o,void **out) {if(!out)return E_POINTER;EnterCriticalSection(&o->lock);*out=o->handler;if(*out)IUnknown_AddRef((IUnknown *)*out);LeaveCriticalSection(&o->lock);return S_OK;}
static HRESULT WINAPI results(Obj *o,void *out) {
    if(!out)return E_POINTER;
    if(o->kind==ASYNC_BOOL)*(BOOLEAN *)out=FALSE;else if(o->kind==ASYNC_U32)*(UINT32 *)out=0;else *(void **)out=NULL;
    EnterCriticalSection(&o->lock);HRESULT hr=S_OK;
    if(o->closed)hr=RO_E_CLOSED;
    else if(o->async_status==0)hr=E_ILLEGAL_METHOD_CALL;
    else if(FAILED(o->async_error))hr=o->async_error;
    else if(o->kind==ASYNC_BOOL)*(BOOLEAN *)out=o->bool_result;
    else if(o->kind==ASYNC_U32)*(UINT32 *)out=o->u32_result;
    else {*(void **)out=o->result;if(o->result)IUnknown_AddRef((IUnknown *)o->result);}
    LeaveCriticalSection(&o->lock);return hr;
}
static HRESULT WINAPI info_qi(Info *i,REFIID iid,void **out){return qi(i->owner,iid,out);}
static ULONG WINAPI info_add(Info *i){return addref(i->owner);}
static ULONG WINAPI info_release(Info *i){return release(i->owner);}
static HRESULT WINAPI info_iids(Info *i,ULONG *n,IID **p){return get_iids(i->owner,n,p);}
static HRESULT WINAPI info_name(Info *i,HSTRING *p){return get_name(i->owner,p);}
static HRESULT WINAPI info_trust(Info *i,TrustLevel *p){return get_trust(i->owner,p);}
static HRESULT WINAPI info_id(Info *i,UINT32 *p){(void)i;if(!p)return E_POINTER;*p=1;return S_OK;}
static HRESULT WINAPI info_status(Info *i,INT32 *p){if(!p)return E_POINTER;if(i->owner->closed)return RO_E_CLOSED;*p=i->owner->async_status;return S_OK;}
static HRESULT WINAPI info_error(Info *i,HRESULT *p){if(!p)return E_POINTER;*p=i->owner->async_error;return S_OK;}
static HRESULT WINAPI info_cancel(Info *i){EnterCriticalSection(&i->owner->lock);if(i->owner->async_status==0){i->owner->async_status=2;i->owner->async_error=HRESULT_FROM_WIN32(ERROR_CANCELLED);}LeaveCriticalSection(&i->owner->lock);return S_OK;}
static HRESULT WINAPI info_close(Info *i){EnterCriticalSection(&i->owner->lock);i->owner->closed=TRUE;LeaveCriticalSection(&i->owner->lock);return S_OK;}
#include "collections-streams.inc"
#include "events.inc"
#include "commands.inc"
#include "datareader.inc"
#include "generated-traces.h"
#include "datareader-vtables.inc"
static const void *vt_factory[]={BASE,T(activate)};
static const void *vt_statics[]={FACET_BASE,T(request_facet)};
static const void *vt_manager[]={BASE,T(current),T(sessions),T(event_current),T(event_remove),T(event_sessions),T(event_remove)};
static const void *vt_session[]={BASE,T(source),T(properties),T(timeline),T(playback),
    T(cmd_play),T(cmd_pause),T(unsupported_command),T(unsupported_command),T(unsupported_command),T(unsupported_command),
    T(cmd_next),T(cmd_previous),T(unsupported_command),T(unsupported_command),T(cmd_toggle),
    T(unsupported_i32),T(unsupported_double),T(unsupported_i32),T(cmd_seek),T(event_timeline),T(event_remove),T(event_playback),T(event_remove),T(event_properties),T(event_remove)};
static const void *vt_properties[]={BASE,T(title),T(empty_string),T(empty_string),T(artist),T(album),T(zero_i32),T(genres),T(zero_i32),T(unknown_optional),T(thumbnail)};
static const void *vt_playback[]={BASE,T(controls),T(status),T(unknown_optional),T(unknown_optional),T(unknown_optional),T(unknown_optional)};
static const void *vt_controls[]={BASE,T(can_play),T(can_pause),T(disabled),T(disabled),T(disabled),T(disabled),T(can_next),T(can_previous),T(disabled),T(disabled),T(can_toggle),T(disabled),T(disabled),T(disabled),T(can_seek)};
static const void *vt_timeline[]={BASE,T(zero_time),T(duration),T(zero_time),T(duration),T(position),T(observed)};
static const void *vt_vector[]={BASE,T(at),T(size),T(index_of),T(many)};
static const void *vt_string_vector[]={BASE,T(string_at),T(string_size),T(string_index),T(string_many)};
static const void *vt_iterable[]={FACET_BASE,T(iterable_first)};
static const void *vt_iterator[]={BASE,T(iterator_current),T(iterator_has),T(iterator_next),T(iterator_many)};
static const void *vt_event_args[]={BASE};
static const void *vt_async[]={BASE,T(put_completed),T(get_completed),T(results)};
static const void *vt_info[]={FACET_BASE,T(info_id),T(info_status),T(info_error),T(info_cancel),T(info_close)};
static const void *vt_stream_reference[]={BASE,T(open_read)};
static const void *vt_stream[]={BASE};
static const void *vt_ras[]={FACET_BASE,T(stream_size),T(stream_put_size),T(stream_input_at),T(stream_output_at),T(stream_position),T(stream_seek),T(stream_clone),T(stream_can_read),T(stream_can_write)};
static const void *vt_input[]={FACET_BASE,T(stream_read)};
static const void *vt_content[]={FACET_BASE,T(stream_content_type)};
static const void *vt_closable[]={FACET_BASE,T(stream_close)};
static const void *vt_async_progress[]={BASE,T(put_progress),T(get_progress),T(put_completed),T(get_completed),T(results)};
__declspec(dllexport) HRESULT WINAPI DllGetActivationFactory(HSTRING name,IActivationFactory **out) {
    if(!out)return E_POINTER;*out=NULL;const WCHAR *text=WindowsGetStringRawBuffer(name,NULL);
    if(!wcscmp(text,L"Windows.Storage.Streams.DataReader"))return dr_activation(out);
    if(wcscmp(text,L"Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager"))return CLASS_E_CLASSNOTAVAILABLE;
    HRESULT result=return_object(FACTORY,NULL,(void **)out);trace_result("DllGetActivationFactory",result);return result;
}
HRESULT WINAPI DllCanUnloadNow(void){return live_objects?S_FALSE:S_OK;}
BOOL WINAPI DllMain(HINSTANCE module,DWORD reason,void *reserved){(void)reserved;if(reason==DLL_PROCESS_ATTACH)DisableThreadLibraryCalls(module);return TRUE;}
