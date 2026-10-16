typedef struct CommandJob {Obj *operation;Snapshot snapshot;UINT32 command;INT64 value;WCHAR directory[32768];} CommandJob;
static void complete_async(Obj *o,HRESULT error,BOOLEAN value) {
    IAgileReference *agile=NULL;LONG status;
    EnterCriticalSection(&o->lock);
    if(o->async_status==0){o->async_error=error;o->bool_result=value;o->async_status=FAILED(error)?3:1;}
    status=o->async_status;
    if(!o->closed&&o->handler_agile){agile=o->handler_agile;IAgileReference_AddRef(agile);}
    LeaveCriticalSection(&o->lock);
    if(agile){
        IUnknown *handler=NULL;HRESULT hr=IAgileReference_Resolve(agile,o->kind==ASYNC_U32?&iid_handler_u32:&iid_handler_bool,(void **)&handler);
        if(SUCCEEDED(hr)) {
            typedef HRESULT (WINAPI *Invoke)(void *,void *,INT32);
            hr=((Invoke)(*(void ***)handler)[3])(handler,o,status);IUnknown_Release(handler);
        }
        trace_result("Async.Completed.Invoke",hr);IAgileReference_Release(agile);
    }
}
static DWORD WINAPI command_worker(void *parameter) {
    HMODULE module=NULL;GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS,(const WCHAR *)(uintptr_t)command_worker,&module);
    CommandJob *job=parameter;Obj *operation=job->operation;
    HRESULT initialized=CoInitializeEx(NULL,COINIT_MULTITHREADED),hr=S_OK;BOOLEAN performed=FALSE;
    WCHAR filename[64],request[32768],temporary[32768],ack[32768];GUID id;
    hr=CoCreateGuid(&id);
    if(SUCCEEDED(hr)) {
        swprintf(filename,64,L"%08lx-%04x-%04x-%02x%02x-%02x%02x%02x%02x%02x%02x",id.Data1,id.Data2,id.Data3,
            id.Data4[0],id.Data4[1],id.Data4[2],id.Data4[3],id.Data4[4],id.Data4[5],id.Data4[6],id.Data4[7]);
        swprintf(request,32768,L"%ls\\%ls.req",job->directory,filename);
        swprintf(temporary,32768,L"%ls\\%ls.tmp",job->directory,filename);
        swprintf(ack,32768,L"%ls\\%ls.ack",job->directory,filename);
        struct {char magic[8];UINT32 version,command;INT64 value;WCHAR bundle[128];} data={0};
        memcpy(data.magic,"LWMCMD01",8);data.version=1;data.command=job->command;data.value=job->value;
        memcpy(data.bundle,job->snapshot.bundle,sizeof(data.bundle));
        HANDLE file=CreateFileW(temporary,GENERIC_WRITE,0,NULL,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,NULL);DWORD written=0;
        if(file==INVALID_HANDLE_VALUE)hr=HRESULT_FROM_WIN32(GetLastError());
        else {
            if(!WriteFile(file,&data,sizeof(data),&written,NULL)||written!=sizeof(data))hr=E_FAIL;
            FlushFileBuffers(file);CloseHandle(file);
            if(SUCCEEDED(hr)&&!MoveFileExW(temporary,request,MOVEFILE_WRITE_THROUGH))hr=HRESULT_FROM_WIN32(GetLastError());
            DeleteFileW(temporary);
        }
        if(SUCCEEDED(hr)) {
            ULONGLONG deadline=GetTickCount64()+5000;hr=HRESULT_FROM_WIN32(ERROR_TIMEOUT);
            while(GetTickCount64()<deadline) {
                if(operation->closed||operation->async_status==2){hr=HRESULT_FROM_WIN32(ERROR_CANCELLED);break;}
                HANDLE response=CreateFileW(ack,GENERIC_READ,FILE_SHARE_READ|FILE_SHARE_DELETE,NULL,OPEN_EXISTING,0,NULL);
                if(response!=INVALID_HANDLE_VALUE) {
                    struct {char magic[8];UINT32 version,ok,error,flags;} result;DWORD read=0;
                    BOOL valid=ReadFile(response,&result,sizeof(result),&read,NULL)&&read==sizeof(result);CloseHandle(response);
                    if(!valid||memcmp(result.magic,"LWMACK01",8)||result.version!=1)hr=E_INVALIDARG;
                    else if((result.flags&2)&&!(job->snapshot.flags&2))hr=E_ACCESSDENIED;
                    else {hr=(HRESULT)result.error;performed=!!result.ok;}
                    DeleteFileW(ack);break;
                }
                Sleep(40);
            }
            DeleteFileW(request);
        }
    }
    complete_async(operation,hr,performed);trace_result("Command.TransportComplete",hr);
    HeapFree(GetProcessHeap(),0,job);release(operation);
    if(SUCCEEDED(initialized))CoUninitialize();if(module)FreeLibraryAndExitThread(module,0);return 0;
}
static HRESULT native_command(Obj *o,UINT32 command,INT64 value,void **out) {
    if(!out)return E_POINTER;*out=NULL;if(value<0)return E_INVALIDARG;
    Snapshot current;HRESULT hr=refresh_session(o,&current);if(FAILED(hr))return hr;
    WCHAR directory[32768];DWORD length=GetEnvironmentVariableW(L"LWMEDIA_COMMAND_DIR",directory,32700);
    if(command<1||command>6||!length||length>=32700||!(current.flags&(1u<<(7+command))))return unsupported_command(o,out);
    hr=make_async(NULL,&iid_async_bool,out);if(FAILED(hr))return hr;
    Obj *operation=*out;operation->kind=ASYNC_BOOL;operation->async_status=0;
    CommandJob *job=HeapAlloc(GetProcessHeap(),HEAP_ZERO_MEMORY,sizeof(*job));
    if(!job){operation->async_status=3;operation->async_error=E_OUTOFMEMORY;return S_OK;}
    job->operation=operation;job->snapshot=current;job->command=command;job->value=value;wcscpy(job->directory,directory);
    addref(operation);HANDLE worker=CreateThread(NULL,0,command_worker,job,0,NULL);
    if(worker)CloseHandle(worker);
    else {HRESULT error=HRESULT_FROM_WIN32(GetLastError());HeapFree(GetProcessHeap(),0,job);release(operation);operation->async_status=3;operation->async_error=error;}
    return S_OK;
}
static HRESULT command_enabled(Obj *o,UINT32 command,BOOLEAN *out) {
    if(!out)return E_POINTER;WCHAR directory[32768];DWORD length=GetEnvironmentVariableW(L"LWMEDIA_COMMAND_DIR",directory,32768);
    *out=length>0&&length<32700&&(o->snapshot.flags&(1u<<(7+command)));return S_OK;
}
static HRESULT WINAPI can_play(Obj *o,BOOLEAN *out){return command_enabled(o,1,out);}
static HRESULT WINAPI can_pause(Obj *o,BOOLEAN *out){return command_enabled(o,2,out);}
static HRESULT WINAPI can_next(Obj *o,BOOLEAN *out){return command_enabled(o,3,out);}
static HRESULT WINAPI can_previous(Obj *o,BOOLEAN *out){return command_enabled(o,4,out);}
static HRESULT WINAPI can_toggle(Obj *o,BOOLEAN *out){return command_enabled(o,5,out);}
static HRESULT WINAPI can_seek(Obj *o,BOOLEAN *out){return command_enabled(o,6,out);}
