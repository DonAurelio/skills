#!/usr/bin/env bash
# Scaffold a new deliverable STAGE directory in the project's established layout.
#
#   ./scaffold_stage.sh <deliverables-dir> <NN_slug> [--runbook]
#     e.g. ./scaffold_stage.sh ~/dev/pytorch_tracing_recordfunction/deliverables 05_dispatch_keys
#
# Creates:
#   deliverables/NN_slug/
#   ├── README.md          # from README template (headings the project uses)
#   ├── RUNBOOK.md         # only with --runbook (local-only ops; keep OUT of repo)
#   ├── env.sh             # copied from the env-config skill (module recipe)
#   ├── example/           # workloads go here (.py)
#   ├── tracer/            # tracer.cpp/.tp/build.sh/run.sh/view.sh (copied)
#   └── traces/            # babeltrace2 dumps (.txt) go here
#
# Copies the CURRENT tracer + env from the skills so a stage is self-contained and
# reproducible, matching stages 01-04. Never overwrites an existing stage dir.
set -euo pipefail

DELIV="${1:?usage: scaffold_stage.sh <deliverables-dir> <NN_slug> [--runbook]}"
NAME="${2:?usage: scaffold_stage.sh <deliverables-dir> <NN_slug> [--runbook]}"
WANT_RUNBOOK=0
[ "${3:-}" = "--runbook" ] && WANT_RUNBOOK=1

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILLS="$HOME/.claude/skills"
STAGE="$DELIV/$NAME"

[ -e "$STAGE" ] && { echo "ERROR: $STAGE already exists -- refusing to overwrite." >&2; exit 1; }
mkdir -p "$STAGE/example" "$STAGE/tracer" "$STAGE/traces"
echo "[scaffold] created $STAGE/{example,tracer,traces}"

# env.sh -- the canonical module recipe.
ENV_SRC="$SKILLS/pytorch-basic-tracing-environment-config/scripts/env.sh"
[ -f "$ENV_SRC" ] && cp "$ENV_SRC" "$STAGE/env.sh" && echo "[scaffold] copied env.sh"

# tracer sources -- current build-once/configure-at-runtime tracer + record scripts.
TB="$SKILLS/pytorch-basic-tracing-tracer-build/scripts"
REC="$SKILLS/pytorch-basic-tracing-record/scripts"
for f in tracer.cpp pytorch_tracepoints.tp build.sh; do
  [ -f "$TB/$f" ] && cp "$TB/$f" "$STAGE/tracer/$f"
done
for f in run.sh view.sh; do
  [ -f "$REC/$f" ] && cp "$REC/$f" "$STAGE/tracer/$f"
done
echo "[scaffold] copied tracer sources (tracer.cpp, .tp, build.sh, run.sh, view.sh)"

# README from template, with the stage name substituted.
STEPNUM="${NAME%%_*}"; STEPNUM="${STEPNUM#0}"
sed -e "s/{{STAGE_DIR}}/$NAME/g" -e "s/{{STEP}}/$STEPNUM/g" \
    "$HERE/README.template.md" > "$STAGE/README.md"
echo "[scaffold] wrote README.md (fill in the {{...}} placeholders)"

if [ "$WANT_RUNBOOK" = "1" ]; then
  sed -e "s/{{STAGE_DIR}}/$NAME/g" -e "s/{{STEP}}/$STEPNUM/g" \
      "$HERE/RUNBOOK.template.md" > "$STAGE/RUNBOOK.md"
  echo "[scaffold] wrote RUNBOOK.md  (LOCAL ONLY -- do NOT commit to the repo)"
fi

echo "[scaffold] done. Next: add workloads to example/, record into traces/, fill README.md."
