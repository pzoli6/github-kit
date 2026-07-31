#!/usr/bin/env bash
# Set the Status field on a Project item identified by its issue/PR URL.
set -euo pipefail

# No hardcoded status vocabulary on purpose. The Project board is the only authority on which
# Status options exist, and a second list here can only drift out of sync with it. It did: this
# script used to ship "In Progress"/"In Review" while a default GitHub board spells them
# "In progress"/"In review", so every one of those calls failed with a misleading
# "not a recognized Status value" before the board was ever consulted. Validation now happens
# against the board itself, below, and the error lists what the board actually offers.

usage() {
  echo "Usage: $(basename "$0") <issue-or-pr-url> <Status>" >&2
  echo "Status must match an option on the Project's Status field exactly, including case." >&2
  exit 1
}

[ "$#" -eq 2 ] || usage
ITEM_URL="$1"
STATUS="$2"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
# PROJECT_CONFIG.env is gitignored, so a linked worktree doesn't have it — fall back to the
# main checkout's copy (the same anchor publish_agent_branch.sh uses). Without this, an agent
# working in a worktree would silently treat the Project as unconfigured and stop updating the
# board, while the same command from the main checkout works.
ENV_FILE="$REPO_ROOT/docs/ai/PROJECT_CONFIG.env"
if [ ! -f "$ENV_FILE" ]; then
  GIT_COMMON_DIR="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  [ -n "$GIT_COMMON_DIR" ] && ENV_FILE="$(dirname "$GIT_COMMON_DIR")/docs/ai/PROJECT_CONFIG.env"
fi
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
if [ -z "$option_id" ]; then
  echo "error: the Project's 'Status' field has no option named '$STATUS'." >&2
  echo "       Options are matched exactly, including case. This board offers:" >&2
  gh project field-list "$AGENT_PROJECT_NUMBER" --owner "$AGENT_PROJECT_OWNER" --format json \
    --jq '.fields[] | select(.name=="Status") | .options[].name' 2>/dev/null | sed 's/^/         /' >&2
  exit 1
fi

gh project item-edit \
  --id "$item_id" \
  --project-id "$project_id" \
  --field-id "$field_id" \
  --single-select-option-id "$option_id"

echo "Set Status -> $STATUS for $ITEM_URL"
