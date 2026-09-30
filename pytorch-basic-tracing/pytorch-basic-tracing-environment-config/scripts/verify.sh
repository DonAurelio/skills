#!/usr/bin/env bash
# Non-destructive verification of a PyTorch tracing shell on Aurora.
# Run AFTER `source env.sh [lttng]` in the SAME shell:
#
#   source env.sh lttng && bash verify.sh
#
# Prints one line per check and a final `RESULT: PASS|FAIL`. Never modifies state.
# LTTng-tool checks are only enforced when the lttng toolchain is actually loaded
# (i.e. the `lttng` profile), so the same script works for both profiles.

# NOTE: no `set -e` -- we want every check to run and report, not abort on first fail.
fail=0
ok()   { echo "[ok]   $*"; }
bad()  { echo "[FAIL] $*"; fail=1; }
info() { echo "[info] $*"; }

echo "=== PyTorch tracing environment verification ==="
echo "host: $(hostname)"

# 1. module system available
if command -v module >/dev/null 2>&1; then ok "module command available"
else bad "module command NOT available (env.sh could not init Lmod)"; fi

# 2. torch imports cleanly -- the load-order canary
if command -v python >/dev/null 2>&1; then
  if TVER=$(python -c 'import torch; print(torch.__version__)' 2>/tmp/verify_torch.err); then
    ok "import torch OK (torch $TVER)"
  else
    bad "import torch FAILED -- likely load-order (frameworks must load LAST). See:"
    sed 's/^/       /' /tmp/verify_torch.err | tail -3
  fi
else
  bad "python not on PATH (frameworks not loaded?)"
fi

# 3. build vars exported (needed by the later build step, not by this skill)
if [ -n "${TORCH_INCLUDE:-}" ] && [ -d "${TORCH_INCLUDE:-/nonexistent}" ]; then
  ok "TORCH_INCLUDE set ($TORCH_INCLUDE)"
else
  bad "TORCH_INCLUDE unset/missing (torch import must succeed first)"
fi
if [ -n "${TORCH_LIB:-}" ] && [ -d "${TORCH_LIB:-/nonexistent}" ]; then
  ok "TORCH_LIB set ($TORCH_LIB)"
else
  bad "TORCH_LIB unset/missing"
fi

# 4. LTTng toolchain -- enforced only when the lttng profile is loaded.
#    Detect the profile from LOADED MODULES, not from PATH: the head node has a
#    stray system /usr/bin/lttng-gen-tp that would falsely trip a PATH check.
if echo "${LOADEDMODULES:-}" | grep -qE 'lttng-tools|babeltrace2'; then
  PROFILE="lttng"
  for t in lttng lttng-gen-tp babeltrace2; do
    p=$(command -v "$t" 2>/dev/null)
    # Require the tool to resolve from a module tree, not /usr/bin.
    if [ -n "$p" ] && [ "${p#/usr/bin/}" = "$p" ]; then ok "$t present ($p)"
    elif [ -n "$p" ]; then bad "$t resolves to system $p, not the module (load order?)"
    else bad "$t MISSING (lttng profile incomplete)"; fi
  done
else
  PROFILE="default"
  info "LTTng modules not loaded -> 'default' profile (fine for build/run; re-source with 'lttng' to record traces)"
fi
info "profile: $PROFILE"

# 5. Node type + XPU count -- informational, never a failure.
if command -v python >/dev/null 2>&1; then
  XPU=$(python -c 'import torch; print(torch.xpu.device_count() if hasattr(torch,"xpu") else 0)' 2>/dev/null)
  XPU=${XPU:-unknown}
  if [ "$XPU" = "0" ]; then
    info "XPU count = 0  -> HEAD/login node (build + CPU workloads OK; GPU needs a compute node)"
  elif [ "$XPU" = "unknown" ]; then
    info "XPU count = unknown (torch import failed)"
  else
    info "XPU count = $XPU  -> DEVICE (compute) node"
    # On a device node, warn about the shared-home sessiond lock trap.
    if [ "$PROFILE" = "lttng" ] && [ -e "$HOME/.lttng/lttng-sessiond.lck" ] && [ -z "${LTTNG_HOME:-}" ]; then
      info "NOTE: stale \$HOME/.lttng sessiond lock present and LTTNG_HOME unset --"
      info "      set a node-local LTTNG_HOME (e.g. /tmp/lttng_\$USER_\$\$) before recording."
    fi
  fi
fi

echo "================================================"
if [ "$fail" = "0" ]; then echo "RESULT: PASS"; exit 0
else echo "RESULT: FAIL"; exit 1; fi
