// Opt-in isolated A/B loader. Never edits the stock runtime or a PE binary.
#include <dlfcn.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void *load_with_candidate(const char *path, int mode) {
  const char *enabled = getenv("LW_GST_UNIX_OVERRIDE");
  const char *stock = getenv("LW_GST_STOCK_UNIX_MODULE");
  const char *candidate = getenv("LW_GST_CANDIDATE_UNIX_MODULE");
  char actual_path[PATH_MAX], stock_path[PATH_MAX], candidate_path[PATH_MAX];
  if (enabled && !strcmp(enabled, "1") && path && stock && candidate &&
      stock[0] == '/' && candidate[0] == '/' &&
      realpath(path, actual_path) && realpath(stock, stock_path) &&
      !strcmp(actual_path, stock_path)) {
    if (!realpath(candidate, candidate_path) || !strcmp(candidate_path, stock_path)) {
      fprintf(stderr, "[LW GstOverride] invalid isolated candidate; refusing redirect\n");
      return NULL;
    }
    fprintf(stderr, "[LW GstOverride] loading isolated candidate instead of stock winegstreamer.so\n");
    // A failed candidate load stays a failure; silently using stock would
    // invalidate the A/B evidence. dyld excludes this image's own original call.
    return dlopen(candidate_path, mode);
  }
  return dlopen(path, mode);
}

__attribute__((used, section("__DATA,__interpose")))
static const struct { const void *replacement; const void *original; } redirect = {
  (const void *)(uintptr_t)&load_with_candidate, (const void *)(uintptr_t)&dlopen
};
