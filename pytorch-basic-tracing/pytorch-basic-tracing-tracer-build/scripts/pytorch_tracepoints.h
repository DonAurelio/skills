
#undef LTTNG_UST_TRACEPOINT_PROVIDER
#define LTTNG_UST_TRACEPOINT_PROVIDER lttng_ust_pytorch

#undef LTTNG_UST_TRACEPOINT_INCLUDE
#define LTTNG_UST_TRACEPOINT_INCLUDE "./pytorch_tracepoints.h"

#if !defined(PYTORCH_TRACEPOINTS_H) || defined(LTTNG_UST_TRACEPOINT_HEADER_MULTI_READ)
#define PYTORCH_TRACEPOINTS_H

#include <lttng/tracepoint.h>

/*
 * LTTng-UST tracepoint schema for the PyTorch RecordFunction tracer.
 *
 * Each event carries the op name, the RecordScope, the per-thread nesting
 * depth, and (entry only) a rendered argument string. One trace thus exposes
 * aspects 2 (scope), 4 (depth), and 5 (inputs) at once; aspect 3 (thread) comes
 * from LTTng's vtid context, added at record time.
 *
 * Provider: lttng_ust_pytorch
 * Events:   lttng_ust_pytorch:op_entry  /  lttng_ust_pytorch:op_exit
 * Generate with:  lttng-gen-tp pytorch_tracepoints.tp
 *   -> pytorch_tracepoints.c + pytorch_tracepoints.h
 */

TRACEPOINT_EVENT(
  lttng_ust_pytorch,
  op_entry,
  TP_ARGS(
    const char *, name,
    const char *, scope,
    int, depth,
    const char *, args
  ),
  TP_FIELDS(
    ctf_string(name, name)
    ctf_string(scope, scope)
    ctf_integer(int, depth, depth)
    ctf_string(args, args)
  )
)

TRACEPOINT_EVENT(
  lttng_ust_pytorch,
  op_exit,
  TP_ARGS(
    const char *, name,
    const char *, scope,
    int, depth
  ),
  TP_FIELDS(
    ctf_string(name, name)
    ctf_string(scope, scope)
    ctf_integer(int, depth, depth)
  )
)

#endif /* PYTORCH_TRACEPOINTS_H */

#include <lttng/tracepoint-event.h>
