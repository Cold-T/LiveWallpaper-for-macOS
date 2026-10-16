// Opt-in, metadata-only diagnostic. Never change caps or original return values.
// Link the exact application's GStreamer libraries so dyld knows the replacee
// before a later Wine dlopen/dlsym. Calls from this interposing image to the
// original symbol are excluded from interposition by dyld (no dlsym recursion).
#include <execinfo.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef struct _GstCaps GstCaps;
typedef struct _GstVideoInfo GstVideoInfo;
extern int gst_video_info_from_caps(GstVideoInfo *, const GstCaps *);
extern int gst_caps_is_fixed(const GstCaps *);
extern char *gst_caps_to_string(const GstCaps *);
extern void g_free(void *);

static atomic_uint emitted;
static _Thread_local int in_trace;

static int lw_gst_video_info_from_caps(GstVideoInfo *info, const GstCaps *caps) {
  const char *enabled = getenv("LW_GST_CAPS_TRACE");
  if (!in_trace && enabled && !strcmp(enabled, "1") && caps && !gst_caps_is_fixed(caps)) {
    unsigned limit = 12;
    const char *setting = getenv("LW_GST_CAPS_TRACE_LIMIT");
    if (setting) {
      char *end = NULL;
      unsigned long value = strtoul(setting, &end, 10);
      if (end != setting && !*end && value >= 1 && value <= 64) limit = (unsigned)value;
    }
    unsigned index = atomic_fetch_add_explicit(&emitted, 1, memory_order_relaxed);
    if (index < limit) {
      in_trace = 1;
      char *description = gst_caps_to_string(caps);
      void *stack[32];
      int count = backtrace(stack, 32);
      flockfile(stderr);
      fprintf(stderr, "[LW GstCaps] pid=%d nonfixed=%u limit=%u caps=%.4096s\n",
              getpid(), index + 1, limit, description ? description : "(unavailable)");
      backtrace_symbols_fd(stack, count, STDERR_FILENO);
      funlockfile(stderr);
      g_free(description);
      in_trace = 0;
    }
  }
  return gst_video_info_from_caps(info, caps);
}

__attribute__((used, section("__DATA,__interpose")))
static const struct { const void *replacement; const void *original; } interpose_caps = {
  (const void *)(uintptr_t)&lw_gst_video_info_from_caps,
  (const void *)(uintptr_t)&gst_video_info_from_caps
};
