#!/usr/bin/env bash
# Set a text field on a Project item identified by its issue/PR URL.
set -euo pipefail

usage() {
  echo "Usage: $(basename "$0") <issue-or-pr-url> <field-name> <value>" >&2
  echo "Example: $(basename "$0") https://github.com/o/r/pull/1 'Last Agent Update' 'Implementation done, awaiting review'" >&2
  exit 1
}

[ "$#" -eq 3 ] || usage
ITEM_URL="$1"
FIELD_NAME="$2"
VALUE="$3"

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

item_id="$(gh project item-add "$AGENT_PROJECT_NUMBER" --owner "$AGENT_PROJECT_OWNER" --url "$ITEM_URL" --format json --jq '.id')"
[ -n "$item_id" ] && [ "$item_id" != "null" ] || { echo "error: could not resolve a Project item for $ITEM_URL." >&2; exit 1; }

# gh's --jq uses gh's built-in jq engine, so no external `jq` binary is needed (Git Bash on
# Windows ships none). It has no --arg, so shell values reach the expression through env.
# A field name with spaces ("Last Agent Update") is exactly why env is used here.
field_tsv="$(FIELD_NAME="$FIELD_NAME" gh project field-list "$AGENT_PROJECT_NUMBER" --owner "$AGENT_PROJECT_OWNER" --format json --jq '.fields[] | select(.name==env.FIELD_NAME) | [ .id, (.type // "") ] | @tsv')"
IFS=$'\t' read -r field_id field_type <<EOF
$field_tsv
EOF

[ -n "$field_id" ] || { echo "error: Project has no field named '$FIELD_NAME'." >&2; exit 1; }

case "$field_type" in
  ProjectV2SingleSelectField)
    echo "error: '$FIELD_NAME' is a single-select field. Use project_set_status.sh (or the same --single-select-option-id pattern) instead of free text." >&2
    exit 1
    ;;
  ProjectV2IterationField)
    echo "error: '$FIELD_NAME' is an iteration field — not supported by this script." >&2
    exit 1
    ;;
  ProjectV2Field|"")
    : # plain text/number/date-ish field — proceed with --text
    ;;
  *)
    echo "warning: '$FIELD_NAME' has unrecognized type '$field_type' — attempting --text anyway." >&2
    ;;
esac

gh project item-edit \
  --id "$item_id" \
  --project-id "$project_id" \
  --field-id "$field_id" \
  --text "$VALUE"

echo "Set '$FIELD_NAME' -> '$VALUE' for $ITEM_URL"
