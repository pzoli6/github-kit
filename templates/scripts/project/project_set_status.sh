#!/usr/bin/env bash
# Set the Status field on a Project item identified by its issue/PR URL.
set -euo pipefail

VALID_STATUSES=(Backlog "Plan Review" Ready "In Progress" Blocked "In Review" "Changes Requested" Done Cancelled)

usage() {
  echo "Usage: $(basename "$0") <issue-or-pr-url> <Status>" >&2
  printf 'Valid statuses: %s\n' "${VALID_STATUSES[*]}" >&2
  exit 1
}

[ "$#" -eq 2 ] || usage
ITEM_URL="$1"
STATUS="$2"

valid=0
for s in "${VALID_STATUSES[@]}"; do
  [ "$s" = "$STATUS" ] && valid=1
done
if [ "$valid" -ne 1 ]; then
  echo "error: '$STATUS' is not a recognized Status value." >&2
  usage
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ENV_FILE="$REPO_ROOT/docs/ai/PROJECT_CONFIG.env"
# shellcheck disable=SC1090
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

: "${AGENT_PROJECT_OWNER:=}"
: "${AGENT_PROJECT_NUMBER:=}"

if [ -z "$AGENT_PROJECT_OWNER" ] || [ -z "$AGENT_PROJECT_NUMBER" ] || [ "$AGENT_PROJECT_NUMBER" = "TBD" ]; then
  echo "error: AGENT_PROJECT_OWNER / AGENT_PROJECT_NUMBER are not configured." >&2
  echo "Copy docs/ai/PROJECT_CONFIG.env.example to docs/ai/PROJECT_CONFIG.env and fill in real values," >&2
  echo "or export AGENT_PROJECT_OWNER and AGENT_PROJECT_NUMBER yourself." >&2
  exit 1
fi

# jq is deliberately NOT required: every JSON read here goes through gh --jq, which uses
# gh's built-in engine. Git Bash on Windows ships no jq, and demanding one made these scripts
# unusable there.
for bin in gh; do
  command -v "$bin" >/dev/null 2>&1 || { echo "error: '$bin' is required but not found on PATH." >&2; exit 1; }
done

project_id="$(gh project view "$AGENT_PROJECT_NUMBER" --owner "$AGENT_PROJECT_OWNER" --format json --jq '.id')"
[ -n "$project_id" ] && [ "$project_id" != "null" ] || { echo "error: could not resolve Project #$AGENT_PROJECT_NUMBER for owner $AGENT_PROJECT_OWNER." >&2; exit 1; }

# gh project item-add is idempotent — re-adding an existing URL returns the existing item's ID,
# which is how this script resolves an item ID from a URL without a separate lookup call.
item_id="$(gh project item-add "$AGENT_PROJECT_NUMBER" --owner "$AGENT_PROJECT_OWNER" --url "$ITEM_URL" --format json --jq '.id')"
[ -n "$item_id" ] && [ "$item_id" != "null" ] || { echo "error: could not resolve a Project item for $ITEM_URL." >&2; exit 1; }

# gh's --jq uses gh's built-in jq engine, so no external `jq` binary is needed (Git Bash on
# Windows ships none). It has no --arg, so shell values reach the expression through env.
# One call returns both IDs, tab-separated so a status name with spaces survives.
status_tsv="$(STATUS="$STATUS" gh project field-list "$AGENT_PROJECT_NUMBER" --owner "$AGENT_PROJECT_OWNER" --format json --jq '.fields[] | select(.name=="Status") | [ .id, ([.options[]? | select(.name==env.STATUS) | .id][0] // "") ] | @tsv')"
IFS=$'\t' read -r field_id option_id <<EOF
$status_tsv
EOF

[ -n "$field_id" ] || { echo "error: Project has no 'Status' field." >&2; exit 1; }
[ -n "$option_id" ] || { echo "error: Project 'Status' field has no option named '$STATUS'." >&2; exit 1; }

gh project item-edit \
  --id "$item_id" \
  --project-id "$project_id" \
  --field-id "$field_id" \
  --single-select-option-id "$option_id"

echo "Set Status -> $STATUS for $ITEM_URL"
