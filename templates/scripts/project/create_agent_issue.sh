#!/usr/bin/env bash
# Create a GitHub issue with full sidebar metadata (assignee/labels/milestone), add it to the
# configured Project, and set Status to Ready — so issue metadata is never left blank.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: create_agent_issue.sh --title <title> --body-file <path> [options]

Options:
  --assignee <user>     Defaults to AGENT_DEFAULT_ISSUE_ASSIGNEE (PROJECT_CONFIG.env)
  --labels <a,b,c>      Comma-separated. Defaults to AGENT_DEFAULT_ISSUE_LABELS
  --milestone <title>   Defaults to AGENT_DEFAULT_MILESTONE
  --no-project          Skip adding the issue to the configured GitHub Project
EOF
  exit 1
}

TITLE=""
BODY_FILE=""
ASSIGNEE=""
LABELS=""
MILESTONE=""
SKIP_PROJECT=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --title) TITLE="${2:-}"; shift 2 ;;
    --body-file) BODY_FILE="${2:-}"; shift 2 ;;
    --assignee) ASSIGNEE="${2:-}"; shift 2 ;;
    --labels) LABELS="${2:-}"; shift 2 ;;
    --milestone) MILESTONE="${2:-}"; shift 2 ;;
    --no-project) SKIP_PROJECT=1; shift ;;
    *) usage ;;
  esac
done

[ -n "$TITLE" ] && [ -n "$BODY_FILE" ] || usage
[ -f "$BODY_FILE" ] || { echo "error: body file '$BODY_FILE' not found." >&2; exit 1; }

for bin in gh; do
  command -v "$bin" >/dev/null 2>&1 || { echo "error: '$bin' is required but not found on PATH." >&2; exit 1; }
done

gh auth status >/dev/null 2>&1 || {
  echo "error: gh is not authenticated. Run 'gh auth login' (and 'gh auth refresh -s project' if Project updates also fail)." >&2
  exit 1
}

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ENV_FILE="$REPO_ROOT/docs/ai/PROJECT_CONFIG.env"
# shellcheck disable=SC1090
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

: "${AGENT_PROJECT_OWNER:=}"
: "${AGENT_PROJECT_NUMBER:=}"
: "${AGENT_DEFAULT_ISSUE_ASSIGNEE:=}"
: "${AGENT_DEFAULT_ISSUE_LABELS:=}"
: "${AGENT_DEFAULT_MILESTONE:=}"

[ -n "$ASSIGNEE" ] || ASSIGNEE="$AGENT_DEFAULT_ISSUE_ASSIGNEE"
[ -n "$LABELS" ] || LABELS="$AGENT_DEFAULT_ISSUE_LABELS"
[ -n "$MILESTONE" ] || MILESTONE="$AGENT_DEFAULT_MILESTONE"

# Best-effort: make sure the standard labels exist before applying any of them. Non-fatal — a
# repo without label-write permission still gets a clear error from `gh issue create` below if a
# requested label genuinely doesn't exist.
[ -x "$REPO_ROOT/scripts/project/create_standard_labels.sh" ] && \
  "$REPO_ROOT/scripts/project/create_standard_labels.sh" >/dev/null 2>&1 || true

create_args=(issue create --title "$TITLE" --body-file "$BODY_FILE")

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

issue_url="$(gh "${create_args[@]}")"
echo "Created issue: $issue_url" >&2

if [ "$SKIP_PROJECT" -ne 1 ]; then
  if [ -n "$AGENT_PROJECT_OWNER" ] && [ -n "$AGENT_PROJECT_NUMBER" ] && [ "$AGENT_PROJECT_NUMBER" != "TBD" ]; then
    "$REPO_ROOT/scripts/project/project_add_item.sh" "$issue_url" >/dev/null
    "$REPO_ROOT/scripts/project/project_set_status.sh" "$issue_url" Ready >&2
  else
    echo "warning: AGENT_PROJECT_OWNER/AGENT_PROJECT_NUMBER not configured — issue was not added to a Project. Add it manually if one exists." >&2
  fi
fi

echo "$issue_url"
