#!/usr/bin/env bash
# Install github-kit templates into a target repository.
#
# Safe by default:
#   - never overwrites AGENTS.md/CLAUDE.md/GEMINI.md content outside the managed block
#   - never overwrites docs/ai/PROJECT_CONFIG.md or an existing PR/issue template
#   - everything else is created only if missing, unless --mode force is passed
set -euo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATES="$KIT_ROOT/templates"

DEFAULT_WORKFLOW_REF="main"

TARGET="."
MODE="merge"
ALLOW_DIRTY=0
INCLUDE_PROJECT_SYNC=0
WORKFLOW_REF=""
KIT_TIER=""

usage() {
  cat <<'EOF'
Usage: install-github-kit.sh [--target <path>] [--mode merge|force] [--allow-dirty]
                              [--include-project-sync] [--ref <ref>]

  --target <path>          Target repository root (default: current directory)
  --mode merge              Copy missing files, never overwrite existing ones (default)
  --mode force              Also refresh github-kit-owned boilerplate that's already installed
                             (caller workflows, Cursor rules, skills, CODEOWNERS,
                             REVIEW.md block, project helper scripts,
                             docs/ai/AGENT_WORKFLOW.md, docs/ai/HANDOFF_INDEX.md,
                             docs/ai/PROJECT_CONFIG.env.example).
  --allow-dirty             Proceed even if the target repo has uncommitted changes
                             (default: refuse and ask you to commit/stash first).
  --include-project-sync    Also install .github/workflows/project-sync.yml. Off by default —
                             Project Sync needs a real GitHub Project number and an
                             AGENT_PROJECT_TOKEN secret, so most repos should add it later.
  --ref <ref>               Git ref used in caller workflows' uses: lines when referencing
                             pzoli6/github-kit reusable workflows. Default: main, the
                             always-latest channel — most repos should leave this alone and let
                             workflows auto-track pzoli6/github-kit@main. Pass a tag/sha here only
                             to deliberately pin a repo to a fixed version (record that choice as
                             `github-kit update mode: pinned` in docs/ai/PROJECT_CONFIG.md).
  --workflow-ref <ref>      Backward-compatible alias for --ref.
  --tier 1|2                Actions-budget tier for the refreshed caller workflows (CI, verify).
                             1 = run automatically on production-bound changes (the default);
                             2 = run only when dispatched by hand. Omitted = keep each caller's
                             current tier ("# github-kit tier: N" line), or 1 for a new file.
                             The fan-out passes the tier from .github/fanout-targets.json.

  Regardless of mode, this script NEVER overwrites:
    - docs/ai/PROJECT_CONFIG.md (repo-specific, edit it yourself)
    - docs/ai/design-handoffs/DESIGN_SYNC.md (repo sync state: last-synced commit, round counter,
      reading list, decision log), if it already exists
    - .github/workflows/pr-policy.yml (repo-specific required_base_branch gate), if it already exists
    - .github/ISSUE_TEMPLATE/agent_task.yml or .github/PULL_REQUEST_TEMPLATE.md, if they already
      exist (they may already contain repo-specific customization)
    - .github/workflows/project-setup.yml / project-sync.yml, if they already exist
    - .claude/settings.json (repo-specific Claude Code permissions), if it already exists
    - AGENTS.md / CLAUDE.md / GEMINI.md / REVIEW.md content outside the managed block markers
  The full per-file list is templates/docs/ai/KIT_MANIFEST.tsv.
EOF
  echo "  (current default ref: $DEFAULT_WORKFLOW_REF)"
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --target)
      [ "$#" -ge 2 ] || usage
      TARGET="$2"
      shift 2
      ;;
    --mode)
      [ "$#" -ge 2 ] || usage
      MODE="$2"
      shift 2
      ;;
    --allow-dirty)
      ALLOW_DIRTY=1
      shift
      ;;
    --include-project-sync)
      INCLUDE_PROJECT_SYNC=1
      shift
      ;;
    --tier)
      [ "$#" -ge 2 ] || usage
      case "$2" in 1|2) KIT_TIER="$2" ;; *) echo "error: --tier must be 1 or 2" >&2; usage ;; esac
      shift 2
      ;;
    --ref|--workflow-ref)
      [ "$#" -ge 2 ] || usage
      WORKFLOW_REF="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "error: unknown argument '$1'" >&2
      usage
      ;;
  esac
