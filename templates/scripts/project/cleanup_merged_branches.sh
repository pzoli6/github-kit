#!/usr/bin/env bash
# After a human merges a PR, clean up after the agent: remove the task's git worktree, delete the
# local branch, and close the linked issue (Project Status -> Done, plus `gh issue close`). Every
# destructive step is gated on a safety check and anything that fails one is left alone and
# reported, never forced by guesswork:
#   - the PR for the branch is actually MERGED (not just closed),
#   - the local branch tip matches exactly what GitHub merged (no forgotten local commits),
#   - the worktree has no uncommitted/untracked work beyond the kit's own scratch files.
# Local artifacts only — the remote branch is never touched (GitHub may auto-delete it on merge).
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: cleanup_merged_branches.sh [--branch <name>] [--dry-run]

Without --branch, scans every local branch matching this repo's agent branch prefixes (the
comma-separated "Agent branch prefix" list in docs/ai/PROJECT_CONFIG.md, default
"agent/,claude/,codex/") and cleans up each one whose PR is merged. With
--branch, processes only that one branch.

For each merged branch it: removes the branch's worktree (if any), deletes the local branch, and
closes the issue(s) the PR declared it closes (Closes/Fixes/Resolves #N).

--dry-run   report what would happen without changing anything

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

# The worktree this script was launched from — never remove it out from under the caller.
INVOCATION_WT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Anchor to the MAIN working tree even when invoked from a linked worktree, so ref/worktree ops and
# the helper-script paths resolve against the primary checkout.
GIT_COMMON_DIR="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
if [ -n "$GIT_COMMON_DIR" ]; then
  MAIN_ROOT="$(dirname "$GIT_COMMON_DIR")"
else
  MAIN_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
cd "$MAIN_ROOT"

# "Agent branch prefix" may be a single prefix or a comma-separated allowlist
# (e.g. `agent/,claude/,codex/`) — sweep every listed prefix.
PREFIXES="agent/,claude/,codex/"
if [ -f "docs/ai/PROJECT_CONFIG.md" ]; then
  configured="$(grep -F 'Agent branch prefix' docs/ai/PROJECT_CONFIG.md | head -1 | sed -E 's/.*`([^`]+)`.*/\1/')"
  [ -n "$configured" ] && PREFIXES="$configured"
fi

if [ -n "$TARGET_BRANCH" ]; then
  CANDIDATES="$TARGET_BRANCH"
else
  CANDIDATES=""
  IFS=',' read -r -a prefix_list <<< "$PREFIXES"
  for raw_prefix in "${prefix_list[@]}"; do
    prefix="$(echo "$raw_prefix" | sed 's/^ *//;s/ *$//')"
    [ -n "$prefix" ] || continue
    matches="$(git for-each-ref --format='%(refname:short)' "refs/heads/${prefix}*" 2>/dev/null || true)"
    [ -n "$matches" ] && CANDIDATES="${CANDIDATES}${CANDIDATES:+
}${matches}"
  done
fi

if [ -z "$CANDIDATES" ]; then
  echo "No candidate branches found (prefixes: ${PREFIXES})."
  exit 0
fi

WORKTREE_LIST="$(git worktree list --porcelain 2>/dev/null || true)"

# A worktree is removable if its only uncommitted content is the kit's own generated scratch
# (WORKTREE.md, .claude/launch.json). Anything else — tracked modifications or other untracked
# files — means real work could be lost, so we refuse and report.
worktree_is_clean_modulo_scratch() {
  local wt="$1"
  local raw
  raw="$(git -C "$wt" status --porcelain 2>/dev/null || echo '__ERR__')"
  [ "$raw" != "__ERR__" ] || return 1
  local unexpected
  unexpected="$(printf '%s\n' "$raw" \
    | grep -vE '^\?\? (WORKTREE\.md|\.claude/launch\.json|\.claude/)$' \
    | sed '/^$/d' || true)"
  [ -z "$unexpected" ]
}

