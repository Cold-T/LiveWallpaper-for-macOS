#include <assert.h>
#include <pthread.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <stdio.h>
#include <gst/gst.h>
#define __WINESRC__
#include "unixlib.h"
struct wg_parser { pthread_mutex_t mutex; bool error; };
struct wg_parser_stream { struct wg_parser *parser; UINT64 read_epoch; bool enabled,flushing,eos; GstBuffer *buffer; GstMapInfo map_info; unsigned int number; pthread_cond_t event_empty_cond; };
static struct wg_parser *get_parser(wg_parser_t p) { return (void *)(uintptr_t)p; }
static struct wg_parser_stream *get_stream(wg_parser_stream_t p) { return (void *)(uintptr_t)p; }

#include "atomic-body.h"

static void fill(struct wg_parser_stream *s,const char *data,size_t n,uint64_t pts) {
    assert(!s->buffer);
    s->buffer=gst_buffer_new_allocate(NULL,n,NULL); assert(s->buffer);
    gst_buffer_fill(s->buffer,0,data,n);
    GST_BUFFER_PTS(s->buffer)=pts;GST_BUFFER_DURATION(s->buffer)=1000;
    assert(gst_buffer_map(s->buffer,&s->map_info,GST_MAP_READ));
}
static void flush(struct wg_parser_stream *s) {
    pthread_mutex_lock(&s->parser->mutex);
    ++s->read_epoch;
    if(s->buffer) {gst_buffer_unmap(s->buffer,&s->map_info);gst_buffer_unref(s->buffer);s->buffer=NULL;}
    pthread_mutex_unlock(&s->parser->mutex);
}
int main(void) {
    struct wg_parser p={0}; struct wg_parser_stream s={0}; struct wg_parser_buffer meta;
    struct wg_parser_stream_try_read_params a={0};char data[16];unsigned checks=0;
    gst_init(NULL,NULL); pthread_mutex_init(&p.mutex,NULL);pthread_cond_init(&s.event_empty_cond,NULL);
    s.parser=&p;s.enabled=true;s.read_epoch=1;s.number=7;
    a.parser=(uintptr_t)&p;a.stream=(uintptr_t)&s;a.buffer=&meta;
    assert(!wg_parser_stream_try_read(&a));assert(a.status==WG_PARSER_READ_WOULD_BLOCK);checks++;
    s.eos=true;a.epoch=0;wg_parser_stream_try_read(&a);assert(a.status==WG_PARSER_READ_EOS);checks++;
    s.enabled=false;wg_parser_stream_try_read(&a);assert(a.status==WG_PARSER_READ_CANCELLED);checks++;
    s.enabled=true;s.eos=false;a.epoch=0;fill(&s,"old",3,12300);
    wg_parser_stream_try_read(&a);assert(a.status==WG_PARSER_READ_NEED_BUFFER &&meta.size==3&&meta.pts==123&&s.buffer);checks++;
    a.data=data;a.capacity=2;wg_parser_stream_try_read(&a);assert(a.status==WG_PARSER_READ_NEED_BUFFER&&s.buffer);checks++;
    /* A real asynchronous segment change between advisory preflight and copy. */
    flush(&s);fill(&s,"new-frame",9,98700);memset(data,0x55,sizeof(data));a.capacity=sizeof(data);
    wg_parser_stream_try_read(&a);assert(a.status==WG_PARSER_READ_CANCELLED&&s.buffer&&data[0]==0x55);checks++;
    a.epoch=0;a.data=NULL;a.capacity=0;wg_parser_stream_try_read(&a);
    assert(a.status==WG_PARSER_READ_NEED_BUFFER&&meta.size==9&&meta.pts==987);checks++;
    a.data=data;a.capacity=sizeof(data);wg_parser_stream_try_read(&a);
    assert(a.status==WG_PARSER_READ_READY&&!s.buffer&&!memcmp(data,"new-frame",9)&&meta.size==9&&meta.duration==10);checks++;
    wg_parser_stream_try_read(&a);assert(a.status==WG_PARSER_READ_WOULD_BLOCK);checks++;
    p.error=true;a.epoch=0;wg_parser_stream_try_read(&a);assert(a.status==WG_PARSER_READ_ERROR);checks++;
    p.error=false;
    s.flushing=true;a.epoch=0;wg_parser_stream_try_read(&a);assert(a.status==WG_PARSER_READ_CANCELLED);checks++;
    pthread_cond_destroy(&s.event_empty_cond);pthread_mutex_destroy(&p.mutex);
    printf("{\"checks\":%u,\"result\":\"passed\",\"scope\":\"actual try_read body; synthetic native GstBuffer; no Wine or media\"}\n",checks);
    return 0;
}