done

case "$MODE" in
  merge|force) ;;
  *) echo "error: --mode must be 'merge' or 'force'" >&2; exit 1 ;;
esac

WORKFLOW_REF="${WORKFLOW_REF:-$DEFAULT_WORKFLOW_REF}"

[ -d "$TARGET" ] || { echo "error: target directory '$TARGET' does not exist." >&2; exit 1; }
TARGET="$(cd "$TARGET" && pwd)"

if git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if [ -n "$(git -C "$TARGET" status --porcelain 2>/dev/null)" ]; then
    if [ "$ALLOW_DIRTY" -ne 1 ]; then
      echo "error: target repository has uncommitted changes." >&2
      echo "Commit or stash your work first, then re-run — or pass --allow-dirty if you understand" >&2
      echo "the risk (the installer only creates/updates github-kit-owned files, but review the diff" >&2
      echo "afterwards either way)." >&2
      exit 1
    else
      echo "warning: target repository has uncommitted changes (--allow-dirty passed, continuing)."
    fi
  fi
fi

echo "github-kit source: $KIT_ROOT"
echo "Target repository:  $TARGET"
echo "Mode:                $MODE"
echo "Workflow ref:        $WORKFLOW_REF$([ "$WORKFLOW_REF" = "main" ] && echo " (always-latest channel)" || echo " (pinned)")"
echo "Project Sync:        $([ "$INCLUDE_PROJECT_SYNC" -eq 1 ] && echo "included" || echo "not included (default)")"
echo

cd "$TARGET"

# --- files (every row of templates/docs/ai/KIT_MANIFEST.tsv) ---------------

# shellcheck source-path=SCRIPTDIR source=lib/kit.sh
. "$KIT_ROOT/scripts/lib/kit.sh"
KIT_OP=install
KIT_FORCE=$([ "$MODE" = "force" ] && echo true || echo false)
FORCE_CONFIG=false
kit_sync_manifest
kit_warn_stray_skills
kit_ensure_gitignore

# --- summary --------------------------------------------------------------

echo
echo "Summary: $CREATED_COUNT created, $UPDATED_COUNT updated, $SKIPPED_COUNT skipped."

# --- verify -------------------------------------------------------------

echo
echo "Running verifier..."
if bash "scripts/project/verify_agent_workflow.sh"; then
  echo
  echo "github-kit install complete and verified."
else
  echo
  echo "github-kit installed, but verification reported issues — see output above."
  echo "This is expected if you still need to fill in docs/ai/PROJECT_CONFIG.md."
fi

echo
echo "Next steps:"
echo "  1. Fill in docs/ai/PROJECT_CONFIG.md with this repo's Project name/number, base branch,"
echo "     validation commands, and forbidden files."
echo "  2. Optional: run scripts/project/create_standard_labels.sh to create the standard"
echo "     status:/type:/risk: labels (gh auth login with repo scope required)."
echo "  3. Project Sync (.github/workflows/project-sync.yml) was $([ "$INCLUDE_PROJECT_SYNC" -eq 1 ] && echo "installed" || echo "NOT installed (default)")."
echo "     It needs a real GitHub Project number and an AGENT_PROJECT_TOKEN secret before use —"
echo "     re-run with --include-project-sync once those exist."
echo "  4. Private repos on the GitHub Free plan can't enforce branch protection rulesets — rely on"
echo "     PR review discipline and required status checks instead (see README.md)."
echo "  5. If you're picking this up after an AI usage-limit pause, see"
echo "     docs/ai/AGENT_WORKFLOW.md for the resume procedure."
echo "  6. Reusable workflow callers now auto-track pzoli6/github-kit@main — no version bump needed"
echo "     to pick up central workflow changes. Local bootstrap files (AGENTS.md, skills, Cursor"
echo "     rules, this script's own templates) only refresh when you run /github_kit_update or"
echo "     update-github-kit.sh again — see README.md → \"Always-latest main channel\"."
