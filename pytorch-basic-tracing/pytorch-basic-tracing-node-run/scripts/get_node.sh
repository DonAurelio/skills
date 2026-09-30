#!/usr/bin/env bash
# Reserve an Aurora compute node and print its hostname (for driving over ssh).
#
#   ./get_node.sh [walltime] [queue]      # defaults: 00:60:00  debug
#
# Submits a holding job (sleep) so the node stays reserved while you ssh commands
# to it from the head node -- the pattern this project uses (no interactive TTY
# needed). Prints the node hostname on the LAST line; writes the JOBID to
# /tmp/tracing_node_job_$USER.txt so release_node.sh can find it.
#
# On success the last stdout line is JUST the node hostname (e.g. x4300c3s6b0n0),
# so a caller can:  NODE=$(./get_node.sh | tail -1)
set -o pipefail

WALLTIME="${1:-00:60:00}"
QUEUE="${2:-debug}"
ACCOUNT="${ACCOUNT:-Performance}"
JOBFILE="/tmp/tracing_node_job_${USER}.txt"

echo "[node] submitting holding job (A=$ACCOUNT q=$QUEUE walltime=$WALLTIME)..." >&2
JOBID=$(echo "sleep 3600" | qsub -A "$ACCOUNT" -q "$QUEUE" \
          -l walltime="$WALLTIME" -l filesystems=home -l select=1 \
          -N tracing_node 2>/dev/null)
if [ -z "$JOBID" ]; then echo "[node] qsub FAILED" >&2; exit 1; fi
echo "$JOBID" > "$JOBFILE"
echo "[node] JOBID=$JOBID (saved to $JOBFILE)" >&2

echo "[node] waiting for it to start (state R)..." >&2
NODE=""
for _ in $(seq 1 180); do          # up to ~60 min at 20s cadence
  line=$(qstat "$JOBID" 2>/dev/null | tail -1)
  state=$(echo "$line" | awk '{print $5}')
  case "$state" in
    R)
      NODE=$(qstat -f "$JOBID" 2>/dev/null | grep -oP 'exec_host = \K[^/]+')
      break ;;
    F|"")
      echo "[node] job ended before running (state='$state')" >&2; exit 2 ;;
  esac
  sleep 20
done

if [ -z "$NODE" ]; then echo "[node] timed out waiting for the node" >&2; exit 3; fi
echo "[node] running on: $NODE" >&2
echo "$NODE"          # <- machine-readable last line
