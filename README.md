# skills

Claude Code skills for Aurora tracing workflows, grouped by family.

## Layout

```
pytorch-basic-tracing/   6 skills — trace PyTorch (RecordFunction) workloads via a custom LTTng-preload tracer
thapi-tracer/            3 skills — build and run THAPI (Tracing Heterogeneous APIs) / iprof
```

Each skill is its own directory (`<name>/SKILL.md`, plus `scripts/` and/or
`examples/` where it has supporting files), so any of them can be copied
individually into `~/.claude/skills/`.

## pytorch-basic-tracing

A linear pipeline for tracing a PyTorch workload with a custom C++
RecordFunction tracer over LTTng, run in this order:

| # | Skill | Purpose |
|---|-------|---------|
| 1 | `pytorch-basic-tracing-environment-config` | Load oneapi + LTTng + babeltrace2 + frameworks in the required order; verify torch imports and the LTTng toolchain |
| 2 | `pytorch-basic-tracing-tracer-build` | Build `libtorch_tracer.so` (LTTng-UST probe + tracer.cpp, release ABI) |
| 3 | `pytorch-basic-tracing-node-run` | Reserve an Aurora compute node and run commands there over ssh (needed for XPU/GPU tracing) |
| 4 | `pytorch-basic-tracing-record` | LD_PRELOAD the tracer, record an LTTng session, convert to text with babeltrace2 |
| 5 | `pytorch-basic-tracing-analyze` | Turn a recorded trace into granularity metrics (entry/exit balance, nesting depth, op frequency, etc.) |
| 6 | `pytorch-basic-tracing-notes` | Scaffold/write up a numbered stage deliverable (README, env.sh, example/, tracer/, traces/) |

Steps 1–2 are one-time setup; step 3 is only needed for GPU/XPU work (the
head node has no devices); steps 4–6 repeat per trace.

## thapi-tracer

Build and run [THAPI](https://github.com/argonne-lcf/THAPI) on Aurora:

| Skill | Purpose |
|-------|---------|
| `thapi-tracer-environment-config` | Clone THAPI, load the build-time module set, create a venv with h2yaml, run autogen.sh |
| `thapi-tracer-build` | Configure (in-tree prefix) + `make install`, verify `iprof` and backend libraries |
| `thapi-tracer-run` | *(placeholder — not yet authored)* run a workload under `iprof` on a compute node |
