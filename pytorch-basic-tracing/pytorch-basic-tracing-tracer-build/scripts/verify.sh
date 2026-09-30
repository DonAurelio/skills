#!/usr/bin/env bash
# Non-destructive verification of a freshly built tracer .so.
# Run AFTER `source <env-skill>/scripts/env.sh lttng && ./build.sh` in the SAME shell:
#
#   bash verify.sh [path/to/libtorch_tracer.so]
#
# Defaults to ./libtorch_tracer.so next to this script. Prints one line per check
# and a final `RESULT: PASS|FAIL`. Records NO trace — it only confirms the .so is
# well-formed, its libs resolve, and it LD_PRELOADs onto a live torch process
# without the ABI/symbol breakage that has bitten this project before.

# NOTE: no `set -e` -- we want every check to run and report, not abort on first fail.
fail=0
ok()   { echo "[ok]   $*"; }
bad()  { echo "[FAIL] $*"; fail=1; }
info() { echo "[info] $*"; }

HERE="$(cd "$(dirname "$0")" && pwd)"
SO="${1:-$HERE/libtorch_tracer.so}"

echo "=== PyTorch tracer build verification ==="
echo "host: $(hostname)"
echo "so:   $SO"

# 1. The .so exists and is non-empty.
if [ -s "$SO" ]; then ok "libtorch_tracer.so present ($(stat -c%s "$SO") bytes)"
else bad "libtorch_tracer.so missing/empty -- run build.sh (after sourcing env.sh lttng)"; fi

# 2. env is the lttng profile (build needs lttng-gen-tp; TORCH_* must be set).
if [ -n "${TORCH_LIB:-}" ] && [ -d "${TORCH_LIB:-/nonexistent}" ]; then
  ok "TORCH_LIB set ($TORCH_LIB)"
else
  bad "TORCH_LIB unset/missing -- source the env skill's env.sh with 'lttng' first"
fi

# 3. Dependencies resolve -- no 'not found' in ldd, and c10/torch/lttng-ust bound.
if [ -s "$SO" ]; then
  LDD="$(ldd "$SO" 2>/dev/null)"
  if echo "$LDD" | grep -q 'not found'; then
    bad "unresolved shared libs (check env.sh was sourced before build):"
    echo "$LDD" | grep 'not found' | sed 's/^/       /'
  else
    ok "all shared libs resolve"
  fi
  for lib in libc10 libtorch liblttng-ust; do
    line="$(echo "$LDD" | grep -m1 "$lib")"
    if [ -n "$line" ]; then ok "links $lib ->$(echo "$line" | sed -E 's/.*=> +//; s/ \(.*//')"
    else bad "$lib NOT linked (build.sh -l flags or rpath wrong)"; fi
  done
  # The lttng-ust must be the module's 2.14, not system 2.12 (missing
  # lttng_ust_probe_register). Warn if it resolved under /usr/lib64.
  ustline="$(echo "$LDD" | grep -m1 'liblttng-ust' | sed -E 's/.*=> +//; s/ \(.*//')"
  case "$ustline" in
    /usr/lib64/*) info "NOTE: liblttng-ust resolved to system $ustline -- expected the module's 2.14; recording may fail on lttng_ust_probe_register";;
  esac
fi

# 4. The generated probe header carries the enriched 4-field op_entry schema.
if [ -f "$HERE/pytorch_tracepoints.h" ]; then
  if grep -q 'op_entry' "$HERE/pytorch_tracepoints.h"; then ok "probe header generated (pytorch_tracepoints.h)"
  else bad "pytorch_tracepoints.h present but has no op_entry -- .tp/gen mismatch"; fi
else
  info "pytorch_tracepoints.h not found next to build (lttng-gen-tp output elsewhere?)"
fi

# 5. LIVE PRELOAD SMOKE TEST -- the real ABI check. Preload the .so onto a tiny
#    torch workload; a debug/release ABI mismatch or unresolved symbol crashes
#    the process here (SIGSEGV/undefined symbol) even without a trace session.
#    No sessiond running => tracepoints no-op, but the constructor + callback
#    install still execute, exercising the at::RecordFunction ABI path.
if [ -s "$SO" ] && command -v python >/dev/null 2>&1; then
  SMOKE_ERR=/tmp/tracer_smoke.$$.err
  if LD_PRELOAD="$SO" python -c '
import torch
a = torch.randn(8, 8); b = torch.randn(8, 8)
(a @ b + 1).sum().backward() if False else (a @ b + 1).relu().sum()
print("SMOKE_OK")
' >/tmp/tracer_smoke.$$.out 2>"$SMOKE_ERR"; then
    if grep -q SMOKE_OK /tmp/tracer_smoke.$$.out; then
      ok "LD_PRELOAD smoke test passed (constructor + callback install, ABI OK)"
    else
      bad "smoke test ran but produced no SMOKE_OK marker"; sed 's/^/       /' "$SMOKE_ERR" | tail -3
    fi
  else
    bad "LD_PRELOAD smoke test CRASHED -- likely ABI (need -DNDEBUG + CXX11 ABI=1) or unresolved symbol:"
    sed 's/^/       /' "$SMOKE_ERR" | tail -5
  fi
  rm -f /tmp/tracer_smoke.$$.out "$SMOKE_ERR"
else
  info "skipping smoke test (.so missing or python not on PATH)"
fi

echo "================================================"
if [ "$fail" = "0" ]; then echo "RESULT: PASS"; exit 0
else echo "RESULT: FAIL"; exit 1; fi
