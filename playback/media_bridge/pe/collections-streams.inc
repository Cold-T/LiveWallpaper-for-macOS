static const GUID iid_stream_reference={0x33ee3134,0x1dd6,0x4e3a,{0x80,0x67,0xd1,0xc1,0x62,0xe8,0x64,0x2b}};
static const GUID iid_stream_content={0xcc254827,0x4b3d,0x438f,{0x92,0x32,0x10,0xc7,0x6b,0xc7,0xe0,0x38}};
static const GUID iid_ras={0x905a0fe1,0xbc53,0x11df,{0x8c,0x49,0,0x1e,0x4f,0xc6,0x86,0xda}};
static const GUID iid_input={0x905a0fe2,0xbc53,0x11df,{0x8c,0x49,0,0x1e,0x4f,0xc6,0x86,0xda}};
static const GUID iid_content={0x97d098a5,0x3b99,0x4de9,{0x88,0xa5,0xe1,0x1d,0x2f,0x50,0xc7,0x95}};
static const GUID iid_closable={0x30d5a829,0x7fa4,0x4026,{0x83,0xbb,0xd7,0x5b,0xae,0x4e,0xa9,0x9e}};
static const GUID iid_buffer_bytes={0x905a0fef,0xbc53,0x11df,{0x8c,0x49,0,0x1e,0x4f,0xc6,0x86,0xda}};
static ULONG required_iids(Obj *o,IID *values) {
    if(o->kind==FACTORY){values[0]=iid_statics;return 1;}
    if(o->kind==VECTOR){values[0]=iid_session_iterable;return 1;}
    if(o->kind==STRING_VECTOR){values[0]=iid_string_iterable;return 1;}
    if(o->kind==ASYNC||o->kind==ASYNC_BOOL||o->kind==ASYNC_PROGRESS||o->kind==ASYNC_U32){values[0]=iid_async_info;return 1;}
    if(o->kind==STREAM){values[0]=iid_ras;values[1]=iid_input;values[2]=iid_content;values[3]=iid_closable;return 4;}
    return 0;
}
static HRESULT special_qi(Obj *o,REFIID iid,void **out) {
    if((o->kind==VECTOR&&IsEqualIID(iid,&iid_session_iterable))||(o->kind==STRING_VECTOR&&IsEqualIID(iid,&iid_string_iterable))) {
        o->iterable.vt=vt_iterable;*out=&o->iterable;return S_OK;
    }
    if(o->kind==STREAM) {
        if(IsEqualIID(iid,&iid_ras)){o->ras.vt=vt_ras;*out=&o->ras;return S_OK;}
        if(IsEqualIID(iid,&iid_input)){o->input.vt=vt_input;*out=&o->input;return S_OK;}
        if(IsEqualIID(iid,&iid_content)){o->content.vt=vt_content;*out=&o->content;return S_OK;}
        if(IsEqualIID(iid,&iid_closable)){o->closable.vt=vt_closable;*out=&o->closable;return S_OK;}
    }
    return S_FALSE;
}
static HRESULT WINAPI iterable_first(Info *facet,void **out) {
    if(!out)return E_POINTER;*out=NULL;Obj *o=create(ITERATOR,&facet->owner->snapshot);if(!o)return E_OUTOFMEMORY;
    o->collection_kind=facet->owner->kind;o->iid=o->collection_kind==STRING_VECTOR?iid_string_iterator:iid_session_iterator;
    *out=o;return S_OK;
}
static HRESULT WINAPI string_at(Obj *o,UINT32 index,HSTRING *out){(void)o;(void)index;if(out)*out=NULL;return out?E_BOUNDS:E_POINTER;}
static HRESULT WINAPI string_size(Obj *o,UINT32 *out){(void)o;if(!out)return E_POINTER;*out=0;return S_OK;}
static HRESULT WINAPI string_index(Obj *o,HSTRING value,UINT32 *index,BOOLEAN *found){(void)o;(void)value;if(!index||!found)return E_POINTER;*index=0;*found=FALSE;return S_OK;}
static HRESULT WINAPI string_many(Obj *o,UINT32 start,UINT32 capacity,HSTRING *out,UINT32 *actual){(void)o;(void)capacity;(void)out;if(!actual)return E_POINTER;*actual=0;return start?E_BOUNDS:S_OK;}
static BOOL iterator_available(Obj *o){return o->collection_kind!=STRING_VECTOR&&!o->iterator_index&&(o->snapshot.flags&1);}
static HRESULT WINAPI iterator_current(Obj *o,void **out){if(!out)return E_POINTER;*out=NULL;return iterator_available(o)?return_object(SESSION,&o->snapshot,out):E_BOUNDS;}
static HRESULT WINAPI iterator_has(Obj *o,BOOLEAN *out){if(!out)return E_POINTER;*out=iterator_available(o);return S_OK;}
static HRESULT WINAPI iterator_next(Obj *o,BOOLEAN *out){if(!out)return E_POINTER;o->iterator_index=1;*out=FALSE;return S_OK;}
static HRESULT WINAPI iterator_many(Obj *o,UINT32 capacity,void **out,UINT32 *actual){
    if(!actual)return E_POINTER;*actual=0;
    if(capacity&&iterator_available(o)){HRESULT h=iterator_current(o,out);if(FAILED(h))return h;*actual=1;o->iterator_index=1;}return S_OK;
}
static HRESULT load_artwork(const Snapshot *s,Blob **out) {
    *out=NULL;WCHAR path[32768];DWORD length=GetEnvironmentVariableW(L"LWMEDIA_SNAPSHOT_PATH",path,32760);
    if(!length||length>=32700)return S_OK;
    WCHAR fallback[32768];wcscpy(fallback,path);wcscat(fallback,L".art");
    swprintf(path+length,32768-length,L".art.%u",s->generation);
    HANDLE file=CreateFileW(path,GENERIC_READ,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,NULL,OPEN_EXISTING,0,NULL);
    if(file==INVALID_HANDLE_VALUE&&GetLastError()==ERROR_FILE_NOT_FOUND)file=CreateFileW(fallback,GENERIC_READ,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,NULL,OPEN_EXISTING,0,NULL);
    if(file==INVALID_HANDLE_VALUE)return GetLastError()==ERROR_FILE_NOT_FOUND?S_OK:HRESULT_FROM_WIN32(GetLastError());
    struct {char magic[8];UINT32 version,generation,mime,length;} header;DWORD read=0;
    BOOL valid=ReadFile(file,&header,sizeof(header),&read,NULL)&&read==sizeof(header);
    if(!valid||memcmp(header.magic,"LWMART01",8)||header.version!=1||header.length>16*1024*1024){CloseHandle(file);return E_INVALIDARG;}
    if(header.generation!=s->generation||!header.length||!(header.mime==1||header.mime==2)){CloseHandle(file);return S_OK;}
    Blob *blob=HeapAlloc(GetProcessHeap(),HEAP_ZERO_MEMORY,sizeof(*blob)+header.length);if(!blob){CloseHandle(file);return E_OUTOFMEMORY;}
    valid=ReadFile(file,blob->data,header.length,&read,NULL)&&read==header.length;CloseHandle(file);
    if(!valid){HeapFree(GetProcessHeap(),0,blob);return E_FAIL;}
    blob->refs=1;blob->length=header.length;wcscpy(blob->mime,header.mime==1?L"image/jpeg":L"image/png");
    *out=blob;return S_OK;
}
static HRESULT WINAPI thumbnail(Obj *o,void **out) {
    if(!out)return E_POINTER;*out=NULL;Blob *blob=o->blob;HRESULT hr=S_OK;
    if(blob)InterlockedIncrement(&blob->refs);else hr=load_artwork(&o->snapshot,&blob);
    if(FAILED(hr)||!blob)return hr;
    Obj *r=create(STREAM_REFERENCE,NULL);if(!r){if(!InterlockedDecrement(&blob->refs))HeapFree(GetProcessHeap(),0,blob);return E_OUTOFMEMORY;}
    r->iid=iid_stream_reference;r->blob=blob;*out=r;return S_OK;
}
static HRESULT new_stream(Blob *blob,UINT64 position,void **out) {
    if(!out)return E_POINTER;*out=NULL;Obj *o=create(STREAM,NULL);if(!o)return E_OUTOFMEMORY;
    o->iid=iid_stream_content;o->blob=blob;InterlockedIncrement(&blob->refs);o->position=position;*out=o;return S_OK;
}
static HRESULT WINAPI open_read(Obj *o,void **out){void *stream=NULL;HRESULT hr=new_stream(o->blob,0,&stream);return FAILED(hr)?hr:make_async(stream,&iid_async_stream,out);}
static HRESULT WINAPI stream_size(Info *i,UINT64 *out){if(!out)return E_POINTER;if(i->owner->closed)return RO_E_CLOSED;*out=i->owner->blob->length;return S_OK;}
static HRESULT WINAPI stream_put_size(Info *i,UINT64 size){(void)i;(void)size;return E_ACCESSDENIED;}
static HRESULT WINAPI stream_input_at(Info *i,UINT64 position,void **out){
    if(!out)return E_POINTER;*out=NULL;if(i->owner->closed)return RO_E_CLOSED;
    void *stream=NULL;HRESULT hr=new_stream(i->owner->blob,position,&stream);if(FAILED(hr))return hr;
    hr=qi(stream,&iid_input,out);release(stream);return hr;
}
static HRESULT WINAPI stream_output_at(Info *i,UINT64 position,void **out){(void)i;(void)position;if(out)*out=NULL;return E_ACCESSDENIED;}
static HRESULT WINAPI stream_position(Info *i,UINT64 *out){if(!out)return E_POINTER;if(i->owner->closed)return RO_E_CLOSED;*out=i->owner->position;return S_OK;}
static HRESULT WINAPI stream_seek(Info *i,UINT64 position){if(i->owner->closed)return RO_E_CLOSED;i->owner->position=position;return S_OK;}
static HRESULT WINAPI stream_clone(Info *i,void **out){
    if(!out)return E_POINTER;*out=NULL;if(i->owner->closed)return RO_E_CLOSED;
    void *stream=NULL;HRESULT hr=new_stream(i->owner->blob,0,&stream);if(FAILED(hr))return hr;
    hr=qi(stream,&iid_ras,out);release(stream);return hr;
}
static HRESULT WINAPI stream_can_read(Info *i,BOOLEAN *out){if(!out)return E_POINTER;if(i->owner->closed)return RO_E_CLOSED;*out=TRUE;return S_OK;}
static HRESULT WINAPI stream_can_write(Info *i,BOOLEAN *out){if(!out)return E_POINTER;if(i->owner->closed)return RO_E_CLOSED;*out=FALSE;return S_OK;}
static HRESULT WINAPI stream_content_type(Info *i,HSTRING *out){if(i->owner->closed)return RO_E_CLOSED;return string_value(i->owner->blob->mime,out);}
static HRESULT WINAPI stream_close(Info *i){i->owner->closed=TRUE;return S_OK;}
static HRESULT WINAPI stream_read(Info *i,void *buffer,UINT32 count,INT32 options,void **out) {
    if(!buffer||!out)return E_POINTER;*out=NULL;Obj *o=i->owner;if(o->closed)return RO_E_CLOSED;
    if(options<0||options>3)return E_INVALIDARG;
    typedef HRESULT (WINAPI *Capacity)(void *,UINT32 *);
    typedef HRESULT (WINAPI *Length)(void *,UINT32);
    typedef HRESULT (WINAPI *Bytes)(void *,BYTE **);
    UINT32 capacity=0;HRESULT hr=((Capacity)(*(void ***)buffer)[6])(buffer,&capacity);if(FAILED(hr))return hr;
    if(count>capacity)return E_INVALIDARG;
    IUnknown *access=NULL;hr=IUnknown_QueryInterface((IUnknown *)buffer,&iid_buffer_bytes,(void **)&access);if(FAILED(hr))return hr;
    BYTE *bytes=NULL;hr=((Bytes)(*(void ***)access)[3])(access,&bytes);
    if(SUCCEEDED(hr)&&count&&!bytes)hr=E_POINTER;
    EnterCriticalSection(&o->lock);
    UINT64 remaining=o->position<o->blob->length?o->blob->length-o->position:0;
    UINT32 amount=(UINT32)(remaining<count?remaining:count);
    if(SUCCEEDED(hr)){if(amount)memcpy(bytes,o->blob->data+o->position,amount);o->position+=amount;}
    LeaveCriticalSection(&o->lock);IUnknown_Release(access);if(FAILED(hr))return hr;
    hr=((Length)(*(void ***)buffer)[8])(buffer,amount);if(FAILED(hr))return hr;
    IUnknown_AddRef((IUnknown *)buffer);hr=make_async(buffer,&iid_async_buffer_progress,out);
    if(SUCCEEDED(hr)){Obj *operation=*out;operation->kind=ASYNC_PROGRESS;operation->vt=vt_async_progress;}
    return hr;
}
static HRESULT WINAPI put_progress(Obj *o,void *handler){EnterCriticalSection(&o->lock);if(o->progress)IUnknown_Release((IUnknown *)o->progress);o->progress=handler;if(handler)IUnknown_AddRef((IUnknown *)handler);LeaveCriticalSection(&o->lock);return S_OK;}
static HRESULT WINAPI get_progress(Obj *o,void **out){if(!out)return E_POINTER;EnterCriticalSection(&o->lock);*out=o->progress;if(*out)IUnknown_AddRef((IUnknown *)*out);LeaveCriticalSection(&o->lock);return S_OK;}
