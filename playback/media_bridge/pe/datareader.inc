/* Independent DataReader implementation. Windows11 Wine source has no class.
 * Official ABI: microsoft/windows-rs Windows/Storage/Streams/mod.rs.
 * Input is consumed through IInputStream::ReadAsync, never fabricated bytes. */
#define DR_LIMIT (16u*1024u*1024u)
static const GUID dr_iid={0xe2b50029,0xb4c1,0x4314,{0xa4,0xb8,0xfb,0x81,0x3a,0x2f,0x27,0x5e}};
static const GUID dr_factory_iid={0xd7527847,0x57da,0x4e15,{0x91,0x4c,0x06,0x80,0x66,0x99,0xa0,0x98}};
static const GUID dr_statics_iid={0x11fcbfc8,0xf93a,0x471b,{0xb1,0x21,0xf3,0x79,0xe3,0x49,0x31,0x3c}};
static const GUID dr_buffer_iid={0x905a0fe0,0xbc53,0x11df,{0x8c,0x49,0x00,0x1e,0x4f,0xc6,0x86,0xda}};
typedef struct DR DR;
typedef struct DRFacet {const void **vt;DR *owner;} DRFacet;
struct DR {const void **vt;LONG refs;int kind;CRITICAL_SECTION lock;DRFacet factory,statics,closable,bytes;
    IAgileReference *input;BYTE *data;UINT32 length,capacity,position;INT32 encoding,order,options;BOOL closed,loading,resident_input;};
