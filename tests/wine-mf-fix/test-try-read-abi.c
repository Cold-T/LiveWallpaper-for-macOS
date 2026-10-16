#define __WINESRC__
#include <stddef.h>
#include "unixlib.h"
C_ASSERT(unix_wg_parser_stream_try_read == 37);
C_ASSERT(unix_wg_funcs_count == 38);
C_ASSERT(offsetof(struct wg_parser_stream_try_read_params, epoch) == 16);
#ifdef _WIN64
C_ASSERT(sizeof(struct wg_parser_stream_try_read_params) == 48);
C_ASSERT(offsetof(struct wg_parser_stream_try_read_params, buffer) == 24);
C_ASSERT(offsetof(struct wg_parser_stream_try_read_params, data) == 32);
C_ASSERT(offsetof(struct wg_parser_stream_try_read_params, capacity) == 40);
C_ASSERT(offsetof(struct wg_parser_stream_try_read_params, status) == 44);
#else
C_ASSERT(sizeof(struct wg_parser_stream_try_read_params) == 40);
C_ASSERT(offsetof(struct wg_parser_stream_try_read_params, buffer) == 24);
C_ASSERT(offsetof(struct wg_parser_stream_try_read_params, data) == 28);
C_ASSERT(offsetof(struct wg_parser_stream_try_read_params, capacity) == 32);
C_ASSERT(offsetof(struct wg_parser_stream_try_read_params, status) == 36);
#endif
int fixture_only_not_executed;
