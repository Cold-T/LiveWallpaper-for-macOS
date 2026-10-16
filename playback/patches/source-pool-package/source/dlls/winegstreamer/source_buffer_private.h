/* Private source-owned IMFMediaBuffer. Payload is not exposed to a consumer
 * until parser READY and source_buffer_seal() attest a complete initialized
 * range. Cache storage is never reused before the last COM reference. */
#include <malloc.h>
#define SOURCE_POOL_SLOTS 2
#define SOURCE_POOL_BYTES (64u * 1024u * 1024u)
struct source_buffer_pool
{
    LONG refs;
    SRWLOCK lock;
    BOOL closed;
    unsigned int count;
    SIZE_T cached_bytes, active_bytes, peak_bytes;
    ULONGLONG hits, allocations, active;
    struct { BYTE *data; DWORD capacity; } slots[SOURCE_POOL_SLOTS];
};
struct source_buffer
{
    IMFMediaBuffer IMFMediaBuffer_iface;
    LONG refs;
    SRWLOCK lock;
    struct source_buffer_pool *pool;
    BYTE *data;
    DWORD capacity, maximum, length;
    BOOL sealed;
};
static void source_pool_release(struct source_buffer_pool *pool)
{
    if (pool && !InterlockedDecrement(&pool->refs)) free(pool);
}
/* Caller serializes owner creation/close with the existing media source cs. */
static void source_pool_close(struct source_buffer_pool **owner)
{
    struct source_buffer_pool *pool = *owner;
    BYTE *data[SOURCE_POOL_SLOTS];
    unsigned int i, count;
    if (!pool) return;
    *owner = NULL;
    AcquireSRWLockExclusive(&pool->lock);
    pool->closed = TRUE;
    count = pool->count;
    for (i = 0; i < count; ++i) data[i] = pool->slots[i].data;
    pool->count = 0;
    pool->cached_bytes = 0;
    ReleaseSRWLockExclusive(&pool->lock);
    for (i = 0; i < count; ++i) _aligned_free(data[i]);
    source_pool_release(pool);
}
static void source_pool_return(struct source_buffer_pool *pool, BYTE *data, DWORD capacity)
{
    BOOL keep;
    AcquireSRWLockExclusive(&pool->lock);
    --pool->active;
    pool->active_bytes -= capacity;
    keep = !pool->closed && pool->count < SOURCE_POOL_SLOTS && capacity <= SOURCE_POOL_BYTES
            && pool->cached_bytes <= SOURCE_POOL_BYTES - capacity;
    if (keep)
    {
        pool->slots[pool->count].data = data;
        pool->slots[pool->count++].capacity = capacity;
        pool->cached_bytes += capacity;
    }
    ReleaseSRWLockExclusive(&pool->lock);
    if (!keep) _aligned_free(data);
    source_pool_release(pool);
}
static HRESULT source_pool_take(struct source_buffer_pool **owner, DWORD requested,
        struct source_buffer_pool **lease, BYTE **data, DWORD *capacity)
{
    struct source_buffer_pool *pool = *owner;
    unsigned int i, best = SOURCE_POOL_SLOTS;
    DWORD required = requested ? requested : 1;
    *lease = NULL;
    *data = NULL;
    if (!pool)
    {
        if (!(pool = calloc(1, sizeof(*pool)))) return E_OUTOFMEMORY;
        pool->refs = 1;
        *owner = pool;
    }
    AcquireSRWLockExclusive(&pool->lock);
    if (pool->closed) { ReleaseSRWLockExclusive(&pool->lock); return MF_E_SHUTDOWN; }
    InterlockedIncrement(&pool->refs);
    for (i = 0; i < pool->count; ++i)
        if (pool->slots[i].capacity >= required
                && (best == SOURCE_POOL_SLOTS || pool->slots[i].capacity < pool->slots[best].capacity)) best = i;
    if (best != SOURCE_POOL_SLOTS)
    {
        *data = pool->slots[best].data;
        *capacity = pool->slots[best].capacity;
        pool->cached_bytes -= *capacity;
        pool->slots[best] = pool->slots[--pool->count];
        ++pool->hits;
    }
    ReleaseSRWLockExclusive(&pool->lock);
    if (!*data)
    {
        *capacity = required;
        if (!(*data = _aligned_malloc(required, 16))) { source_pool_release(pool); return E_OUTOFMEMORY; }
        AcquireSRWLockExclusive(&pool->lock);
        ++pool->allocations;
        ReleaseSRWLockExclusive(&pool->lock);
    }
    AcquireSRWLockExclusive(&pool->lock);
    ++pool->active;
    pool->active_bytes += *capacity;
    if (pool->active_bytes > pool->peak_bytes) pool->peak_bytes = pool->active_bytes;
    ReleaseSRWLockExclusive(&pool->lock);
    *lease = pool;
    return S_OK;
}
static struct source_buffer *source_buffer_from_iface(IMFMediaBuffer *iface)
{
    return CONTAINING_RECORD(iface, struct source_buffer, IMFMediaBuffer_iface);
}
static HRESULT WINAPI source_buffer_QueryInterface(IMFMediaBuffer *iface, REFIID iid, void **out)
{
    if (!out) return E_POINTER;
    *out = NULL;
    if (!IsEqualIID(iid, &IID_IUnknown) && !IsEqualIID(iid, &IID_IMFMediaBuffer)) return E_NOINTERFACE;
    *out = iface;
    IMFMediaBuffer_AddRef(iface);
    return S_OK;
}
static ULONG WINAPI source_buffer_AddRef(IMFMediaBuffer *iface)
{
    return InterlockedIncrement(&source_buffer_from_iface(iface)->refs);
}
static ULONG WINAPI source_buffer_Release(IMFMediaBuffer *iface)
{
    struct source_buffer *buffer = source_buffer_from_iface(iface);
    ULONG refs = InterlockedDecrement(&buffer->refs);
    if (!refs)
    {
        source_pool_return(buffer->pool, buffer->data, buffer->capacity);
        free(buffer);
    }
    return refs;
}
static HRESULT WINAPI source_buffer_Lock(IMFMediaBuffer *iface, BYTE **data, DWORD *maximum, DWORD *length)
{
    struct source_buffer *buffer = source_buffer_from_iface(iface);
    if (!data) return E_INVALIDARG;
    AcquireSRWLockExclusive(&buffer->lock);
    *data = buffer->data;
    if (maximum) *maximum = buffer->maximum;
    if (length) *length = buffer->length;
    ReleaseSRWLockExclusive(&buffer->lock);
    return S_OK;
}
static HRESULT WINAPI source_buffer_Unlock(IMFMediaBuffer *iface)
{
    (void)iface;
    return S_OK;
}
static HRESULT WINAPI source_buffer_GetCurrentLength(IMFMediaBuffer *iface, DWORD *length)
{
    struct source_buffer *buffer = source_buffer_from_iface(iface);
    if (!length) return E_INVALIDARG;
    AcquireSRWLockExclusive(&buffer->lock);
    *length = buffer->length;
    ReleaseSRWLockExclusive(&buffer->lock);
    return S_OK;
}
static HRESULT WINAPI source_buffer_SetCurrentLength(IMFMediaBuffer *iface, DWORD length)
{
    struct source_buffer *buffer = source_buffer_from_iface(iface);
    HRESULT hr = S_OK;
    AcquireSRWLockExclusive(&buffer->lock);
    if (length > buffer->maximum) hr = E_INVALIDARG;
    else buffer->length = length;
    ReleaseSRWLockExclusive(&buffer->lock);
    return hr;
}
static HRESULT WINAPI source_buffer_GetMaxLength(IMFMediaBuffer *iface, DWORD *maximum)
{
    struct source_buffer *buffer = source_buffer_from_iface(iface);
    if (!maximum) return E_INVALIDARG;
    AcquireSRWLockExclusive(&buffer->lock);
    *maximum = buffer->maximum;
    ReleaseSRWLockExclusive(&buffer->lock);
    return S_OK;
}
static const IMFMediaBufferVtbl source_buffer_vtbl =
{
    source_buffer_QueryInterface, source_buffer_AddRef, source_buffer_Release,
    source_buffer_Lock, source_buffer_Unlock, source_buffer_GetCurrentLength,
    source_buffer_SetCurrentLength, source_buffer_GetMaxLength,
};
static HRESULT source_buffer_create(struct source_buffer_pool **owner, DWORD requested, IMFMediaBuffer **out)
{
    struct source_buffer *buffer;
    HRESULT hr;
    *out = NULL;
    if (!(buffer = calloc(1, sizeof(*buffer)))) return E_OUTOFMEMORY;
    hr = source_pool_take(owner, requested, &buffer->pool, &buffer->data, &buffer->capacity);
    if (FAILED(hr)) { free(buffer); return hr; }
    buffer->IMFMediaBuffer_iface.lpVtbl = &source_buffer_vtbl;
    buffer->refs = 1;
    buffer->maximum = requested;
    *out = &buffer->IMFMediaBuffer_iface;
    return S_OK;
}
/* Private producer operation, only after the atomic parser copy returned READY.
 * Narrow max as well as current length: no uninitialized allocation tail is
 * advertised if actual metadata size is smaller than advisory preflight. */
static HRESULT source_buffer_seal(IMFMediaBuffer *iface, DWORD initialized)
{
    struct source_buffer *buffer = source_buffer_from_iface(iface);
    HRESULT hr = S_OK;
    AcquireSRWLockExclusive(&buffer->lock);
    if (buffer->sealed || initialized > buffer->maximum) hr = E_INVALIDARG;
    else
    {
        buffer->maximum = buffer->length = initialized;
        buffer->sealed = TRUE;
    }
    ReleaseSRWLockExclusive(&buffer->lock);
    return hr;
}
struct source_pool_stats
{
    ULONGLONG hits, allocations, active;
    SIZE_T cached_bytes, active_bytes, peak_bytes;
    unsigned int cached;
};
static void source_pool_snapshot(struct source_buffer_pool *pool, struct source_pool_stats *stats)
{
    AcquireSRWLockExclusive(&pool->lock);
    stats->hits = pool->hits;
    stats->allocations = pool->allocations;
    stats->active = pool->active;
    stats->cached_bytes = pool->cached_bytes;
    stats->active_bytes = pool->active_bytes;
    stats->peak_bytes = pool->peak_bytes;
    stats->cached = pool->count;
    ReleaseSRWLockExclusive(&pool->lock);
}
