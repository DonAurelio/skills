---
name: pytorch-basic-tracing-node-run
description: Reserve an Aurora compute node (needed for XPU/GPU tracing, since the login/head node has zero devices) and send execution to it over ssh with the tracing module environment sourced — qsub a holding job, wait for it to run, get the node hostname, run commands there with env.sh already sourced from an absolute path, then release the reservation. Use when a tracing step needs a real GPU: recording an XPU trace, or any build/run that must happen on a device node.
---

# PyTorch basic tracing — node run

Get a real Aurora **compute node** and drive work on it over `ssh`. The
login/head node has **no XPU** (`torch.xpu.device_count()` == 0), so every GPU
recording needs a device node. This skill automates the reserve → wait → ssh →
release loop that the project uses, handling the two Aurora traps: the module env
is **not propagated** to the node, and `ssh` lands in `$HOME`, not the repo.

## Why a holding job (not just `qsub -I`)

`qsub -I` gives an interactive TTY, which an automated flow can't drive. Instead
`get_node.sh` submits a **holding job** (`sleep 3600`), waits for it to reach the
running state, and prints the assigned node hostname. You then `ssh` commands to
that node from the head node for the life of the reservation. Home is shared, so
the repo, tracer source, and `.so` are already visible on the node — nothing to
copy.

## Procedure

1. **Reserve a node.** `scripts/get_node.sh` prints progress on stderr and the
   **node hostname as its last stdout line**:

   ```bash
   NODE=$(bash "<skill-dir>/scripts/get_node.sh" | tail -1)
   # optional args: get_node.sh <walltime> <queue>   (default 00:60:00 debug)
   # ACCOUNT env overrides the -A account (default Performance)
   ```

   It saves the JOBID to `/tmp/tracing_node_job_$USER.txt` so `release_node.sh`
   can find it. If it prints "timed out"/"job ended", the queue was busy — retry
   or pick a shorter walltime.

2. **Confirm the node is a real device node** (optional but wise) — reuse the
   env-config skill's verify, which reports the XPU count:

   ```bash
   bash "<skill-dir>/scripts/run_on_node.sh" "$NODE" \
     'bash ~/.claude/skills/pytorch-basic-tracing-environment-config/scripts/verify.sh'
   # expect: XPU count = 12 -> DEVICE (compute) node, RESULT: PASS
   ```

3. **Send execution.** `run_on_node.sh` sources `env.sh` (in the SAME remote
   shell, absolute path) then runs your command. Default profile is `lttng`:

   ```bash
   bash "<skill-dir>/scripts/run_on_node.sh" "$NODE" \
     'DEVICE=xpu TRACER_SCOPES=function+backward \
      bash ~/.claude/skills/pytorch-basic-tracing-record/scripts/run.sh \
        xpu_intraop ~/.claude/skills/pytorch-basic-tracing-record/examples/train_intraop.py \
      && bash ~/.claude/skills/pytorch-basic-tracing-record/scripts/verify.sh'
   ```

   Use `--profile default` for a frameworks-only (no-LTTng) command. The record
   skill's `run.sh` sets a **node-local `LTTNG_HOME`** itself, so recordings won't
   hit the shared-home sessiond lock — don't override it back to `$HOME`.

4. **Release the node** as soon as you're done — a debug reservation otherwise
   holds the node until walltime:

   ```bash
   bash "<skill-dir>/scripts/release_node.sh"     # qdels the saved JOBID
   ```

## Interpreting results

- **get_node.sh prints a hostname** (e.g. `x4300c3s6b0n0`) → reserved and running.
- **run_on_node.sh** returns the remote command's own exit code and output — treat
  a `RESULT: PASS` / trace summary exactly as if it ran locally, since home is
  shared and any files it wrote are already visible on the head node.
- Because output comes back over one ssh channel, a remote failure shows up inline;
  there's no separate log to fetch (home is shared if the command wrote one).

## Reporting back to the user

State the node, what ran there, and the outcome, then confirm release. Example:
"Reserved x4300c3s6b0n0 (12 XPUs). Recorded xpu_intraop there: 400 events / 2
vtids, RESULT: PASS. Node released (qdel)."

## Scope / boundaries

- This skill **reserves, runs, and releases** — it does not itself build, record,
  or analyze. Compose it with the build / record / analyze skills as the remote
  command.
- **Always release** the node when the work is done (or on failure). Leaving a
  debug reservation idle wastes an allocation and blocks the queue.
- Adjust `-A` account via `ACCOUNT=...`, walltime/queue via get_node.sh args, if
  the defaults (Performance / debug / 60 min) don't fit.
