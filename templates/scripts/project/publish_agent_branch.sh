#!/usr/bin/env bash
# Create an agent branch in its OWN git worktree, freshly branched from origin/<base>, and push it
# to origin immediately — before any implementation code is written. Worktree isolation is the
# default because multiple agents routinely work the same repo in parallel; two agents must never
# share one working tree. Comments on the issue and updates the Project's Status/Branch/Base Branch
# fields, then drops a WORKTREE.md preamble into the new worktree so the agent that picks it up
# doesn't have to reverse-engineer the base branch, dev port, or verify commands.
#
# Prints the absolute worktree path as the final line of stdout — the caller is expected to `cd`
# into it and do all implementation there.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: publish_agent_branch.sh --issue <issue-url-or-number> --slug <short-description> [options]

Options:
  --base <branch>      Base branch to fork from. Defaults to AGENT_DEFAULT_BASE_BRANCH
                        (PROJECT_CONFIG.env), else the repo's default branch.
  --prefix <prefix>    Branch-name prefix. Defaults to "agent/".
  --worktree-dir <dir> Where to create the worktree. Defaults to
                        <repo-parent>/<repo-name>-worktrees/<slug> (override base via
                        AGENT_WORKTREE_BASE in PROJECT_CONFIG.env).
  --no-worktree        Legacy in-place mode: switch the current working tree to the new branch
                        instead of creating a separate worktree. Only for environments that can't
                        use worktrees (e.g. some CI); never the right choice when other agents may
                        touch this repo concurrently.

On success the final stdout line is the worktree path (or, with --no-worktree, the repo root).
EOF
  exit 1
}

ISSUE=""
SLUG=""
BASE=""
PREFIX="agent/"
WORKTREE_DIR=""
USE_WORKTREE=1

while [ "$#" -gt 0 ]; do
  case "$1" in
    --issue) ISSUE="${2:-}"; shift 2 ;;
    --slug) SLUG="${2:-}"; shift 2 ;;
    --base) BASE="${2:-}"; shift 2 ;;
    --prefix) PREFIX="${2:-}"; shift 2 ;;
    --worktree-dir) WORKTREE_DIR="${2:-}"; shift 2 ;;
    --no-worktree) USE_WORKTREE=0; shift ;;
    *) usage ;;
  esac
done

[ -n "$ISSUE" ] && [ -n "$SLUG" ] || usage

for bin in gh git; do
  command -v "$bin" >/dev/null 2>&1 || { echo "error: '$bin' is required but not found on PATH." >&2; exit 1; }
done

gh auth status >/dev/null 2>&1 || { echo "error: gh is not authenticated. Run 'gh auth login'." >&2; exit 1; }

# Anchor to the MAIN working tree even when this script is invoked from inside a linked worktree,
# so worktrees are always created as siblings of the real repo, never nested under another worktree.
GIT_COMMON_DIR="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
if [ -n "$GIT_COMMON_DIR" ]; then
  MAIN_ROOT="$(dirname "$GIT_COMMON_DIR")"
else
  MAIN_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
REPO_NAME="$(basename "$MAIN_ROOT")"
REPO_PARENT="$(dirname "$MAIN_ROOT")"

# PROJECT_CONFIG.env lives in the main checkout (it's gitignored, so it's not in linked worktrees).
ENV_FILE="$MAIN_ROOT/docs/ai/PROJECT_CONFIG.env"
# shellcheck disable=SC1090
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

: "${AGENT_DEFAULT_BASE_BRANCH:=}"
: "${AGENT_WORKTREE_BASE:=}"
: "${AGENT_DEV_SERVER_CMD:=}"
: "${AGENT_DEV_PORT_BASE:=}"
: "${AGENT_PREVIEW_ROUTE:=}"
: "${AGENT_AUTH_NOTE:=}"
: "${AGENT_KEY_PATHS:=}"
: "${AGENT_VISUAL_QA_NOTE:=}"
: "${AGENT_LAUNCH_TEMPLATE:=}"

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
ISSUE_NUM="$(gh issue view "$ISSUE_URL" --json number --jq '.number')"

BRANCH="${PREFIX}${SLUG}"
NWO="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')"

