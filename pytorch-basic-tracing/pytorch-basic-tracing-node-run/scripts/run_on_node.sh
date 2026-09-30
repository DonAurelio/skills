#!/usr/bin/env bash
# Send a command to an Aurora compute node with the tracing env already sourced.
#
#   ./run_on_node.sh <node> '<remote command>'
#   ./run_on_node.sh <node> --profile default '<remote command>'   # frameworks only
#
# Wraps the two things that always trip up a remote command on Aurora:
#   1. the module env is NOT propagated -- so it sources env.sh <profile> first,
#      in the SAME remote shell, from an ABSOLUTE path (ssh lands in $HOME);
#   2. for recording, the shared $HOME/.lttng sessiond lock -- callers should let
#      the record skill's run.sh set a node-local LTTNG_HOME (it does by default).
#
# ENV_SH overrides the env script path (default: the env-config skill's copy).
set -o pipefail

NODE="${1:?usage: run_on_node.sh <node> [--profile default|lttng] '<cmd>'}"; shift
PROFILE="lttng"
if [ "${1:-}" = "--profile" ]; then PROFILE="${2:?}"; shift 2; fi
CMD="${1:?usage: run_on_node.sh <node> [--profile ...] '<cmd>'}"

ENV_SH="${ENV_SH:-$HOME/.claude/skills/pytorch-basic-tracing-environment-config/scripts/env.sh}"

echo "[node-run] $NODE  (profile=$PROFILE)" >&2
# One remote shell: source env, then run the caller's command. Absolute env path.
ssh "$NODE" "source '$ENV_SH' ${PROFILE} && { ${CMD} ; }"
