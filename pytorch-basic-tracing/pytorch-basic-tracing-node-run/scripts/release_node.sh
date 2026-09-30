#!/usr/bin/env bash
# Release the compute node reserved by get_node.sh (qdel the holding job).
#
#   ./release_node.sh [JOBID]      # defaults to the one get_node.sh saved
#
# ALWAYS release when done -- a debug reservation otherwise ties up a node until
# walltime expires.
set -o pipefail
JOBFILE="/tmp/tracing_node_job_${USER}.txt"
JOBID="${1:-}"
[ -z "$JOBID" ] && [ -f "$JOBFILE" ] && JOBID="$(cat "$JOBFILE")"
[ -z "$JOBID" ] && { echo "[node] no JOBID given and none saved in $JOBFILE"; exit 1; }

qdel "$JOBID" && echo "[node] released $JOBID" || echo "[node] qdel failed (already gone?)"
rm -f "$JOBFILE"
