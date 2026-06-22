#!/usr/bin/env bash
# Open a draft PR with full sidebar metadata (assignee/labels/milestone/reviewer) and a
# "Closes #<n>" body, add the PR to the configured Project, and update the linked issue's Status
# and PR URL — so PR metadata and Project tracking are never left incomplete.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: create_agent_pr.sh --issue <issue-url-or-number> --base <branch> --head <branch> \
  --title <title> --body-file <path> [options]

Options:
  --assignee <user>     Defaults to AGENT_DEFAULT_PR_ASSIGNEE (PROJECT_CONFIG.env)
  --labels <a,b,c>      Comma-separated. Defaults to AGENT_DEFAULT_PR_LABELS
  --milestone <title>   Defaults to AGENT_DEFAULT_MILESTONE
  --reviewer <a,b,c>    Comma-separated. Defaults to AGENT_DEFAULT_REVIEWER
  --no-project          Skip adding the PR to the configured GitHub Project
EOF
  exit 1
}

ISSUE=""
BASE=""
HEAD=""
TITLE=""
BODY_FILE=""
ASSIGNEE=""
LABELS=""
MILESTONE=""
REVIEWER=""
SKIP_PROJECT=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --issue) ISSUE="${2:-}"; shift 2 ;;
    --base) BASE="${2:-}"; shift 2 ;;
    --head) HEAD="${2:-}"; shift 2 ;;
    --title) TITLE="${2:-}"; shift 2 ;;
    --body-file) BODY_FILE="${2:-}"; shift 2 ;;
    --assignee) ASSIGNEE="${2:-}"; shift 2 ;;
    --labels) LABELS="${2:-}"; shift 2 ;;
    --milestone) MILESTONE="${2:-}"; shift 2 ;;
    --reviewer) REVIEWER="${2:-}"; shift 2 ;;
    --no-project) SKIP_PROJECT=1; shift ;;
    *) usage ;;
  esac
done

[ -n "$ISSUE" ] && [ -n "$BASE" ] && [ -n "$HEAD" ] && [ -n "$TITLE" ] && [ -n "$BODY_FILE" ] || usage
[ -f "$BODY_FILE" ] || { echo "error: body file '$BODY_FILE' not found." >&2; exit 1; }

for bin in gh git; do
  command -v "$bin" >/dev/null 2>&1 || { echo "error: '$bin' is required but not found on PATH." >&2; exit 1; }
done

gh auth status >/dev/null 2>&1 || { echo "error: gh is not authenticated. Run 'gh auth login'." >&2; exit 1; }

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ENV_FILE="$REPO_ROOT/docs/ai/PROJECT_CONFIG.env"
# shellcheck disable=SC1090
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

: "${AGENT_PROJECT_OWNER:=}"
: "${AGENT_PROJECT_NUMBER:=}"
: "${AGENT_DEFAULT_PR_ASSIGNEE:=}"
: "${AGENT_DEFAULT_PR_LABELS:=}"
: "${AGENT_DEFAULT_MILESTONE:=}"
: "${AGENT_DEFAULT_REVIEWER:=}"

[ -n "$ASSIGNEE" ] || ASSIGNEE="$AGENT_DEFAULT_PR_ASSIGNEE"
[ -n "$LABELS" ] || LABELS="$AGENT_DEFAULT_PR_LABELS"
[ -n "$MILESTONE" ] || MILESTONE="$AGENT_DEFAULT_MILESTONE"
[ -n "$REVIEWER" ] || REVIEWER="$AGENT_DEFAULT_REVIEWER"

case "$ISSUE" in
  http*) ISSUE_URL="$ISSUE"; ISSUE_NUM="$(gh issue view "$ISSUE_URL" --json number --jq '.number')" ;;
  *) ISSUE_NUM="$ISSUE"; ISSUE_URL="$(gh issue view "$ISSUE_NUM" --json url --jq '.url')" ;;
esac
[ -n "$ISSUE_URL" ] && [ "$ISSUE_URL" != "null" ] || { echo "error: could not resolve issue for '$ISSUE'." >&2; exit 1; }

FINAL_BODY_FILE="$(mktemp)"
trap 'rm -f "$FINAL_BODY_FILE"' EXIT
cp "$BODY_FILE" "$FINAL_BODY_FILE"
if ! grep -qiE "(closes|fixes|resolves) #${ISSUE_NUM}\b" "$FINAL_BODY_FILE"; then
  printf '\n\nCloses #%s\n' "$ISSUE_NUM" >> "$FINAL_BODY_FILE"
fi

# Best-effort: see create_agent_issue.sh for why this is non-fatal.
[ -x "$REPO_ROOT/scripts/project/create_standard_labels.sh" ] && \
  "$REPO_ROOT/scripts/project/create_standard_labels.sh" >/dev/null 2>&1 || true

create_args=(pr create --draft --base "$BASE" --head "$HEAD" --title "$TITLE" --body-file "$FINAL_BODY_FILE")

if [ -n "$ASSIGNEE" ] && [ "$ASSIGNEE" != "TBD" ]; then
  create_args+=(--assignee "$ASSIGNEE")
fi

if [ -n "$LABELS" ] && [ "$LABELS" != "TBD" ]; then
  IFS=',' read -r -a label_array <<< "$LABELS"
  for l in "${label_array[@]}"; do
    create_args+=(--label "$l")
  done
fi

if [ -n "$MILESTONE" ] && [ "$MILESTONE" != "TBD" ]; then
  if ! gh api "repos/{owner}/{repo}/milestones" --jq '.[].title' 2>/dev/null | grep -qx "$MILESTONE"; then
    echo "error: milestone '$MILESTONE' is configured (Default milestone) but does not exist in this repo's GitHub Issues." >&2
    echo "Create it first, or fix 'Default milestone' in docs/ai/PROJECT_CONFIG.md / AGENT_DEFAULT_MILESTONE in PROJECT_CONFIG.env." >&2
    exit 1
  fi
  create_args+=(--milestone "$MILESTONE")
fi

if [ -n "$REVIEWER" ] && [ "$REVIEWER" != "TBD" ]; then
  IFS=',' read -r -a reviewer_array <<< "$REVIEWER"
  for r in "${reviewer_array[@]}"; do
    create_args+=(--reviewer "$r")
  done
fi

pr_url="$(gh "${create_args[@]}")"
echo "Created draft PR: $pr_url" >&2

gh issue comment "$ISSUE_URL" --body "Draft PR opened: $pr_url" >/dev/null

if [ "$SKIP_PROJECT" -ne 1 ] && [ -n "$AGENT_PROJECT_OWNER" ] && [ -n "$AGENT_PROJECT_NUMBER" ] && [ "$AGENT_PROJECT_NUMBER" != "TBD" ]; then
  "$REPO_ROOT/scripts/project/project_add_item.sh" "$pr_url" >/dev/null
  "$REPO_ROOT/scripts/project/sync_project_fields.sh" pr_opened "$ISSUE_URL" "$pr_url" >&2
else
  echo "warning: Project not configured or --no-project passed — PR was not added to a Project." >&2
fi

echo "$pr_url"