# Always fork from the freshly-fetched remote base, never a stale local tip.
git -C "$MAIN_ROOT" fetch origin "$BASE"

if git -C "$MAIN_ROOT" show-ref --verify --quiet "refs/heads/$BRANCH"; then
  echo "error: branch '$BRANCH' already exists locally. Pick a different --slug or clean it up first." >&2
  exit 1
fi

# Deterministic per-slug dev port so parallel worktrees don't fight over one port and re-runs are
# stable. Only emitted into WORKTREE.md when the repo configures a base.
DEV_PORT=""
if [ -n "$AGENT_DEV_PORT_BASE" ] && [ "$AGENT_DEV_PORT_BASE" != "TBD" ]; then
  offset="$(printf '%s' "$SLUG" | cksum | cut -d' ' -f1)"
  DEV_PORT="$(( AGENT_DEV_PORT_BASE + (offset % 100) ))"
fi

write_worktree_md() {
  local dest_root="$1"
  local md="$dest_root/WORKTREE.md"
  {
    echo "# WORKTREE.md — agent task preamble"
    echo
    echo "> Generated by \`scripts/project/publish_agent_branch.sh\`. Local scratch, not committed."
    echo "> The facts here are what an agent otherwise burns calls reverse-engineering — read first."
    echo
    echo "| Fact | Value |"
    echo "|---|---|"
    echo "| Issue | #$ISSUE_NUM ($ISSUE_URL) |"
    echo "| Repository | $NWO |"
    echo "| Branch | \`$BRANCH\` |"
    echo "| Base branch | \`$BASE\` (forked from \`origin/$BASE\`) |"
    [ -n "$DEV_PORT" ] && echo "| Dev port | $DEV_PORT (unique to this worktree — do NOT assume 3000) |"
    [ -n "$AGENT_DEV_SERVER_CMD" ] && [ "$AGENT_DEV_SERVER_CMD" != "TBD" ] && echo "| Dev server | \`$AGENT_DEV_SERVER_CMD\` |"
    [ -n "$AGENT_PREVIEW_ROUTE" ] && [ "$AGENT_PREVIEW_ROUTE" != "TBD" ] && echo "| Preview / visual-QA route | $AGENT_PREVIEW_ROUTE |"
    [ -n "$AGENT_KEY_PATHS" ] && [ "$AGENT_KEY_PATHS" != "TBD" ] && echo "| Key paths | $AGENT_KEY_PATHS |"
    echo
    if [ -n "$AGENT_AUTH_NOTE" ] && [ "$AGENT_AUTH_NOTE" != "TBD" ]; then
      echo "**Auth / access:** $AGENT_AUTH_NOTE"
      echo
    fi
    if [ -n "$AGENT_VISUAL_QA_NOTE" ] && [ "$AGENT_VISUAL_QA_NOTE" != "TBD" ]; then
      echo "**Visual QA / browser:** $AGENT_VISUAL_QA_NOTE"
      echo
    fi
    echo "**Verify commands:** see \"Validation commands\" in \`docs/ai/PROJECT_CONFIG.md\` — run them"
    echo "before opening the PR; report \`Validation: Passed\` only if they actually passed."
    echo
    echo "**Workflow:** this is a real git worktree (its own checkout + \`.git\` file). Do all work"
    echo "for issue #$ISSUE_NUM here. When the PR is merged, the worktree and branch are removed and the"
    echo "issue is closed by \`scripts/project/cleanup_merged_branches.sh\` — see \`AGENTS.md\` →"
    echo "\"Branch and worktree rules\"."
  } > "$md"
  # Keep WORKTREE.md (and a copied launch.json) out of git status noise for this worktree only.
  local exclude
  exclude="$(git -C "$dest_root" rev-parse --git-path info/exclude 2>/dev/null || true)"
  if [ -n "$exclude" ] && [ -f "$exclude" ]; then
    grep -qxF "WORKTREE.md" "$exclude" 2>/dev/null || echo "WORKTREE.md" >> "$exclude"
  fi
}

