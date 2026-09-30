---
name: pytorch-basic-tracing-notes
description: Scaffold and write up a PyTorch tracing deliverable STAGE in the project's established structure — a numbered stage dir (NN_slug) with README.md, optional local-only RUNBOOK.md, env.sh, example/ workloads, tracer/ sources, and traces/ babeltrace2 dumps — following the same file layout, README headings, and reproduce-recipe conventions as stages 01–04. Use when documenting a completed tracing experiment or starting a new stage's notes, so the write-up matches the existing deliverables and its numbers come from the analyze skill.
---

# PyTorch basic tracing — notes / stage write-up

Produce a deliverable **stage** that looks like the ones already in the project
(`deliverables/01…04`): the same directory shape, the same README structure
(intro → toggle table → contents tree → reproduce → results → "what this
demonstrates"), and — when there are environment-specific ops — a **local-only**
RUNBOOK. This is the documentation phase: it turns a recorded + analyzed
experiment into the durable artifact.

## The established structure (match it)

Every stage is a self-contained, reproducible directory:

```
NN_slug/
├── README.md      # the public write-up: question, toggles, contents, reproduce, results
├── RUNBOOK.md     # OPTIONAL, LOCAL-ONLY: exact ops recipe + gotchas (NOT committed)
├── env.sh         # the module recipe (copied, same across stages)
├── example/       # the workload .py files
├── tracer/        # tracer.cpp + .tp + build.sh + run.sh + view.sh (copied, self-contained)
└── traces/        # babeltrace2 text dumps (.txt), one per experiment
```

Two conventions that matter:

- **README is the artifact; RUNBOOK is the lab notebook.** The README is public
  (goes in the notes repo). The RUNBOOK holds machine-specific procedure and the
  "gotchas hit and fixed" — keep it **out of the repo** (the project has done this
  deliberately). Only scaffold a RUNBOOK with `--runbook` when there's real ops
  detail to capture (e.g. a compute-node recording).
- **Results cite numbers, not adjectives.** Every finding in the README is backed
  by a fenced excerpt of actual counts (per-vtid entry/exit, maxdepth, event
  totals, capture %). Get those from the `pytorch-basic-tracing-analyze` skill —
  do not eyeball them.

## Procedure

1. **Scaffold the stage.** `scripts/scaffold_stage.sh` creates the dir tree, copies
   the current `env.sh` + tracer sources from the sibling skills (so the stage is
   self-contained like 01–04), and writes README (and optionally RUNBOOK) from
   templates with the stage name filled in:

   ```bash
   bash "<skill-dir>/scripts/scaffold_stage.sh" \
     ~/dev/pytorch_tracing_recordfunction/deliverables 05_slug [--runbook]
   ```

   It refuses to overwrite an existing stage dir.

2. **Add the workloads + traces.** Put the `.py` workloads in `example/` and the
   babeltrace2 dumps in `traces/` (the record skill writes these; copy the `.txt`
   in). Keep the trace filenames descriptive (`<label>.txt`) and mention their
   event/vtid counts in the contents tree.

3. **Get the numbers from the analyze skill.** Run
   `pytorch-basic-tracing-analyze` on each trace (and `--compare` for
   global-vs-local) and lift the counts straight into the README's results
   section and the contents-tree annotations.

4. **Fill the README placeholders.** Replace every `{{…}}` with real content:
   the question this stage answers, the toggle table, the reproduce commands (the
   exact `TRACER_*`/`DEVICE` lines you ran), and one `### finding` per result with
   its trace excerpt. End with the "What this demonstrates" bullets, each tied to a
   number above.

5. **Fill the RUNBOOK** (if scaffolded) with the real qsub/ssh/LTTNG_HOME steps and
   — most importantly — the **gotchas you actually hit and how you fixed them**.
   Confirm it is not tracked by the repo before finishing.

## Writing conventions (from stages 01–04)

- Title line: `# Step N — <declarative phrase>`.
- Say whether the tracer changed ("UNCHANGED from Step N — same `.so`") — usually
  it didn't; behaviour is selected by runtime toggles.
- Present any new axis as a small markdown table with the default value marked.
- Contents tree annotates each trace with `(N events, M vtid)`.
- Reproduce section is copy-pasteable: `source env.sh lttng` → `build.sh` → the
  `./run.sh` lines.
- Findings are declarative `###` headings; each has a fenced block of the concrete
  counts. Close with a bulleted "What this demonstrates".

## Reporting back to the user

State what was scaffolded/written and what still needs filling. Example:
"Scaffolded deliverables/05_dispatch_keys (README + tracer + env, no RUNBOOK).
Pulled counts from analyze into the results section; the reproduce block and
finding #2's excerpt still need your numbers."

## Scope / boundaries

- This skill **structures and writes** the stage; it does not record traces or
  compute the numbers (record + analyze skills do). Pull results from analyze.
- **Never commit RUNBOOK.md** to the notes repo — it's local-only by project
  convention.
- Match the existing stages rather than inventing a new layout; if the structure
  must change, change it everywhere, not just in the new stage.
