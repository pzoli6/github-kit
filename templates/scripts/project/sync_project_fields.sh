#!/usr/bin/env bash
# Single entry point for updating GitHub Project fields at a fixed set of workflow checkpoints.
# Delegates to project_set_status.sh / project_set_text.sh so field-resolution logic stays in one
# place. Checkpoints mirror the Status/Validation vocabularies in AGENTS.md — see
# docs/ai/AGENT_WORKFLOW.md for when each one applies.
set -euo pipefail

VALID_CHECKPOINTS=(
  issue_created branch_published plan_ready implementation_started blocked
  validation_passed validation_failed validation_partial validation_manual validation_na
  handoff_updated pr_opened changes_requested done cancelled metadata
)

usage() {
  echo "Usage: $(basename "$0") <checkpoint> <issue-or-pr-url> [text]" >&2
  printf 'Valid checkpoints: %s\n' "${VALID_CHECKPOINTS[*]}" >&2
  cat >&2 <<'EOF'
Notes:
  branch_published        [text] = the branch name (required)
  blocked                 [text] = the reason (required)
  pr_opened               [text] = the PR URL (required)
  implementation_started  [text] = optional Last Agent Update note
  handoff_updated         [text] = optional note (defaults to "Handoff file updated")
  metadata                [text] = required "Field=Value,Field=Value" pairs, e.g.
                          "Agent=Claude Code,Area=backend,Risk=Low,Environment=staging".
                          Pairs with an empty or "TBD" value are skipped, not written.
EOF
  exit 1
}

[ "$#" -ge 2 ] || usage
CHECKPOINT="$1"
ITEM_URL="$2"
TEXT="${3:-}"

# Every "Last Agent Update" write is timestamp-prefixed (UTC, ISO-8601) so
# scripts/project/check_resume_safety.sh can tell how stale a claim is without a dedicated field.
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SET_STATUS="$REPO_ROOT/scripts/project/project_set_status.sh"
SET_TEXT="$REPO_ROOT/scripts/project/project_set_text.sh"

case "$CHECKPOINT" in
  issue_created)
    "$SET_STATUS" "$ITEM_URL" "Ready"
    ;;
  branch_published)
    [ -n "$TEXT" ] || { echo "error: 'branch_published' requires the branch name as [text]." >&2; exit 1; }
    "$SET_STATUS" "$ITEM_URL" "In Progress"
    "$SET_TEXT" "$ITEM_URL" "Branch" "$TEXT"
    ;;
  plan_ready)
    "$SET_STATUS" "$ITEM_URL" "Plan Review"
    ;;
  implementation_started)
    "$SET_TEXT" "$ITEM_URL" "Last Agent Update" "$TIMESTAMP ${TEXT:-Implementation started}"
    ;;
  blocked)
    [ -n "$TEXT" ] || { echo "error: 'blocked' requires a reason as [text]." >&2; exit 1; }
    "$SET_STATUS" "$ITEM_URL" "Blocked"
    "$SET_TEXT" "$ITEM_URL" "Last Agent Update" "$TIMESTAMP Blocked: $TEXT"
    ;;
  validation_passed)
    "$SET_TEXT" "$ITEM_URL" "Validation" "Passed"
    ;;
  validation_failed)
    "$SET_TEXT" "$ITEM_URL" "Validation" "Failed"
    ;;
  validation_partial)
    "$SET_TEXT" "$ITEM_URL" "Validation" "Partial"
    ;;
  validation_manual)
    "$SET_TEXT" "$ITEM_URL" "Validation" "Manual Required"
    ;;
  validation_na)
    "$SET_TEXT" "$ITEM_URL" "Validation" "Not Applicable"
    ;;
  handoff_updated)
    "$SET_TEXT" "$ITEM_URL" "Handoff" "${TEXT:-Handoff file updated}"
    "$SET_TEXT" "$ITEM_URL" "Last Agent Update" "$TIMESTAMP ${TEXT:-Handoff file updated}"
    ;;
  pr_opened)
    [ -n "$TEXT" ] || { echo "error: 'pr_opened' requires the PR URL as [text]." >&2; exit 1; }
    "$SET_STATUS" "$ITEM_URL" "In Review"
    "$SET_TEXT" "$ITEM_URL" "PR URL" "$TEXT"
    ;;
  changes_requested)
    "$SET_STATUS" "$ITEM_URL" "Changes Requested"
    ;;
  done)
    "$SET_STATUS" "$ITEM_URL" "Done"
    ;;
  cancelled)
    "$SET_STATUS" "$ITEM_URL" "Cancelled"
    ;;
  metadata)
    [ -n "$TEXT" ] || { echo "error: 'metadata' requires 'Field=Value,Field=Value' pairs as [text]." >&2; exit 1; }
    IFS=',' read -r -a pairs <<< "$TEXT"
    for pair in "${pairs[@]}"; do
      field="${pair%%=*}"
      value="${pair#*=}"
      if [ -n "$value" ] && [ "$value" != "TBD" ]; then
        "$SET_TEXT" "$ITEM_URL" "$field" "$value"
      fi
    done
    ;;
  *)
    usage
    ;;
esac
