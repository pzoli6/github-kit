#!/usr/bin/env bash
# After a human merges a PR, delete the corresponding local agent branch — but only when it's
# safe: the branch isn't checked out anywhere, its PR is actually MERGED (not just closed), and
# the local branch has no commits beyond what was merged (no unpushed/forgotten work). Anything
# that fails a check is left alone and reported, never force-deleted by guesswork. Local branches
# only — this never touches the remote branch.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: cleanup_merged_branches.sh [--branch <name>] [--dry-run]

Without --branch, scans every local branch matching this repo's agent branch prefix (from
docs/ai/PROJECT_CONFIG.md, default "agent/") and deletes each one whose PR is merged and has no
local-only commits. With --branch, checks only that one branch.

--dry-run   report what would be deleted without deleting anything

Exit code is always 0 (informational tool) unless the arguments themselves are invalid.
EOF
  exit 1
}

TARGET_BRANCH=""
DRY_RUN=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --branch) TARGET_BRANCH="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) usage ;;
  esac
done

for bin in gh git jq; do
  command -v "$bin" >/dev/null 2>&1 || { echo "error: '$bin' is required but not found on PATH." >&2; exit 1; }
done

gh auth status >/dev/null 2>&1 || { echo "error: gh is not authenticated. Run 'gh auth login'." >&2; exit 1; }

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

PREFIX="agent/"
if [ -f "docs/ai/PROJECT_CONFIG.md" ]; then
  configured="$(grep -F 'Agent branch prefix' docs/ai/PROJECT_CONFIG.md | head -1 | sed -E 's/.*`([^`]+)`.*/\1/')"
  [ -n "$configured" ] && PREFIX="$configured"
fi

CURRENT_BRANCH="$(git branch --show-current)"

if [ -n "$TARGET_BRANCH" ]; then
  CANDIDATES="$TARGET_BRANCH"
else
  CANDIDATES="$(git for-each-ref --format='%(refname:short)' "refs/heads/${PREFIX}*" 2>/dev/null || true)"
fi

if [ -z "$CANDIDATES" ]; then
  echo "No candidate branches found (prefix: ${PREFIX})."
  exit 0
fi

# Worktree map: branch name -> worktree path, for branches checked out elsewhere.
WORKTREE_LIST="$(git worktree list --porcelain 2>/dev/null || true)"

deleted=0
skipped=0

while IFS= read -r branch; do
  [ -n "$branch" ] || continue

  if ! git show-ref --verify --quiet "refs/heads/$branch"; then
    echo "SKIPPED $branch: no such local branch"
    skipped=$((skipped + 1))
    continue
  fi

  if [ "$branch" = "$CURRENT_BRANCH" ]; then
    echo "SKIPPED $branch: currently checked out here"
    skipped=$((skipped + 1))
    continue
  fi

  worktree_path="$(echo "$WORKTREE_LIST" | awk -v b="refs/heads/$branch" '
    /^worktree /{wt=$2} /^branch /{if ($2==b) print wt}')"
  if [ -n "$worktree_path" ]; then
    echo "SKIPPED $branch: checked out in another worktree ($worktree_path)"
    skipped=$((skipped + 1))
    continue
  fi

  pr_json="$(gh pr list --head "$branch" --state all --json number,url,state,mergedAt,headRefOid --limit 1 2>/dev/null || echo '[]')"
  pr_count="$(echo "$pr_json" | jq 'length')"
  if [ "$pr_count" -eq 0 ]; then
    echo "SKIPPED $branch: no PR found for this branch"
    skipped=$((skipped + 1))
    continue
  fi

  pr_state="$(echo "$pr_json" | jq -r '.[0].state')"
  pr_number="$(echo "$pr_json" | jq -r '.[0].number')"
  pr_url="$(echo "$pr_json" | jq -r '.[0].url')"
  pr_head_sha="$(echo "$pr_json" | jq -r '.[0].headRefOid')"

  if [ "$pr_state" != "MERGED" ]; then
    echo "SKIPPED $branch: PR #$pr_number ($pr_url) is $pr_state, not merged"
    skipped=$((skipped + 1))
    continue
  fi

  local_sha="$(git rev-parse "refs/heads/$branch")"
  if [ "$local_sha" != "$pr_head_sha" ]; then
    echo "SKIPPED $branch: local branch has commits beyond what PR #$pr_number merged (local $local_sha != merged head $pr_head_sha) — review manually"
    skipped=$((skipped + 1))
    continue
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "WOULD DELETE $branch (PR #$pr_number merged, $pr_url)"
    deleted=$((deleted + 1))
    continue
  fi

  if git branch -d "$branch" >/dev/null 2>&1; then
    echo "DELETED $branch (PR #$pr_number merged, $pr_url)"
  elif git branch -D "$branch" >/dev/null 2>&1; then
    # -d refuses on squash/rebase merges since the commit isn't a real ancestor of any local
    # branch; safe to force here because pr_state=MERGED and local_sha==pr_head_sha were already
    # verified above independently of git's own merge-detection.
    echo "DELETED $branch (PR #$pr_number merged via squash/rebase, $pr_url)"
  else
    echo "SKIPPED $branch: git branch delete failed unexpectedly — review manually"
    skipped=$((skipped + 1))
    continue
  fi
  deleted=$((deleted + 1))
done <<< "$CANDIDATES"

echo
echo "Summary: $deleted deleted/would-delete, $skipped skipped."
exit 0