static const void *dr_vt_activation[],*dr_vt_factory[],*dr_vt_statics[],*dr_vt_reader[],*dr_vt_buffer[],*dr_vt_bytes[],*dr_vt_close[];
static ULONG WINAPI dr_add(DR *d){return InterlockedIncrement(&d->refs);}
static ULONG WINAPI dr_release(DR *d){ULONG n=InterlockedDecrement(&d->refs);if(!n){if(d->input)IAgileReference_Release(d->input);HeapFree(GetProcessHeap(),0,d->data);DeleteCriticalSection(&d->lock);HeapFree(GetProcessHeap(),0,d);InterlockedDecrement(&live_objects);}return n;}
static HRESULT WINAPI dr_qi(DR *d,REFIID iid,void **out){
    if(!out)return E_POINTER;*out=NULL;
    if(IsEqualIID(iid,&IID_IUnknown)||IsEqualIID(iid,&iid_agile)||IsEqualIID(iid,&iid_inspectable)||
       (d->kind==0&&IsEqualIID(iid,&iid_factory))||(d->kind==1&&IsEqualIID(iid,&dr_iid))||(d->kind==2&&IsEqualIID(iid,&dr_buffer_iid)))*out=d;
    else if(d->kind==0&&IsEqualIID(iid,&dr_factory_iid))*out=&d->factory;
    else if(d->kind==0&&IsEqualIID(iid,&dr_statics_iid))*out=&d->statics;
    else if(d->kind==1&&IsEqualIID(iid,&iid_closable))*out=&d->closable;
    else if(d->kind==2&&IsEqualIID(iid,&iid_buffer_bytes))*out=&d->bytes;
    else {trace_iid_result("DataReader.QueryInterface",iid,E_NOINTERFACE);return E_NOINTERFACE;}
    dr_add(d);trace_iid_result("DataReader.QueryInterface",iid,S_OK);return S_OK;
}
static HRESULT WINAPI dr_iids(DR *d,ULONG *n,IID **out){
    if(!n||!out)return E_POINTER;*n=0;*out=CoTaskMemAlloc(3*sizeof(IID));if(!*out)return E_OUTOFMEMORY;
    if(d->kind==0){(*out)[0]=iid_factory;(*out)[1]=dr_factory_iid;(*out)[2]=dr_statics_iid;*n=3;}
    else{(*out)[0]=d->kind==1?dr_iid:dr_buffer_iid;*n=1;if(d->kind==1){(*out)[1]=iid_closable;*n=2;}}return S_OK;
}
static HRESULT WINAPI dr_name(DR *d,HSTRING *out){return string_value(d->kind==2?L"Windows.Storage.Streams.Buffer":L"Windows.Storage.Streams.DataReader",out);}
static HRESULT WINAPI dr_trust(DR *d,TrustLevel *out){(void)d;if(!out)return E_POINTER;*out=BaseTrust;return S_OK;}
static HRESULT WINAPI drf_qi(DRFacet *f,REFIID iid,void **out){return dr_qi(f->owner,iid,out);}
static ULONG WINAPI drf_add(DRFacet *f){return dr_add(f->owner);}
static ULONG WINAPI drf_release(DRFacet *f){return dr_release(f->owner);}
static HRESULT WINAPI drf_iids(DRFacet *f,ULONG *n,IID **out){return dr_iids(f->owner,n,out);}
static HRESULT WINAPI drf_name(DRFacet *f,HSTRING *out){return dr_name(f->owner,out);}
static HRESULT WINAPI drf_trust(DRFacet *f,TrustLevel *out){return dr_trust(f->owner,out);}
static DR *dr_create(int kind,UINT32 capacity){
    DR *d=HeapAlloc(GetProcessHeap(),HEAP_ZERO_MEMORY,sizeof(*d));if(!d)return NULL;
    d->refs=1;d->kind=kind;d->capacity=capacity;d->order=1; /* WinRT default BigEndian. */InitializeCriticalSection(&d->lock);
    d->vt=kind==0?dr_vt_activation:kind==1?dr_vt_reader:dr_vt_buffer;
    d->factory.vt=dr_vt_factory;d->statics.vt=dr_vt_statics;d->closable.vt=dr_vt_close;d->bytes.vt=dr_vt_bytes;
    d->factory.owner=d->statics.owner=d->closable.owner=d->bytes.owner=d;
    if(capacity){d->data=HeapAlloc(GetProcessHeap(),0,capacity);if(!d->data){DeleteCriticalSection(&d->lock);HeapFree(GetProcessHeap(),0,d);return NULL;}}
    InterlockedIncrement(&live_objects);return d;
}
static HRESULT dr_activation(IActivationFactory **out){DR *d=dr_create(0,0);*out=(IActivationFactory *)d;return d?S_OK:E_OUTOFMEMORY;}
static HRESULT WINAPI dr_activate(DR *d,void **out){(void)d;if(!out)return E_POINTER;*out=NULL;return E_NOTIMPL;}
static HRESULT WINAPI dr_factory_create(DRFacet *f,void *input,void **out){
    (void)f;if(!out||!input)return E_POINTER;*out=NULL;DR *d=dr_create(1,0);if(!d)return E_OUTOFMEMORY;
    /* Only this DLL's exact IInputStream facet is known to contain a resident
     * immutable Blob and to complete ReadAsync inline. Foreign/proxy vtables
     * stay on the asynchronous path; do not inspect their private layout. */
    d->resident_input=*(const void ***)input==vt_input;
    HRESULT hr=create_agile(&iid_input,(IUnknown *)input,&d->input);if(FAILED(hr)){dr_release(d);return hr;}*out=d;return S_OK;
}
static HRESULT WINAPI dr_capacity(DR *d,UINT32 *out){if(!out)return E_POINTER;*out=d->capacity;return S_OK;}
static HRESULT WINAPI dr_length(DR *d,UINT32 *out){if(!out)return E_POINTER;*out=d->length;return S_OK;}
static HRESULT WINAPI dr_put_length(DR *d,UINT32 value){if(value>d->capacity)return E_INVALIDARG;d->length=value;return S_OK;}
static HRESULT WINAPI dr_buffer_bytes(DRFacet *f,BYTE **out){if(!out)return E_POINTER;*out=f->owner->data;return S_OK;}
static HRESULT dr_copy_buffer(void *buffer,DR **out){
    *out=NULL;UINT32 length=0;IUnknown *access=NULL;
    typedef HRESULT(WINAPI *Length)(void *,UINT32 *);typedef HRESULT(WINAPI *Bytes)(void *,BYTE **);
    HRESULT hr=((Length)(*(void ***)buffer)[7])(buffer,&length);if(FAILED(hr))return hr;if(length>DR_LIMIT)return E_INVALIDARG;
    hr=IUnknown_QueryInterface((IUnknown *)buffer,&iid_buffer_bytes,(void **)&access);if(FAILED(hr))return hr;
    BYTE *bytes=NULL;hr=((Bytes)(*(void ***)access)[3])(access,&bytes);
    if(SUCCEEDED(hr)&&length&&!bytes)hr=E_POINTER;
    if(SUCCEEDED(hr)){DR *d=dr_create(1,length);if(!d)hr=E_OUTOFMEMORY;else {if(length)memcpy(d->data,bytes,length);d->length=length;*out=d;}}
    IUnknown_Release(access);return hr;
}
static HRESULT WINAPI dr_from_buffer(DRFacet *f,void *buffer,void **out){(void)f;if(!out||!buffer)return E_POINTER;*out=NULL;return dr_copy_buffer(buffer,(DR **)out);}
static HRESULT WINAPI dr_unconsumed(DR *d,UINT32 *out){if(!out)return E_POINTER;EnterCriticalSection(&d->lock);HRESULT hr=d->closed?RO_E_CLOSED:S_OK;*out=d->length-d->position;LeaveCriticalSection(&d->lock);return hr;}
static HRESULT dr_get_setting(DR *d,int which,INT32 *out){if(!out)return E_POINTER;EnterCriticalSection(&d->lock);HRESULT hr=d->closed?RO_E_CLOSED:S_OK;*out=which==0?d->encoding:which==1?d->order:d->options;LeaveCriticalSection(&d->lock);return hr;}
static HRESULT dr_set_setting(DR *d,int which,INT32 value){if(value<0||value>(which==0?2:which==1?1:3))return E_INVALIDARG;EnterCriticalSection(&d->lock);HRESULT hr=d->closed?RO_E_CLOSED:S_OK;if(SUCCEEDED(hr)){if(which==0)d->encoding=value;else if(which==1)d->order=value;else d->options=value;}LeaveCriticalSection(&d->lock);return hr;}
static HRESULT WINAPI dr_encoding(DR *d,INT32 *out){return dr_get_setting(d,0,out);}
static HRESULT WINAPI dr_put_encoding(DR *d,INT32 value){return dr_set_setting(d,0,value);}
static HRESULT WINAPI dr_order(DR *d,INT32 *out){return dr_get_setting(d,1,out);}
static HRESULT WINAPI dr_put_order(DR *d,INT32 value){return dr_set_setting(d,1,value);}
static HRESULT WINAPI dr_options(DR *d,INT32 *out){return dr_get_setting(d,2,out);}
static HRESULT WINAPI dr_put_options(DR *d,INT32 value){return dr_set_setting(d,2,value);}
static HRESULT dr_take(DR *d,UINT32 count,BYTE *out,BOOL numeric){
    if(count&&!out)return E_POINTER;EnterCriticalSection(&d->lock);HRESULT hr=S_OK;
    if(d->closed)hr=RO_E_CLOSED;else if(d->loading)hr=HRESULT_FROM_WIN32(ERROR_INVALID_OPERATION);else if(count>d->length-d->position)hr=E_BOUNDS;
    else{if(numeric&&d->order){for(UINT32 i=0;i<count;i++)out[i]=d->data[d->position+count-1-i];}else if(count)memcpy(out,d->data+d->position,count);d->position+=count;}
    LeaveCriticalSection(&d->lock);return hr;
}
static HRESULT WINAPI dr_read_byte(DR *d,BYTE *out){return dr_take(d,1,out,FALSE);}
static HRESULT WINAPI dr_read_bytes(DR *d,UINT32 count,BYTE *out){return dr_take(d,count,out,FALSE);}
static HRESULT WINAPI dr_read_bool(DR *d,BOOLEAN *out){if(!out)return E_POINTER;BYTE value=0;HRESULT hr=dr_take(d,1,&value,FALSE);if(SUCCEEDED(hr))*out=!!value;return hr;}
static HRESULT WINAPI dr_read_i16(DR *d,INT16 *out){return dr_take(d,2,(BYTE *)out,TRUE);}
static HRESULT WINAPI dr_read_i32(DR *d,INT32 *out){return dr_take(d,4,(BYTE *)out,TRUE);}
static HRESULT WINAPI dr_read_i64(DR *d,INT64 *out){return dr_take(d,8,(BYTE *)out,TRUE);}
static HRESULT WINAPI dr_read_u16(DR *d,UINT16 *out){return dr_take(d,2,(BYTE *)out,TRUE);}
static HRESULT WINAPI dr_read_u32(DR *d,UINT32 *out){return dr_take(d,4,(BYTE *)out,TRUE);}
static HRESULT WINAPI dr_read_u64(DR *d,UINT64 *out){return dr_take(d,8,(BYTE *)out,TRUE);}
static HRESULT WINAPI dr_read_float(DR *d,float *out){return dr_take(d,4,(BYTE *)out,TRUE);}
static HRESULT WINAPI dr_read_double(DR *d,double *out){return dr_take(d,8,(BYTE *)out,TRUE);}
static HRESULT WINAPI dr_read_guid(DR *d,GUID *out){
    if(!out)return E_POINTER;BYTE raw[16];HRESULT hr=dr_take(d,16,raw,FALSE);if(FAILED(hr))return hr;
    memcpy(out,raw,16);if(d->order){out->Data1=((UINT32)raw[0]<<24)|((UINT32)raw[1]<<16)|((UINT32)raw[2]<<8)|raw[3];out->Data2=((UINT16)raw[4]<<8)|raw[5];out->Data3=((UINT16)raw[6]<<8)|raw[7];}return S_OK;
}
static HRESULT WINAPI dr_read_buffer(DR *d,UINT32 count,void **out){if(!out)return E_POINTER;*out=NULL;if(count>DR_LIMIT)return E_INVALIDARG;DR *b=dr_create(2,count);if(!b)return E_OUTOFMEMORY;HRESULT hr=dr_take(d,count,b->data,FALSE);if(FAILED(hr)){dr_release(b);return hr;}b->length=count;*out=b;return S_OK;}
static HRESULT WINAPI dr_read_string(DR *d,UINT32 count,HSTRING *out){
    if(!out)return E_POINTER;*out=NULL;EnterCriticalSection(&d->lock);HRESULT hr=S_OK;UINT64 bytes=(UINT64)count*(d->encoding?2:1);
    if(d->closed)hr=RO_E_CLOSED;else if(d->loading)hr=HRESULT_FROM_WIN32(ERROR_INVALID_OPERATION);else if(bytes>d->length-d->position)hr=E_BOUNDS;
    else if(!count)hr=WindowsCreateString(L"",0,out);
    else if(d->encoding){WCHAR *text=HeapAlloc(GetProcessHeap(),0,(SIZE_T)bytes);if(!text)hr=E_OUTOFMEMORY;else{for(UINT32 i=0;i<count;i++){BYTE *p=d->data+d->position+2*i;text[i]=d->encoding==1?p[0]|((UINT16)p[1]<<8):p[1]|((UINT16)p[0]<<8);}hr=WindowsCreateString(text,count,out);HeapFree(GetProcessHeap(),0,text);}}
    else {int length=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,(char *)d->data+d->position,count,NULL,0);if(!length)hr=HRESULT_FROM_WIN32(GetLastError());else{WCHAR *text=HeapAlloc(GetProcessHeap(),0,length*sizeof(WCHAR));if(!text)hr=E_OUTOFMEMORY;else{MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,(char *)d->data+d->position,count,text,length);hr=WindowsCreateString(text,length,out);HeapFree(GetProcessHeap(),0,text);}}}
    if(SUCCEEDED(hr))d->position+=(UINT32)bytes;LeaveCriticalSection(&d->lock);return hr;
}
static HRESULT WINAPI dr_detach_buffer(DR *d,void **out){if(!out)return E_POINTER;*out=NULL;EnterCriticalSection(&d->lock);HRESULT hr=dr_read_buffer(d,d->length-d->position,out);LeaveCriticalSection(&d->lock);return hr;}
static HRESULT WINAPI dr_detach_stream(DR *d,void **out){if(!out)return E_POINTER;*out=NULL;EnterCriticalSection(&d->lock);HRESULT hr=d->closed?RO_E_CLOSED:d->loading?HRESULT_FROM_WIN32(ERROR_INVALID_OPERATION):S_OK;if(SUCCEEDED(hr)&&d->input){hr=IAgileReference_Resolve(d->input,&iid_input,out);if(SUCCEEDED(hr)){IAgileReference_Release(d->input);d->input=NULL;}}LeaveCriticalSection(&d->lock);return hr;}
static HRESULT WINAPI dr_close(DRFacet *f){DR *d=f->owner;EnterCriticalSection(&d->lock);d->closed=TRUE;if(d->input){IUnknown *input=NULL,*closable=NULL;if(SUCCEEDED(IAgileReference_Resolve(d->input,&iid_input,(void **)&input))){if(SUCCEEDED(IUnknown_QueryInterface(input,&iid_closable,(void **)&closable))){typedef HRESULT(WINAPI *Close)(void *);((Close)(*(void ***)closable)[6])(closable);IUnknown_Release(closable);}IUnknown_Release(input);}IAgileReference_Release(d->input);d->input=NULL;}LeaveCriticalSection(&d->lock);return S_OK;}
typedef struct DRLoad {DR *reader;Obj *operation;UINT32 count;INT32 options;IAgileReference *input;} DRLoad;
static void dr_load_transfer(DRLoad *job){DR *d=job->reader;Obj *operation=job->operation;UINT32 loaded=0;
    HRESULT hr=S_OK;IUnknown *input=NULL,*async=NULL,*info=NULL,*result=NULL;DR *buffer=dr_create(2,job->count);
    if(!buffer)hr=E_OUTOFMEMORY;
    if(SUCCEEDED(hr))hr=IAgileReference_Resolve(job->input,&iid_input,(void **)&input);
    if(SUCCEEDED(hr)){typedef HRESULT(WINAPI *Read)(void *,void *,UINT32,INT32,void **);hr=((Read)(*(void ***)input)[6])(input,buffer,job->count,job->options,(void **)&async);}
    if(SUCCEEDED(hr)&&!async)hr=E_UNEXPECTED;
    if(SUCCEEDED(hr))hr=IUnknown_QueryInterface(async,&iid_async_info,(void **)&info);
    if(SUCCEEDED(hr)){
        typedef HRESULT(WINAPI *Status)(void *,INT32 *);INT32 status=0;ULONGLONG deadline=GetTickCount64()+5000;
        do{hr=((Status)(*(void ***)info)[7])(info,&status);if(FAILED(hr)||status)break;if(operation->closed||operation->async_status==2){hr=HRESULT_FROM_WIN32(ERROR_CANCELLED);break;}if(GetTickCount64()>=deadline){hr=HRESULT_FROM_WIN32(ERROR_TIMEOUT);break;}Sleep(10);}while(1);
        if(SUCCEEDED(hr)){typedef HRESULT(WINAPI *Results)(void *,void **);hr=((Results)(*(void ***)async)[10])(async,(void **)&result);}
    }
    DR *copy=NULL;if(SUCCEEDED(hr)&&!result)hr=E_UNEXPECTED;if(SUCCEEDED(hr))hr=dr_copy_buffer(result,&copy);
    EnterCriticalSection(&d->lock);
    if(SUCCEEDED(hr)&&(d->closed||operation->closed||operation->async_status==2))hr=RO_E_CLOSED;
    if(SUCCEEDED(hr)){
        UINT32 old=d->length-d->position;loaded=copy->length;
        if((UINT64)old+loaded>DR_LIMIT)hr=E_INVALIDARG;
        else {BYTE *bytes=(old+loaded)?HeapAlloc(GetProcessHeap(),0,old+loaded):NULL;if(old+loaded&&!bytes)hr=E_OUTOFMEMORY;else{if(old)memcpy(bytes,d->data+d->position,old);if(loaded)memcpy(bytes+old,copy->data,loaded);HeapFree(GetProcessHeap(),0,d->data);d->data=bytes;d->capacity=d->length=old+loaded;d->position=0;}}
    }
    d->loading=FALSE;LeaveCriticalSection(&d->lock);
    EnterCriticalSection(&operation->lock);operation->u32_result=SUCCEEDED(hr)?loaded:0;LeaveCriticalSection(&operation->lock);
    complete_async(operation,hr,FALSE);trace_result("DataReader.LoadComplete",hr);
    if(copy)dr_release(copy);if(result)IUnknown_Release(result);if(info)IUnknown_Release(info);if(async)IUnknown_Release(async);if(input)IUnknown_Release(input);if(buffer)dr_release(buffer);
    IAgileReference_Release(job->input);dr_release(d);release(operation);HeapFree(GetProcessHeap(),0,job);
}
static DWORD WINAPI dr_load_worker(void *parameter){
    HMODULE module=NULL;GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS,(const WCHAR *)(uintptr_t)dr_load_worker,&module);
    HRESULT initialized=CoInitializeEx(NULL,COINIT_MULTITHREADED);
    dr_load_transfer(parameter);
    if(SUCCEEDED(initialized))CoUninitialize();if(module)FreeLibraryAndExitThread(module,0);return 0;
}
static HRESULT WINAPI dr_load(DR *d,UINT32 count,void **out){
    if(!out)return E_POINTER;*out=NULL;if(count>DR_LIMIT)return E_INVALIDARG;
    EnterCriticalSection(&d->lock);HRESULT hr=d->closed?RO_E_CLOSED:d->loading?HRESULT_FROM_WIN32(ERROR_INVALID_OPERATION):!d->input?E_ILLEGAL_METHOD_CALL:S_OK;
    if(FAILED(hr)){LeaveCriticalSection(&d->lock);return hr;}
    hr=make_async(NULL,&iid_async_u32,out);if(FAILED(hr)){LeaveCriticalSection(&d->lock);return hr;}
    Obj *operation=*out;operation->kind=ASYNC_U32;operation->async_status=0;
    DRLoad *job=HeapAlloc(GetProcessHeap(),HEAP_ZERO_MEMORY,sizeof(*job));
    if(!job){operation->async_status=3;operation->async_error=E_OUTOFMEMORY;LeaveCriticalSection(&d->lock);return S_OK;}
    job->reader=d;job->operation=operation;job->count=count;job->options=d->options;job->input=d->input;IAgileReference_AddRef(job->input);dr_add(d);addref(operation);d->loading=TRUE;
    if(d->resident_input){
        LeaveCriticalSection(&d->lock);
        trace_result("DataReader.ResidentLoad",S_OK);
        dr_load_transfer(job); /* Actual ReadAsync/GetResults/bytes commit before return. */
        return S_OK;
    }
    HANDLE worker=CreateThread(NULL,0,dr_load_worker,job,0,NULL);
    if(worker)CloseHandle(worker);else{HRESULT error=HRESULT_FROM_WIN32(GetLastError());d->loading=FALSE;IAgileReference_Release(job->input);dr_release(d);release(operation);HeapFree(GetProcessHeap(),0,job);operation->async_status=3;operation->async_error=error;}
    LeaveCriticalSection(&d->lock);return S_OK;
}
