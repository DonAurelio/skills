#!/usr/bin/env bash
# Non-destructive sanity check of a recorded RecordFunction trace.
#
#   source <env-skill>/scripts/env.sh lttng
#   bash verify.sh [trace-dir]     # defaults to the last session run.sh recorded
#
# Confirms the trace exists, carries op_entry/op_exit events, that entry and exit
# counts BALANCE per vtid (the depth-stack invariant), and reports the vtid set
# and scope mix. Prints one line per check and a final `RESULT: PASS|FAIL`.
# Reads only -- records nothing.

fail=0
ok()   { echo "[ok]   $*"; }
bad()  { echo "[FAIL] $*"; fail=1; }
info() { echo "[info] $*"; }

TRACE_DIR="${1:-}"
if [ -z "$TRACE_DIR" ]; then
  if [ -f "/tmp/last_trace_${USER}.txt" ]; then TRACE_DIR="$(cat "/tmp/last_trace_${USER}.txt")"
  else TRACE_DIR="$(ls -dt "${LTTNG_HOME:-$HOME}"/lttng-traces/rec-* 2>/dev/null | head -1)"; fi
fi

echo "=== PyTorch trace verification ==="
echo "host:  $(hostname)"
echo "trace: ${TRACE_DIR:-<none>}"

# 1. trace dir exists.
if [ -d "$TRACE_DIR" ]; then ok "trace dir present"
else bad "no trace dir -- run.sh did not record, or pass one explicitly"; echo "RESULT: FAIL"; exit 1; fi

# 2. babeltrace2 available (lttng profile).
command -v babeltrace2 >/dev/null 2>&1 || { bad "babeltrace2 missing -- source env.sh lttng"; echo "RESULT: FAIL"; exit 1; }

DUMP="$(babeltrace2 "$TRACE_DIR" 2>/dev/null)"
NL="$(printf '%s\n' "$DUMP" | grep -c 'lttng_ust_pytorch:')"
ENTRY="$(printf '%s\n' "$DUMP" | grep -c 'op_entry')"
EXIT="$(printf '%s\n' "$DUMP" | grep -c 'op_exit')"

# 3. non-empty.
if [ "$NL" -gt 0 ]; then ok "trace has $NL RecordFunction events ($ENTRY entry / $EXIT exit)"
else bad "trace has NO lttng_ust_pytorch events -- tracer not preloaded, or wrong session"; fi

# 4. entry/exit balance PER vtid -- the depth-stack invariant. Each thread must
#    close every op it opened; a mismatch means truncation or an ABI desync.
if [ "$NL" -gt 0 ]; then
  VTIDS="$(printf '%s\n' "$DUMP" | grep -oE 'vtid = [0-9]+' | sort -u | grep -oE '[0-9]+')"
  NVT="$(printf '%s\n' "$VTIDS" | grep -c .)"
  info "distinct vtids: $NVT [$(echo $VTIDS | tr '\n' ' ')]"
  imbalance=0
  for v in $VTIDS; do
    e="$(printf '%s\n' "$DUMP" | grep "vtid = $v" | grep -c op_entry)"
    x="$(printf '%s\n' "$DUMP" | grep "vtid = $v" | grep -c op_exit)"
    if [ "$e" = "$x" ]; then info "  vtid $v: $e entry == $x exit"
    else bad "  vtid $v: $e entry != $x exit (unbalanced -- truncated or ABI desync)"; imbalance=1; fi
  done
  [ "$imbalance" = "0" ] && ok "entry/exit balanced on every vtid"

  # 5. scope mix -- informational (function vs backward, depends on TRACER_SCOPES).
  SCOPES="$(printf '%s\n' "$DUMP" | grep -oE 'scope = "[A-Z_]+"' | sort | uniq -c | tr '\n' ' ')"
  info "scopes: ${SCOPES:-<none>}"
fi

echo "================================================"
if [ "$fail" = "0" ]; then echo "RESULT: PASS"; exit 0
else echo "RESULT: FAIL"; exit 1; fi
