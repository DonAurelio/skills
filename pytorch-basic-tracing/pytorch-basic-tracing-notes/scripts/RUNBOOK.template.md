# Step {{STEP}} — runbook (LOCAL ONLY — do not commit to the repo)

{{The exact operational procedure that produced this stage's traces — the parts
too environment-specific or too rough for the README. Keep this file OUT of the
notes repo (the README is the public artifact; this is the lab notebook).}}

{{If a compute node is needed, state why (e.g. head node has no XPU).}}

## 1. Get a compute node (if the device is needed)

```bash
qsub -A Performance -q debug -l walltime=00:60:00 -l filesystems=home -l select=1 -I
# or drive over ssh (no TTY): see the pytorch-basic-tracing-node-run skill.
```

## 2. Environment (NOT propagated to the node — re-source there)

```bash
REPO=$HOME/dev/pytorch_tracing_recordfunction        # adjust to your checkout
cd $REPO/deliverables/{{STAGE_DIR}}
source env.sh lttng
```

## 3. Isolate LTTng to the node (REQUIRED on a compute node)

```bash
export LTTNG_HOME="/tmp/lttng_${USER}_$$"
mkdir -p "$LTTNG_HOME"
```

## 4. Build + record

```bash
cd tracer && ./build.sh
{{# the ./run.sh commands with their toggles}}
```

## 5. Dump traces to text (into traces/)

```bash
{{for L in <labels>; do DIR=$(ls -dt "$LTTNG_HOME"/lttng-traces/rec-$L-* | head -1); ./view.sh "$DIR" > ../traces/$L.txt; done}}
```

## Gotchas hit (and fixed)

- {{record every real problem + its fix here — this is the highest-value part of a
  runbook; it's what saves the next run.}}

## What the traces showed (see README.md §"The results")

- {{one bullet per finding, cross-referencing the README}}
