#define DR_BASE T(dr_qi),T(dr_add),T(dr_release),T(dr_iids),T(dr_name),T(dr_trust)
#define DR_FACET_BASE T(drf_qi),T(drf_add),T(drf_release),T(drf_iids),T(drf_name),T(drf_trust)
static const void *dr_vt_activation[]={DR_BASE,T(dr_activate)};
static const void *dr_vt_factory[]={DR_FACET_BASE,T(dr_factory_create)};
static const void *dr_vt_statics[]={DR_FACET_BASE,T(dr_from_buffer)};
static const void *dr_vt_buffer[]={DR_BASE,T(dr_capacity),T(dr_length),T(dr_put_length)};
static const void *dr_vt_bytes[]={T(drf_qi),T(drf_add),T(drf_release),T(dr_buffer_bytes)};
static const void *dr_vt_close[]={DR_FACET_BASE,T(dr_close)};
static const void *dr_vt_reader[]={DR_BASE,T(dr_unconsumed),T(dr_encoding),T(dr_put_encoding),T(dr_order),T(dr_put_order),T(dr_options),T(dr_put_options),T(dr_read_byte),T(dr_read_bytes),T(dr_read_buffer),T(dr_read_bool),T(dr_read_guid),T(dr_read_i16),T(dr_read_i32),T(dr_read_i64),T(dr_read_u16),T(dr_read_u32),T(dr_read_u64),T(dr_read_float),T(dr_read_double),T(dr_read_string),T(dr_read_i64),T(dr_read_i64),T(dr_load),T(dr_detach_buffer),T(dr_detach_stream)};