maybe_copy_launch_template() {
  local dest_root="$1"
  [ -n "$AGENT_LAUNCH_TEMPLATE" ] && [ "$AGENT_LAUNCH_TEMPLATE" != "TBD" ] || return 0
  local src="$MAIN_ROOT/$AGENT_LAUNCH_TEMPLATE"
  [ -f "$src" ] || { echo "warning: AGENT_LAUNCH_TEMPLATE '$AGENT_LAUNCH_TEMPLATE' not found — skipping launch.json." >&2; return 0; }
  mkdir -p "$dest_root/.claude"
  # Substitute the per-worktree port placeholder if present.
  sed "s/__AGENT_DEV_PORT__/${DEV_PORT:-}/g" "$src" > "$dest_root/.claude/launch.json"
  local exclude
  exclude="$(git -C "$dest_root" rev-parse --git-path info/exclude 2>/dev/null || true)"
  if [ -n "$exclude" ] && [ -f "$exclude" ]; then
    grep -qxF ".claude/launch.json" "$exclude" 2>/dev/null || echo ".claude/launch.json" >> "$exclude"
  fi
}

if [ "$USE_WORKTREE" -eq 1 ]; then
  if [ -z "$WORKTREE_DIR" ]; then
    if [ -n "$AGENT_WORKTREE_BASE" ] && [ "$AGENT_WORKTREE_BASE" != "TBD" ]; then
      WORKTREE_DIR="$AGENT_WORKTREE_BASE/$SLUG"
    else
      WORKTREE_DIR="$REPO_PARENT/${REPO_NAME}-worktrees/$SLUG"
    fi
  fi

  if [ -e "$WORKTREE_DIR" ]; then
    echo "error: worktree path '$WORKTREE_DIR' already exists. Remove it or pass a different --slug/--worktree-dir." >&2
    exit 1
  fi

  mkdir -p "$(dirname "$WORKTREE_DIR")"
  git -C "$MAIN_ROOT" worktree add -b "$BRANCH" "$WORKTREE_DIR" "origin/$BASE"

  # Confirm git actually registered it — guards against the "banner says worktree, git disagrees"
  # mismatch that wastes an agent's first dozen calls.
  WT_TOPLEVEL="$(git -C "$WORKTREE_DIR" rev-parse --show-toplevel)"
  if ! git -C "$MAIN_ROOT" worktree list --porcelain | grep -qxF "worktree $WT_TOPLEVEL"; then
    echo "error: 'git worktree add' did not register '$WORKTREE_DIR' — aborting before claiming a worktree that isn't real." >&2
    exit 1
  fi

  git -C "$WORKTREE_DIR" push -u origin "$BRANCH"

  write_worktree_md "$WORKTREE_DIR"
  maybe_copy_launch_template "$WORKTREE_DIR"

  PUBLISH_PATH="$WORKTREE_DIR"
  echo "Created worktree for $ISSUE_URL at $WORKTREE_DIR (branch $BRANCH, from origin/$BASE)" >&2
else
  # Legacy in-place mode.
  if [ -n "$(git -C "$MAIN_ROOT" status --porcelain)" ]; then
    echo "error: --no-worktree needs a clean working tree, but it's dirty. Commit, stash, or use a worktree." >&2
    exit 1
  fi
  git -C "$MAIN_ROOT" switch -c "$BRANCH" "origin/$BASE"
  git -C "$MAIN_ROOT" push -u origin "$BRANCH"
  PUBLISH_PATH="$MAIN_ROOT"
  echo "Switched main checkout to $BRANCH (from origin/$BASE) for $ISSUE_URL" >&2
fi

gh issue comment "$ISSUE_URL" --body "Agent branch \`$BRANCH\` pushed: https://github.com/$NWO/tree/$BRANCH" >/dev/null

"$MAIN_ROOT/scripts/project/project_set_status.sh" "$ISSUE_URL" "In Progress" >&2
"$MAIN_ROOT/scripts/project/project_set_text.sh" "$ISSUE_URL" "Branch" "$BRANCH" >&2
"$MAIN_ROOT/scripts/project/project_set_text.sh" "$ISSUE_URL" "Base Branch" "$BASE" >&2

echo "$PUBLISH_PATH"
