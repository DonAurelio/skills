# Step {{STEP}} — {{ONE-LINE TITLE: what this stage measures}}

{{2-4 sentences: what question this stage answers, how it builds on the previous
stage, and the one-line result. State up front whether the tracer changed from the
previous stage — usually it did NOT (same .so, behaviour selected by toggles).}}

{{If this stage introduces a toggle/axis, present it as a table like this:}}

| Toggle | Values | Effect |
|---|---|---|
| `{{ENV}}` | `{{a}}` (default) \| `{{b}}` | {{what it changes}} |

{{One sentence on WHY it's an axis, not a fixed choice.}}

{{If a device/compute node is required, say so and point at RUNBOOK.md.}}

## Contents

```
{{STAGE_DIR}}/
├── README.md                    # this file
{{if runbook:}}├── RUNBOOK.md                   # exact reproduce recipe (kept local, not in repo)
├── env.sh                       # module recipe (same across stages)
├── example/
│   └── {{workload}}.py          # {{one-line description}}
├── tracer/
│   ├── tracer.cpp               # {{"UNCHANGED from Step N" or what changed}}
│   ├── pytorch_tracepoints.tp   # LTTng-UST schema: name + scope + depth + args
│   ├── build.sh                 # lttng-gen-tp + compile -> libtorch_tracer.so
│   ├── run.sh                   # run.sh <label> <workload.py>  (toggles via env)
│   └── view.sh                  # babeltrace2 <trace-dir>
└── traces/                      # babeltrace2 dumps
    └── {{label}}.txt            # {{workload/toggle summary}}  ({{N events, M vtid}})
```

## How to reproduce

```bash
source env.sh lttng          # oneapi -> lttng -> babeltrace2 -> frameworks (LAST)
cd tracer && ./build.sh      # -> tracer/libtorch_tracer.so
{{# one ./run.sh line per experiment, with its TRACER_*/DEVICE/... toggles}}
{{TRACER_SCOPES=... ./run.sh <label> ../example/<workload>.py}}
```

## Where the traces are written

{{Note LTTNG_HOME if a compute node was used; give the view.sh command to read one.}}
The `traces/*.txt` files here are those babeltrace2 dumps, saved so the results are
readable without re-running.

## The results

### {{Finding 1 — short declarative headline}}
{{Prose + a fenced excerpt of the ACTUAL trace numbers (per-vtid entry/exit,
maxdepth, event counts) that back the claim. Cite counts, not adjectives. Use the
analyze skill's output for these numbers.}}

```
{{paste the concrete counts / trace excerpt here}}
```

### {{Finding 2 ...}}

## What this demonstrates

- **{{claim}}** — {{one sentence, tied to a number above}}.
- {{...}}
