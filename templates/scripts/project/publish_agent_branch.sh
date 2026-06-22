#!/usr/bin/env bash
# Create an agent branch from the configured base branch and push it to origin immediately —
# before any implementation code is written — so the branch is never local-only. Comments on the
# issue and updates the Project's Status/Branch fields.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: publish_agent_branch.sh --issue <issue-url-or-number> --slug <short-description> [options]

Options:
  --base <branch>    Defaults to AGENT_DEFAULT_BASE_BRANCH (PROJECT_CONFIG.env), else the repo's
                      default branch
  --prefix <prefix>  Defaults to "agent/"
EOF
  exit 1
}

ISSUE=""
SLUG=""
BASE=""
PREFIX="agent/"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --issue) ISSUE="${2:-}"; shift 2 ;;
    --slug) SLUG="${2:-}"; shift 2 ;;
    --base) BASE="${2:-}"; shift 2 ;;
    --prefix) PREFIX="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done

[ -n "$ISSUE" ] && [ -n "$SLUG" ] || usage

for bin in gh git; do
  command -v "$bin" >/dev/null 2>&1 || { echo "error: '$bin' is required but not found on PATH." >&2; exit 1; }
done

gh auth status >/dev/null 2>&1 || { echo "error: gh is not authenticated. Run 'gh auth login'." >&2; exit 1; }

if [ -n "$(git status --porcelain)" ]; then
  echo "error: working tree is dirty. Commit, stash, or otherwise resolve before publishing a new agent branch." >&2
  exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ENV_FILE="$REPO_ROOT/docs/ai/PROJECT_CONFIG.env"
# shellcheck disable=SC1090
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

: "${AGENT_DEFAULT_BASE_BRANCH:=}"

if [ -z "$BASE" ]; then
  if [ -n "$AGENT_DEFAULT_BASE_BRANCH" ] && [ "$AGENT_DEFAULT_BASE_BRANCH" != "TBD" ]; then
    BASE="$AGENT_DEFAULT_BASE_BRANCH"
  else
    BASE="$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')"
  fi
fi

case "$ISSUE" in
  http*) ISSUE_URL="$ISSUE" ;;
  *) ISSUE_URL="$(gh issue view "$ISSUE" --json url --jq '.url')" ;;
esac
[ -n "$ISSUE_URL" ] && [ "$ISSUE_URL" != "null" ] || { echo "error: could not resolve issue URL for '$ISSUE'." >&2; exit 1; }

BRANCH="${PREFIX}${SLUG}"

git fetch origin "$BASE"
git switch -c "$BRANCH" "origin/$BASE"
git push -u origin "$BRANCH"

echo "Pushed $BRANCH (from origin/$BASE) for $ISSUE_URL" >&2

gh issue comment "$ISSUE_URL" --body "Agent branch \`$BRANCH\` pushed: https://github.com/$(gh repo view --json nameWithOwner --jq '.nameWithOwner')/tree/$BRANCH" >/dev/null

"$REPO_ROOT/scripts/project/project_set_status.sh" "$ISSUE_URL" "In Progress" >&2
"$REPO_ROOT/scripts/project/project_set_text.sh" "$ISSUE_URL" "Branch" "$BRANCH" >&2

echo "$BRANCH"
