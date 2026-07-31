#!/usr/bin/env bash
# Pre-flight check: is it safe to start or resume work on this issue right now?
#
# Stops cold (exit 2) if the issue is closed or its linked PR (found via the same
# "Closes/Fixes/Resolves #<n>" body convention create_agent_pr.sh enforces) is already merged or
# closed. Otherwise reports (exit 3, without stopping the caller) if another agent's claim on the
# issue's Project item — Status + the timestamp sync_project_fields.sh prepends to
# "Last Agent Update" — still looks fresh, so the caller can report it instead of duplicating work.
# Reuses the existing Agent/Status/Last Agent Update fields — no new Project field required.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: check_resume_safety.sh --issue <issue-url-or-number> [--agent <name>]

Exit codes:
  0  safe to proceed
  2  stop — the issue is closed, or its linked PR is already merged/closed
  3  active elsewhere — another agent's claim looks fresh; report it, don't duplicate work
EOF
  exit 1
}

ISSUE=""
AGENT_NAME=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --issue) ISSUE="${2:-}"; shift 2 ;;
    --agent) AGENT_NAME="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done

[ -n "$ISSUE" ] || usage

# jq is deliberately NOT required: every JSON read here goes through gh --jq, which uses
# gh's built-in engine. Git Bash on Windows ships no jq, and demanding one made these scripts
# unusable there.
for bin in gh; do
  command -v "$bin" >/dev/null 2>&1 || { echo "error: '$bin' is required but not found on PATH." >&2; exit 1; }
done

gh auth status >/dev/null 2>&1 || { echo "error: gh is not authenticated. Run 'gh auth login'." >&2; exit 1; }

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
: "${AGENT_CLAIM_STALENESS_MINUTES:=120}"

case "$ISSUE" in
  http*) ISSUE_URL="$ISSUE"; ISSUE_NUM="$(gh issue view "$ISSUE_URL" --json number --jq '.number')" ;;
  *) ISSUE_NUM="$ISSUE"; ISSUE_URL="$(gh issue view "$ISSUE_NUM" --json url --jq '.url')" ;;
esac
[ -n "$ISSUE_URL" ] && [ "$ISSUE_URL" != "null" ] || { echo "error: could not resolve issue for '$ISSUE'." >&2; exit 1; }

# gh's --jq uses gh's built-in jq engine, so no external `jq` binary is needed (Git Bash on
# Windows ships none). It has no --arg, so shell values reach the expression through env.
issue_tsv="$(gh issue view "$ISSUE_NUM" --json state,stateReason --jq '[ .state, (.stateReason // "unknown") ] | @tsv')"
IFS=$'\t' read -r issue_state issue_reason <<EOF
$issue_tsv
EOF
if [ "$issue_state" = "CLOSED" ]; then
  reason="${issue_reason:-unknown}"
  echo "STOP: issue #$ISSUE_NUM is closed (reason: $reason). Do not resume — confirm with the user before doing anything else." >&2
  exit 2
fi

# List recent PRs and filter locally (rather than gh's --search) so this doesn't depend on
# GitHub's free-text search tokenization of bare issue numbers.
# Emits "<number>\t<url>\t<state>" for the first linked PR, or nothing when there is none.
linked_pr="$(ISSUE_NUM="$ISSUE_NUM" gh pr list --state all --limit 100 --json number,url,state,body --jq '[.[] | select(.body // "" | test("(?i)(closes|fixes|resolves) #" + env.ISSUE_NUM + "\\b"))] | .[0] // empty | [ .number, .url, .state ] | @tsv' 2>/dev/null || true)"

if [ -n "$linked_pr" ]; then
  IFS=$'\t' read -r pr_number pr_url pr_state <<EOF
$linked_pr
EOF
  case "$pr_state" in
    MERGED)
      echo "STOP: linked PR #$pr_number ($pr_url) is already merged. Do not resume work on issue #$ISSUE_NUM." >&2
      exit 2
      ;;
    CLOSED)
      echo "STOP: linked PR #$pr_number ($pr_url) is closed without merging. Confirm with the user before resuming issue #$ISSUE_NUM." >&2
      exit 2
      ;;
  esac
