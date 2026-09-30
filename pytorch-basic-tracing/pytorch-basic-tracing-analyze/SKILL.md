---
name: pytorch-basic-tracing-analyze
description: Analyze a recorded PyTorch RecordFunction/LTTng trace into the granularity metrics this project reports — per-vtid entry/exit balance and max nesting depth, scope mix (FUNCTION vs BACKWARD_FUNCTION), which thread carries the backward/autograd graph, top ops by frequency, and @device args — plus a global-vs-thread-local coverage comparison. Use after a trace is recorded and verified (RESULT: PASS from the record skill), to turn a babeltrace2 dump or CTF trace dir into the numbers and findings that go into a stage README.
---

# PyTorch basic tracing — analyze

Turn a **verified** trace into the quantified findings this project documents:
thread granularity, scope mix, nesting depth, backward-thread location, op
identity, and device visibility. This is the phase **after** recording — it reads
a trace and reports numbers; it does not record or interpret beyond the metrics.
Assumes the trace is sound (`RESULT: PASS` from `pytorch-basic-tracing-record`).

## What it extracts (the numbers a stage README cites)

- **Entry/exit balance** overall and per vtid — the correctness invariant.
- **Thread granularity** — distinct vtids, each one's entry count + max nesting
  depth.
- **Backward-thread detection** — which vtid(s) carry `*Backward0` /
  `autograd::engine` / `AccumulateGrad`. On CPU this is the calling thread
  (inline); on XPU it's a dedicated autograd-engine vtid — the headline device
  finding.
- **Scope mix** — FUNCTION vs BACKWARD_FUNCTION counts (depends on
  `TRACER_SCOPES` at record time).
- **Op identity** — top ops by frequency.
- **Device granularity** — counts of `@cpu` / `@xpu:0` seen in rendered `args`
  (only present if the trace was recorded with `TRACER_INPUTS=1`).
- **`--compare`** — global vs thread-local: the event count each captured and the
  **percent a thread-local run misses** (the "register globally" argument).

## Procedure

1. **Have a trace.** Either a `babeltrace2` text dump (a `traces/*.txt` file) or a
   raw CTF trace dir. If you pass a dir, the script converts it with `babeltrace2`,
   so `source <env-skill>/scripts/env.sh lttng` first in that case. A `.txt` dump
   needs nothing but python3.

2. **Locate the script** next to this file: `scripts/analyze.py` (stdlib only).

3. **Run it.** Single trace:

   ```bash
   python3 "<skill-dir>/scripts/analyze.py" path/to/trace.txt
   # or a CTF dir (needs env.sh lttng sourced):
   python3 "<skill-dir>/scripts/analyze.py" "$LTTNG_HOME/lttng-traces/rec-<label>-<ts>"
   ```

   Global-vs-thread-local coverage gap (record both variants first — same
   workload, `TRACER_THREAD=global` and `=local`):

   ```bash
   python3 "<skill-dir>/scripts/analyze.py" --compare global.txt local.txt
   ```

   Add `--json` to either for machine-readable output (useful when feeding the
   numbers into a notes/README step).

4. **Read the report** and lift the numbers into the write-up. Sanity-check that
   balance holds on every vtid before trusting any other number — an imbalance
   means the trace was truncated and the rest is suspect (re-record).

## Interpreting the output

- **balanced=False, or a vtid marked `!! UNBALANCED`** — the trace is truncated or
  the `.so` had an ABI desync. Stop; re-record (and rebuild the `.so` if the
  desync recurs). Every downstream number is unreliable.
- **backward runs on vtid(s): …** — if it names a vtid *other* than the main/only
  thread, backward ran on a dedicated autograd engine thread (the XPU behaviour).
  If it says "inline on the only thread", that's the CPU behaviour.
- **`--compare` capture %** — a low percentage (e.g. 8.3%) is the quantified cost
  of a thread-local callback: everything on the worker + autograd threads is lost.
- **devices in args empty** — the trace was recorded without `TRACER_INPUTS=1`;
  re-record with it if you need the device-visibility finding.

## Reporting back to the user

Give the headline numbers and what they mean, e.g.:
"intraop XPU trace: 400 events / 2 vtids, balanced. Backward runs on vtid 70050
(dedicated autograd thread), 132 backward events; main thread has 0. Scopes:
1806 FUNCTION / 156 BACKWARD_FUNCTION. That's the CPU tie breaking on device."

## Scope / boundaries

- Reads and quantifies a trace; it does **not** record one or write the docs.
  Hand the numbers to the notes skill for the stage README.
- It parses the enriched schema (name + scope + depth + args). A name-only trace
  (older schema) still yields counts, vtids, and top ops, but no scope/depth/device
  breakdown.
