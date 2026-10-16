struct wg_output_cache;
void wg_output_cache_release(struct wg_output_cache *);
struct wg_read_timing { ULONGLONG wrap, unixread, finish, commit, commits, write_wraps, cache_hits, cache_allocs, cache_fallbacks, cache_bytes; };
HRESULT wg_transform_read_mf_timed(wg_transform_t, IMFSample *, DWORD *, bool *, struct wg_read_timing *, BOOL, struct wg_output_cache **);
static inline ULONGLONG convert_timing_now(void) { LARGE_INTEGER t; QueryPerformanceCounter(&t); return t.QuadPart; }
