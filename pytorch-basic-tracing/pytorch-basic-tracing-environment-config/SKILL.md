---
name: pytorch-basic-tracing-environment-config
description: Configure and VERIFY the environment for PyTorch RecordFunction tracing on Aurora (oneapi + LTTng + babeltrace2 + frameworks, loaded in the one order that works), then confirm torch imports cleanly, the LTTng toolchain is present, and report whether this is a head node or a device node with its XPU count. Use when setting up, repairing, or sanity-checking a tracing shell before building the tracer or recording a trace — on a login/head node or a qsub compute node.
---

# PyTorch basic tracing — environment config

Bring a shell (head node or `qsub` compute node) to a **known-good, verified**
state for RecordFunction tracing, then report exactly what is and isn't ready.
This skill does **setup + verification only** — it stops before building the
tracer `.so` (that is a separate step/skill).

## Why this needs a skill, not a one-liner

The module load **order is load-bearing** and has bitten this project before:

- The LTTng modules pull in oneapi, whose SYCL runtime and spack python would
  otherwise **shadow the ones torch was built against** — `import torch` then dies
  on an undefined `sycl::queue` symbol. **`frameworks` must load LAST** so its
  python + libsycl win on `PATH` / `LD_LIBRARY_PATH`.
- The module env **does not propagate** across shells or to compute nodes, so it
  must be re-established in every fresh shell (including over `ssh` to a node).
- "It sourced without error" is **not** the same as "torch imports and the trace
  toolchain is present" — verification is the point.

## Procedure

1. **Locate the bundled scripts.** They live next to this file:
   - `scripts/env.sh` — the canonical module recipe (correct order baked in).
   - `scripts/verify.sh` — non-destructive checks; prints a PASS/FAIL report.

   Resolve the skill directory (the folder containing this `SKILL.md`) and use its
   absolute path for both — an `ssh`'d compute-node shell starts in `$HOME`, so
   relative paths fail.

2. **Decide the profile with the user's task in mind:**
   - `lttng` profile — loads oneapi + lttng-tools + babeltrace2 + frameworks.
     Needed to **record or read** traces (`lttng`, `lttng-gen-tp`, `babeltrace2`).
   - default profile — loads frameworks only. Enough to **run workloads / build**
     but has **no** LTTng tools. When in doubt for a tracing task, use `lttng`.

3. **Source the env, then verify — in the SAME shell.** Sourcing sets the module
   env; it is lost if you start a new shell between source and check. Run:

   ```bash
   source "<skill-dir>/scripts/env.sh" lttng && bash "<skill-dir>/scripts/verify.sh"
   ```

   For the default (no-LTTng) profile, drop the `lttng` argument; `verify.sh`
   auto-detects which tools to expect from what is loaded.

   On a compute node reached over ssh, run both in one remote command from an
   absolute path, e.g.
   `ssh <node> 'source <skill-dir>/scripts/env.sh lttng && bash <skill-dir>/scripts/verify.sh'`.

4. **Read the report and act on it** (see next section). Do not declare the
   environment ready unless `verify.sh` prints `RESULT: PASS`.

## Interpreting verify.sh output

The verifier prints one line per check (`[ok]` / `[FAIL]` / `[info]`) and a final
`RESULT:` line. Key checks and the fix when one fails:

- **`import torch`** — if this FAILs after a clean source, the load order was
  violated (something shadowed frameworks). Re-source in a **fresh** shell using
  the bundled `env.sh` (do not hand-load modules in a different order).
- **`lttng-gen-tp` / `lttng` / `babeltrace2` present** — only checked for the
  `lttng` profile. If missing, you sourced the default profile; re-source with the
  `lttng` argument.
- **`TORCH_INCLUDE` / `TORCH_LIB` exported** — needed later for building; if empty,
  torch did not import, so fix that first.
- **Node type + XPU count** — reported as `[info]`, never a failure:
  - `xpu count = 0` → this is a **head/login node**. Correct for building and for
    CPU workloads; GPU runs need a compute node.
  - `xpu count >= 1` → a **device node**. Also note if a **stale sessiond lock** in
    shared `$HOME/.lttng` is flagged — on a compute node set a node-local
    `LTTNG_HOME` (e.g. `/tmp/lttng_$USER_$$`) before recording, or `lttng create`
    fails with "A session daemon is already running".

## Reporting back to the user

State plainly: which profile was loaded, PASS/FAIL, node type + XPU count, and — if
FAIL — the single next action. Example:
"lttng profile loaded, RESULT: PASS. Compute node, 12 XPUs. Ready to build/record;
set a node-local LTTNG_HOME before recording."

## Scope / boundaries

- This skill **does not build** the tracer or record traces — it only prepares and
  verifies the shell. Hand off to the build/record step after `RESULT: PASS`.
- The recipe pins Aurora module versions (oneapi 2025.3.1, lttng-tools 2.14.0,
  babeltrace2 2.1.2-archive, frameworks 2025.3.1). If a module load fails because a
  version was retired, update `scripts/env.sh` rather than reordering the loads —
  the **order** (frameworks last) must be preserved.