fi

if [ -z "$AGENT_PROJECT_OWNER" ] || [ -z "$AGENT_PROJECT_NUMBER" ] || [ "$AGENT_PROJECT_NUMBER" = "TBD" ]; then
  echo "SAFE_TO_PROCEED (Project not configured — no active-claim check possible)"
  exit 0
fi

item_id="$(gh project item-add "$AGENT_PROJECT_NUMBER" --owner "$AGENT_PROJECT_OWNER" --url "$ISSUE_URL" --format json --jq '.id')"
if [ -z "$item_id" ] || [ "$item_id" = "null" ]; then
  echo "SAFE_TO_PROCEED (could not resolve a Project item for $ISSUE_URL)"
  exit 0
fi

fields_tsv="$(gh api graphql -f query='
  query($id: ID!) {
    node(id: $id) {
      ... on ProjectV2Item {
        fieldValues(first: 50) {
          nodes {
            ... on ProjectV2ItemFieldTextValue { text field { ... on ProjectV2FieldCommon { name } } }
            ... on ProjectV2ItemFieldSingleSelectValue { name field { ... on ProjectV2FieldCommon { name } } }
          }
        }
      }
    }
  }' -f id="$item_id" --jq '
    .data.node.fieldValues.nodes[]
    | select(.field.name != null)
    | [ .field.name, (if has("text") then .text elif has("name") then .name else "" end) ]
    | @tsv')"

# fields_tsv holds "<field name>\t<value>" per line, so lookups are plain awk — no external jq,
# and still exactly one API call however many fields get read.
field_value() {
  printf '%s\n' "$fields_tsv" | awk -F'\t' -v n="$1" '$1 == n { print $2; exit }'
}

status="$(field_value "Status")"
other_agent="$(field_value "Agent")"
last_update="$(field_value "Last Agent Update")"

case "$status" in
  "In Progress"|"In Review"|Blocked) ;;
  *)
    echo "SAFE_TO_PROCEED (Status=$status)"
    exit 0
    ;;
esac

ts="$(echo "$last_update" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z' || true)"
if [ -z "$ts" ]; then
  echo "SAFE_TO_PROCEED (Status=$status, but Last Agent Update has no parseable timestamp — treating as stale)"
  exit 0
fi

now_epoch="$(date -u +%s)"
ts_epoch="$(date -u -d "$ts" +%s 2>/dev/null || true)"
if [ -z "$ts_epoch" ]; then
  echo "SAFE_TO_PROCEED (Status=$status, could not parse timestamp '$ts')"
  exit 0
fi

age_minutes=$(( (now_epoch - ts_epoch) / 60 ))

if [ "$age_minutes" -lt "$AGENT_CLAIM_STALENESS_MINUTES" ] && [ -n "$other_agent" ] && [ "$other_agent" != "$AGENT_NAME" ]; then
  echo "ACTIVE_ELSEWHERE: $other_agent updated this $age_minutes minute(s) ago (Status=$status). Do not duplicate work — report this to the user instead of resuming." >&2
  exit 3
fi

echo "SAFE_TO_PROCEED (last update: ${other_agent:-unknown}, $age_minutes minute(s) ago, Status=$status)"
# A stale claim this check just waved through stays on the board until someone overwrites it —
# and nothing else ever rewrites Agent after creation time. Without re-claiming, the NEXT agent's
# run of this very check compares against the wrong name.
if [ -n "$other_agent" ] && [ "$other_agent" != "$AGENT_NAME" ]; then
  echo "note: the board still says Agent=$other_agent. Claim the card before continuing:" >&2
  echo "      scripts/project/sync_project_fields.sh metadata $ISSUE_URL \"Agent=$AGENT_NAME\"" >&2
fi
exit 0
