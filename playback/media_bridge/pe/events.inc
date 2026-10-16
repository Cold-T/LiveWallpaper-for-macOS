struct EventRegistration { INT64 token; int type; IAgileReference *agile; EventRegistration *next; };
static LONG64 next_event_token;
static const GUID *event_handler_iids[]={&iid_event_handler_0,&iid_event_handler_1,&iid_event_handler_2,&iid_event_handler_3,&iid_event_handler_4};
static HRESULT load_artwork(const Snapshot *,Blob **);
static BOOL try_addref(Obj *o) {
    LONG old=o->refs;
    while(old>0) {LONG seen=InterlockedCompareExchange(&o->refs,old+1,old);if(seen==old)return TRUE;old=seen;}
    return FALSE;
}
static UINT64 artwork_hash(const Snapshot *s) {
    Blob *blob=NULL;if(FAILED(load_artwork(s,&blob))||!blob)return 0;
    UINT64 hash=1469598103934665603ULL;
    for(DWORD i=0;i<blob->length;i++){hash^=blob->data[i];hash*=1099511628211ULL;}
    if(!InterlockedDecrement(&blob->refs))HeapFree(GetProcessHeap(),0,blob);
    return hash;
}
static const WCHAR *event_arg_iids[]={
    L"{6969cb39-0bfa-5fe0-8d73-09cc5e5408e1}",L"{bbf0cd32-42c4-5a58-b317-f34bbfbd26e0}",
    L"{29033a2f-c923-5a77-bcaf-055ff415ad32}",L"{786756c2-bc0d-50a5-8807-054291fef139}",
    L"{7d3741cb-adf0-5cef-91ba-cfabcdd77678}"};
static void dispatch_event(Obj *o,int type) {
    IAgileReference **handlers=NULL;ULONG count=0,index=0;
    EnterCriticalSection(&o->lock);
    for(EventRegistration *r=o->events;r;r=r->next)if(r->type==type)count++;
    if(count)handlers=HeapAlloc(GetProcessHeap(),HEAP_ZERO_MEMORY,sizeof(*handlers)*count);
    if(handlers)for(EventRegistration *r=o->events;r;r=r->next)if(r->type==type){handlers[index++]=r->agile;IAgileReference_AddRef(r->agile);}
    LeaveCriticalSection(&o->lock);
    if(!handlers)return;
    Obj *args=create(EVENT_ARGS,NULL);
    if(args)CLSIDFromString(event_arg_iids[type],&args->iid);
    for(ULONG i=0;i<index;i++) {
        IUnknown *handler=NULL;
        HRESULT hr=IAgileReference_Resolve(handlers[i],event_handler_iids[type],(void **)&handler);
        if(SUCCEEDED(hr)&&args){
            typedef HRESULT (WINAPI *Invoke)(void *,void *,void *);
            hr=((Invoke)(*(void ***)handler)[3])(handler,o,args);
        }
        trace_result("Event.Invoke",hr);
        if(handler)IUnknown_Release(handler);
        IAgileReference_Release(handlers[i]);
    }
    if(args)release(args);HeapFree(GetProcessHeap(),0,handlers);
}
static DWORD WINAPI event_worker(void *parameter) {
    HMODULE module=NULL;GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS,(const WCHAR *)(uintptr_t)event_worker,&module);
    Obj *o=parameter;HRESULT initialized=CoInitializeEx(NULL,COINIT_MULTITHREADED);
    Snapshot last=o->snapshot;UINT64 last_art=artwork_hash(&last);
    while(WaitForSingleObject(o->stop,150)==WAIT_TIMEOUT) {
        if(!try_addref(o))break;
        Snapshot now={0};if(!read_snapshot(&now))memset(&now,0,sizeof(now));
        if(o->kind==SESSION&&wcscmp(o->snapshot.bundle,now.bundle))memset(&now,0,sizeof(now));
        BOOL identity=!!(last.flags&1)!=!!(now.flags&1)||wcscmp(last.bundle,now.bundle);
        UINT64 art=now.generation!=last.generation?artwork_hash(&now):last_art;
        if(o->kind==MANAGER) {if(identity){dispatch_event(o,0);dispatch_event(o,1);}}
        else {
            if(identity||last.duration!=now.duration||last.position!=now.position||last.observed!=now.observed)dispatch_event(o,2);
            if(identity||last.state!=now.state||((last.flags^now.flags)&0x3f00))dispatch_event(o,3);
            if(identity||wcscmp(last.title,now.title)||wcscmp(last.artist,now.artist)||wcscmp(last.album,now.album)||art!=last_art)dispatch_event(o,4);
        }
        last=now;last_art=art;
        if(!release(o)){if(SUCCEEDED(initialized))CoUninitialize();if(module)FreeLibraryAndExitThread(module,0);return 0;}
    }
    if(SUCCEEDED(initialized))CoUninitialize();if(module)FreeLibraryAndExitThread(module,0);return 0;
}
static HRESULT event_register(Obj *o,int type,void *handler,INT64 *token) {
    if(!handler||!token)return E_POINTER;*token=0;
    EventRegistration *r=HeapAlloc(GetProcessHeap(),HEAP_ZERO_MEMORY,sizeof(*r));if(!r)return E_OUTOFMEMORY;
    HRESULT hr=create_agile(event_handler_iids[type],(IUnknown *)handler,&r->agile);
    if(FAILED(hr)){HeapFree(GetProcessHeap(),0,r);return hr;}
    r->type=type;r->token=InterlockedIncrement64(&next_event_token);
    EnterCriticalSection(&o->lock);r->next=o->events;o->events=r;
    if(!o->worker) {
        if(o->kind==MANAGER&&!read_snapshot(&o->snapshot))memset(&o->snapshot,0,sizeof(o->snapshot));
        o->stop=CreateEventW(NULL,TRUE,FALSE,NULL);
        if(o->stop)o->worker=CreateThread(NULL,0,event_worker,o,0,&o->worker_id);
        if(!o->worker) {
            hr=HRESULT_FROM_WIN32(GetLastError());o->events=r->next;
            if(o->stop){CloseHandle(o->stop);o->stop=NULL;}
        }
    }
    if(SUCCEEDED(hr))*token=r->token;LeaveCriticalSection(&o->lock);
    if(FAILED(hr)){IAgileReference_Release(r->agile);HeapFree(GetProcessHeap(),0,r);}
    return hr;
}
static HRESULT event_unregister(Obj *o,INT64 token) {
    EnterCriticalSection(&o->lock);EventRegistration **link=&o->events,*found=NULL;
    while(*link){if((*link)->token==token){found=*link;*link=found->next;break;}link=&(*link)->next;}
    LeaveCriticalSection(&o->lock);
    if(found){IAgileReference_Release(found->agile);HeapFree(GetProcessHeap(),0,found);}return S_OK;
}
static void stop_events(Obj *o) {
    if(o->stop)SetEvent(o->stop);
    if(o->worker&&o->worker_id!=GetCurrentThreadId())WaitForSingleObject(o->worker,INFINITE);
    if(o->worker)CloseHandle(o->worker);if(o->stop)CloseHandle(o->stop);
    EventRegistration *r=o->events;
    while(r){EventRegistration *next=r->next;IAgileReference_Release(r->agile);HeapFree(GetProcessHeap(),0,r);r=next;}
}
