#!/usr/bin/env bash
# Add an issue or PR to the configured GitHub Project and print its item ID.
set -euo pipefail

usage() {
  echo "Usage: $(basename "$0") <issue-or-pr-url>" >&2
  exit 1
}

[ "$#" -eq 1 ] || usage
ITEM_URL="$1"

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

for bin in gh jq; do
  command -v "$bin" >/dev/null 2>&1 || { echo "error: '$bin' is required but not found on PATH." >&2; exit 1; }
done

item_id="$(gh project item-add "$AGENT_PROJECT_NUMBER" \
  --owner "$AGENT_PROJECT_OWNER" \
  --url "$ITEM_URL" \
  --format json | jq -r '.id')"

if [ -z "$item_id" ] || [ "$item_id" = "null" ]; then
  echo "error: gh project item-add did not return an item ID for $ITEM_URL" >&2
  exit 1
fi

echo "$item_id"
