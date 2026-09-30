---
name: pytorch-basic-tracing-record
description: Record and VERIFY an LTTng trace of a PyTorch workload under the RecordFunction tracer on Aurora — LD_PRELOAD the built libtorch_tracer.so onto an unmodified python, capture op_entry/op_exit into a named LTTng session (with the aspect toggles set at run time), convert to text with babeltrace2, then confirm the trace has events and entry/exit balance per vtid. Use after the tracer .so is built (RESULT: PASS from the tracer-build skill), on a head node (CPU) or a qsub compute node (XPU), when recording, re-recording, or diagnosing a trace.
---

# PyTorch basic tracing — record & view

Record a **verified** LTTng trace of a workload running under the RecordFunction
tracer, then read it back. This skill is **record + verify only** — it assumes the
`.so` already exists (run `pytorch-basic-tracing-tracer-build` first and get
`RESULT: PASS`) and it produces a trace, not an analysis. Analysis/interpretation
is the next phase.

## What happens in a recording

`run.sh` starts an LTTng userspace session, then launches an **unmodified**
python workload with the tracer `LD_PRELOAD`ed. Every dispatched ATen op fires
`op_entry` / `op_exit`, captured with `vpid`/`vtid` context. The tracer is
**build-once, configure-at-run-time**: you never rebuild to change behaviour — you
set env vars before `run.sh`:

- Tracer toggles: `TRACER_SCOPES` (function|function+backward), `TRACER_THREAD`
  (global|local), `TRACER_TOPLEVEL` (0|1), `TRACER_INPUTS` (0|1),
  `TRACER_SAMPLING` (0..1).
- Workload knobs (passed through to the bundled examples): `DEVICE` (cpu|xpu),
  `SYNC` (0|1), `N_THREADS`, `DIM`, `STEPS`.

## Why this needs a skill, not a one-liner

- **The shared-home sessiond lock.** `$HOME/.lttng` is shared across nodes; a
  login-node `lttng-sessiond` holds a lock that stops a compute-node sessiond
  starting ("A session daemon is already running"). `run.sh` sets a **node-local
  `LTTNG_HOME`** (`/tmp/lttng_$USER_$$`) so the daemon + raw CTF live on the node;
  it converts to text afterwards. Miss this and every compute-node recording fails.
- **`ssh` lands in `$HOME`, not the repo** — so `run.sh` resolves the tracer `.so`
  and workloads by absolute path, and blocks (`--blocking-timeout=inf` +
  `LTTNG_UST_ALLOW_BLOCKING=1`) so no events are dropped under load.
- **"It recorded" ≠ "the trace is sound."** `verify.sh` checks entry/exit
  **balance per vtid** — the depth-stack invariant. An imbalance means truncation
  or an ABI desync, invisible unless you count.

## Procedure

1. **Confirm prerequisites.** Environment verified (`lttng` profile) and the
   tracer built (`libtorch_tracer.so`, RESULT: PASS from the tracer-build skill).
   For an **XPU** trace you MUST be on a compute node (`qsub -A Performance -q
   debug -l walltime=00:60:00 -l filesystems=home -I -l select=1`); CPU traces run
   anywhere. The module env does not propagate — `source env.sh lttng` in the
   same shell (or same remote command) as the run.

2. **Locate the bundled files** (absolute paths — an ssh'd shell starts in `$HOME`):
   - `scripts/run.sh` — record one named session; passes toggles + knobs through.
   - `scripts/view.sh` — babeltrace2 a trace dir to text.
   - `scripts/verify.sh` — sanity-check a recorded trace.
   - `examples/train_intraop.py` — single-launch-thread workload (intra-op / device).
   - `examples/train_hogwild.py` — N threads share one model (global-vs-local diverges).

   `run.sh` finds the `.so` at the tracer-build skill's default path; override with
   `TRACER_SO=/path/to/libtorch_tracer.so` if it lives elsewhere.

3. **Record, then verify — in the SAME shell** env was sourced in. Example (CPU,
   Hogwild, global vs thread-local — the classic divergence):

   ```bash
   TRACER_SCOPES=function+backward TRACER_THREAD=global \
     bash "<skill-dir>/scripts/run.sh" hogwild_global "<skill-dir>/examples/train_hogwild.py"
   bash "<skill-dir>/scripts/verify.sh"          # verifies the just-recorded trace
   ```

   For an XPU run on a compute node over ssh, put source + run in one remote
   command from absolute paths and set `DEVICE=xpu`:

   ```bash
   ssh <node> 'source <env-skill>/scripts/env.sh lttng && \
     TRACER_SCOPES=function+backward DEVICE=xpu \
     bash <skill-dir>/scripts/run.sh xpu_intraop <skill-dir>/examples/train_intraop.py && \
     bash <skill-dir>/scripts/verify.sh'
   ```

4. **Read the trace** with `view.sh` (no arg → the last session recorded), and
   **read the report** below. Do not treat a trace as sound unless `verify.sh`
   prints `RESULT: PASS`.

## Interpreting verify.sh output

- **trace has N events (E entry / X exit)** — if 0, the tracer was not preloaded
  (wrong `.so` path / not built) or you pointed at the wrong session. Rebuild /
  re-record.
- **entry/exit balanced on every vtid** — the key correctness check. A per-vtid
  imbalance = truncation (channel not blocking / session stopped mid-op) or an ABI
  desync (rebuild the `.so` via the tracer-build skill).
- **distinct vtids / scopes** — informational, and often the *point* of the run:
  `TRACER_THREAD=global` on Hogwild shows all worker vtids; `local` shows one.
  On XPU, backward appears on its own autograd-engine vtid even single-threaded.

## Reporting back to the user

State plainly: what was recorded (label, workload, toggles, device/node), event
count, vtid set, `RESULT: PASS|FAIL`, and where the trace dir is. Example:
"Recorded hogwild_global (function+backward, global, CPU): 1954 events across 5
vtids, entry/exit balanced, RESULT: PASS. Trace at $LTTNG_HOME/lttng-traces/
rec-hogwild_global-*."

## Scope / boundaries

- This skill **records and verifies** a trace; it does not interpret findings or
  build the `.so`. Hand off to analysis after `RESULT: PASS`.
- Change WHAT is captured with the `TRACER_*` env vars, never by rebuilding.
- On a compute node always let `run.sh` set the node-local `LTTNG_HOME` (don't
  point it back at shared `$HOME/.lttng`), or the sessiond lock returns.
