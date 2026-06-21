#!/usr/bin/env bash
# Create (or update) the standard status:/type:/risk: labels used by the github-kit agent
# workflow. Idempotent — safe to re-run; existing labels are updated in place via --force.
set -uo pipefail

for bin in gh; do
  command -v "$bin" >/dev/null 2>&1 || { echo "error: '$bin' is required but not found on PATH." >&2; exit 1; }
done

# name|color|description
LABELS=(
  "status:ready-for-agent|0E8A16|Issue is ready for an AI agent to pick up"
  "type:agent-task|5319E7|Task intended for an AI agent to implement"
  "type:bug|D73A4A|Something isn't working"
  "type:feature|A2EEEF|New feature or request"
  "risk:low|C2E0C6|Low-risk change"
  "risk:medium|FBCA04|Medium-risk change"
  "risk:high|B60205|High-risk change requiring extra review"
)

failed=0

for entry in "${LABELS[@]}"; do
  IFS='|' read -r name color description <<< "$entry"
  if gh label create "$name" --color "$color" --description "$description" --force >/dev/null 2>&1; then
    echo "OK      label: $name"
  else
    echo "FAILED  label: $name"
    failed=1
  fi
done

echo
if [ "$failed" -ne 0 ]; then
  echo "Some labels failed to create/update — check 'gh auth status' and repo permissions." >&2
  exit 1
fi

echo "Standard labels created/updated."