close_linked_issues() {
  local prnum="$1" action="$2"  # action: "report" or "do"
  local urls
  urls="$(gh pr view "$prnum" --json closingIssuesReferences -q '.closingIssuesReferences[].url' 2>/dev/null || true)"
  [ -n "$urls" ] || return 0
  while IFS= read -r issue_url; do
    [ -n "$issue_url" ] || continue
    if [ "$action" = "report" ]; then
      echo "  would close issue $issue_url (Status -> Done)"
    else
      "$MAIN_ROOT/scripts/project/sync_project_fields.sh" done "$issue_url" >/dev/null 2>&1 \
        || echo "  warning: could not set Project Status Done for $issue_url" >&2
      if gh issue close "$issue_url" >/dev/null 2>&1; then
        echo "  CLOSED issue $issue_url"
      else
        echo "  warning: could not close issue $issue_url (already closed?)" >&2
      fi
    fi
  done <<< "$urls"
}

cleaned=0
skipped=0

while IFS= read -r branch; do
  [ -n "$branch" ] || continue

  if ! git show-ref --verify --quiet "refs/heads/$branch"; then
    echo "SKIPPED $branch: no such local branch"
    skipped=$((skipped + 1))
    continue
  fi

  worktree_path="$(echo "$WORKTREE_LIST" | awk -v b="refs/heads/$branch" '
    /^worktree /{wt=$2} /^branch /{if ($2==b) print wt}')"

  if [ -n "$worktree_path" ] && [ "$worktree_path" = "$INVOCATION_WT" ]; then
    echo "SKIPPED $branch: currently checked out here ($worktree_path)"
    skipped=$((skipped + 1))
    continue
  fi
  if [ -n "$worktree_path" ] && [ "$worktree_path" = "$MAIN_ROOT" ]; then
    echo "SKIPPED $branch: checked out in the main working tree (won't remove the primary checkout)"
    skipped=$((skipped + 1))
    continue
  fi

  pr_json="$(gh pr list --head "$branch" --state all --json number,url,state,mergedAt,headRefOid --limit 1 2>/dev/null || echo '[]')"
  if [ "$(echo "$pr_json" | jq 'length')" -eq 0 ]; then
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

  if [ -n "$worktree_path" ] && ! worktree_is_clean_modulo_scratch "$worktree_path"; then
    echo "SKIPPED $branch: worktree $worktree_path has uncommitted or untracked changes — review manually"
    skipped=$((skipped + 1))
    continue
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "WOULD CLEAN $branch (PR #$pr_number merged, $pr_url)"
    [ -n "$worktree_path" ] && echo "  would remove worktree $worktree_path"
    close_linked_issues "$pr_number" report
    cleaned=$((cleaned + 1))
    continue
  fi

  # Remove the worktree first — git won't delete a branch that's checked out in one. Force is safe
  # here: worktree_is_clean_modulo_scratch above already proved nothing but kit scratch is present.
  if [ -n "$worktree_path" ]; then
    if git worktree remove --force "$worktree_path" >/dev/null 2>&1; then
      echo "REMOVED worktree $worktree_path"
    else
      echo "SKIPPED $branch: 'git worktree remove' failed for $worktree_path — review manually"
      skipped=$((skipped + 1))
      continue
    fi
  fi

  if git branch -d "$branch" >/dev/null 2>&1; then
    echo "DELETED branch $branch (PR #$pr_number merged, $pr_url)"
  elif git branch -D "$branch" >/dev/null 2>&1; then
    # -d refuses on squash/rebase merges since the commit isn't a real ancestor of any local
    # branch; safe to force here because pr_state=MERGED and local_sha==pr_head_sha were already
    # verified above independently of git's own merge-detection.
    echo "DELETED branch $branch (PR #$pr_number merged via squash/rebase, $pr_url)"
  else
    echo "SKIPPED $branch: git branch delete failed unexpectedly — review manually"
    skipped=$((skipped + 1))
    continue
  fi

  close_linked_issues "$pr_number" do
  cleaned=$((cleaned + 1))
done <<< "$CANDIDATES"

echo
echo "Summary: $cleaned cleaned/would-clean, $skipped skipped."
exit 0
