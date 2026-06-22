#!/usr/bin/env bash
# Create (or update) the standard status:/type:/risk:/agent: labels used by the github-kit agent
# workflow. Idempotent — safe to re-run; existing labels are updated in place via --force.
set -uo pipefail

for bin in gh; do
  command -v "$bin" >/dev/null 2>&1 || { echo "error: '$bin' is required but not found on PATH." >&2; exit 1; }
done

# name|color|description
LABELS=(
  "status:ready-for-agent|0E8A16|Issue is ready for an AI agent to pick up"
  "status:in-progress|FBCA04|An agent is actively working on this"
  "status:blocked|B60205|Work is blocked — see issue/handoff for why"
  "status:in-review|1D76DB|Draft or real PR is open and needs review"
  "status:changes-requested|D93F0B|Human reviewer requested changes"
  "status:done|0E8A16|Work is merged, closed, or complete"
  "type:agent-task|5319E7|Task intended for an AI agent to implement"
  "type:bug|D73A4A|Something isn't working"
  "type:feature|A2EEEF|New feature or request"
  "type:docs|0075CA|Documentation-only change"
  "type:workflow|5319E7|github-kit / CI / agent-workflow change"
  "risk:low|C2E0C6|Low-risk change"
  "risk:medium|FBCA04|Medium-risk change"
  "risk:high|B60205|High-risk change requiring extra review"
  "agent:claude|D4C5F9|Claude Code worked this task"
  "agent:codex|C5DEF5|Codex worked this task"
  "agent:cursor|BFE5BF|Cursor worked this task"
  "agent:antigravity|F9D0C4|Antigravity worked this task"
  "agent:manual|E4E669|Done by a human, no agent involved"
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
