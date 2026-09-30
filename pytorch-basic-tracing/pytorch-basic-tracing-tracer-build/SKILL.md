---
name: pytorch-basic-tracing-tracer-build
description: Build and VERIFY the C++ RecordFunction tracer .so for PyTorch tracing on Aurora — generate the LTTng-UST probe, compile tracer.cpp with the release ABI (-DNDEBUG + CXX11 ABI=1), link c10/torch/lttng-ust, then confirm the .so's libs resolve and it LD_PRELOADs onto a live torch process without ABI/symbol breakage. Use after the environment is verified (RESULT: PASS from the env-config skill) and before recording a trace, when building, rebuilding, or diagnosing a broken libtorch_tracer.so.
---

# PyTorch basic tracing — tracer build

Produce a **known-good, verified** `libtorch_tracer.so` — the preloadable
RecordFunction tracer — then confirm it actually loads onto torch. This skill is
**build + verification only**: it stops before recording a trace (that is the
next step/skill). It assumes the environment is already verified — run the
`pytorch-basic-tracing-environment-config` skill first and get `RESULT: PASS`.

## What the tracer is

One `.so`, injected with `LD_PRELOAD` into an **unmodified** python. A
`__attribute__((constructor))` installs an `at::RecordFunction` callback at load;
every dispatched ATen op then fires `op_entry` / `op_exit` LTTng-UST tracepoints.
A single build covers six granularity aspects, each selected at **run time** by
environment variables (so this skill never needs rebuilding to change behaviour):

- `TRACER_SCOPES=function|function+backward` — which RecordScopes fire (aspect 2)
- `TRACER_THREAD=global|local` — global (every thread) vs thread-local (aspect 3)
- `TRACER_TOPLEVEL=0|1` — emit only depth==0 user-level ops (aspect 4)
- `TRACER_INPUTS=0|1` — render `fn.inputs()` as `dtype[shape]@device` (aspect 5)
- `TRACER_SAMPLING=<0..1>` — fraction of ops sampled, global callbacks only (aspect 6)

## Why this needs a skill, not a one-liner

The build has **two load-bearing traps** that have bitten this project:

- **ABI must match libtorch's RELEASE build.** `at::RecordFunction`'s memory
  layout differs between debug and release, so the `.so` MUST be compiled with
  `-DNDEBUG -D_GLIBCXX_USE_CXX11_ABI=1`. Get this wrong and it compiles cleanly
  but the callback ABI is wrong at runtime: ENTER/EXIT desync, `fn.inputs()`
  returns garbage, or a SIGSEGV. "It built" is **not** "it works".
- **The module's lttng-ust (2.14) must win over system `/usr/lib64` (2.12),**
  which lacks `lttng_ust_probe_register`. `build.sh` derives the module lib dir
  from `lttng-gen-tp` and bakes it into `-L` + rpath. If lttng-ust resolves to
  `/usr/lib64`, recording later dies on a missing symbol.

Verification is the point: the smoke test LD_PRELOADs the `.so` onto a real
torch process, which exercises the RecordFunction ABI path and crashes *here* if
either trap was hit — instead of silently at record time.

## Procedure

1. **Confirm the environment first.** The build needs the `lttng` profile:
   `TORCH_INCLUDE` / `TORCH_LIB` exported and `lttng-gen-tp` on PATH. If unsure,
   run the `pytorch-basic-tracing-environment-config` skill and confirm
   `RESULT: PASS` before continuing. Do **not** hand-load modules in a different
   order.

2. **Locate the bundled scripts.** They live next to this file in `scripts/`:
   - `tracer.cpp` — the tracer (all six aspects, heavily commented).
   - `pytorch_tracepoints.tp` — the LTTng-UST probe schema (enriched: name +
     scope + depth + args).
   - `build.sh` — generates the probe, compiles with the correct ABI, links.
   - `verify.sh` — non-destructive checks + live LD_PRELOAD smoke test.

   Resolve the skill directory (the folder containing this `SKILL.md`) and use
   its absolute path — on a compute node reached over `ssh` the shell starts in
   `$HOME`, so relative paths fail.

3. **Build, then verify — in the SAME shell** the env was sourced in (the module
   env is lost if you start a new shell between source and build):

   ```bash
   bash "<skill-dir>/scripts/build.sh" && bash "<skill-dir>/scripts/verify.sh"
   ```

   `build.sh` writes `libtorch_tracer.so` next to the scripts and prints the
   linked c10/torch/lttng libs. `verify.sh` then checks it. Building on the head
   node is fine (CPU-only); the `.so` runs on both head and compute nodes.

4. **Read the report and act on it** (next section). Do not declare the tracer
   ready unless `verify.sh` prints `RESULT: PASS`.

## Interpreting verify.sh output

One line per check (`[ok]` / `[FAIL]` / `[info]`) and a final `RESULT:` line:

- **libtorch_tracer.so present** — if missing, `build.sh` did not run or failed;
  re-run it after sourcing `env.sh lttng`.
- **all shared libs resolve / links libc10, libtorch, liblttng-ust** — a
  `not found` or a missing link means the env was not sourced before building, or
  rpath is wrong. Re-source `env.sh lttng` in a fresh shell and rebuild.
- **liblttng-ust resolved to system /usr/lib64** (info NOTE) — the wrong ust
  (2.12) won; recording will fail on `lttng_ust_probe_register`. Rebuild in a
  shell where `env.sh lttng` is sourced so the module's 2.14 is first.
- **LD_PRELOAD smoke test** — the decisive one. If it **CRASHED**, the ABI is
  wrong (rebuild with `-DNDEBUG -D_GLIBCXX_USE_CXX11_ABI=1` — `build.sh` already
  does this, so a crash usually means a stale `.so` or a debug libtorch) or a
  symbol is unresolved. A **PASS** means the constructor ran and the callback
  installed cleanly on live torch.

## Reporting back to the user

State plainly: built or not, `RESULT: PASS|FAIL`, where the `.so` is, and — if
FAIL — the single next action. Example:
"Built libtorch_tracer.so (icpx, release ABI). verify.sh RESULT: PASS — libs
resolve, LD_PRELOAD smoke test clean. Ready to record a trace."

## Scope / boundaries

- This skill **does not record or read** traces — it only builds and verifies the
  `.so`. Hand off to the record/view step after `RESULT: PASS`.
- The tracer is **build-once, configure-at-runtime**: never rebuild to change an
  aspect — set the `TRACER_*` env vars when recording. Rebuild only when
  `tracer.cpp` or the `.tp` schema itself changes.
- If a compiler or module version was retired, update `build.sh` / `env.sh`
  rather than dropping the ABI flags — `-DNDEBUG` + CXX11 ABI=1 must be preserved.
