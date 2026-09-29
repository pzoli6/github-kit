#!/usr/bin/env bash
# Update a target repository that already has github-kit installed.
#
# Refreshes github-kit-owned boilerplate (agent-workflow-verify/ci-node/ci-python caller workflows,
# Cursor rules, skills, CODEOWNERS, REVIEW.md block, project helper scripts,
# docs/ai/AGENT_WORKFLOW.md, docs/ai/HANDOFF_INDEX.md, docs/ai/PROJECT_CONFIG.env.example) and the
# managed block in AGENTS.md/CLAUDE.md/GEMINI.md. Never overwrites docs/ai/PROJECT_CONFIG.md,
# .github/workflows/pr-policy.yml (it holds the repo-specific required_base_branch gate),
# .github/ISSUE_TEMPLATE/agent_task.yml, or .github/PULL_REQUEST_TEMPLATE.md — those may contain
# repo-specific customization and this script has no flag to force them. Use --force-config to
# additionally overwrite docs/ai/PROJECT_CONFIG.md (rarely what you want — prefer editing it by hand).
set -euo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATES="$KIT_ROOT/templates"

DEFAULT_WORKFLOW_REF="main"

TARGET="."
FORCE_CONFIG="false"
ALLOW_DIRTY=0
INCLUDE_PROJECT_SYNC=0
WORKFLOW_REF=""
KIT_TIER=""

usage() {
  cat <<'EOF'
Usage: update-github-kit.sh [--target <path>] [--force-config] [--allow-dirty]
                             [--include-project-sync] [--ref <ref>]

  --target <path>           Target repository root (default: current directory)
  --force-config            Also overwrite docs/ai/PROJECT_CONFIG.md with the template default.
                             Off by default — this file is repo-specific and normally hand-edited.
  --allow-dirty             Proceed even if the target repo has uncommitted changes
                             (default: refuse and ask you to commit/stash first).
  --include-project-sync    Also create .github/workflows/project-sync.yml if it doesn't exist yet.
                             If it already exists it is preserved as-is (create-only — it carries the
                             repo's project_number), and this flag changes nothing.
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

This always refreshes: the managed block in AGENTS.md/CLAUDE.md/GEMINI.md, the agent-workflow-verify
/ ci-node / ci-python caller workflows, Cursor rules, skills, CODEOWNERS, REVIEW.md block,
project helper scripts, docs/ai/AGENT_WORKFLOW.md, docs/ai/HANDOFF_INDEX.md, and
docs/ai/PROJECT_CONFIG.env.example. This is what /github_kit_update runs under the hood.

This never touches (created only if missing, then preserved): docs/ai/PROJECT_CONFIG.md,
.github/workflows/pr-policy.yml (repo-specific required_base_branch gate), and existing
.github/ISSUE_TEMPLATE/agent_task.yml / .github/PULL_REQUEST_TEMPLATE.md content. It also never
touches docs/ai/PROJECT_CONFIG.env (local, git-ignored).
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
    --force-config)
      FORCE_CONFIG="true"
      shift
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

WORKFLOW_REF="${WORKFLOW_REF:-$DEFAULT_WORKFLOW_REF}"

[ -d "$TARGET" ] || { echo "error: target directory '$TARGET' does not exist." >&2; exit 1; }
TARGET="$(cd "$TARGET" && pwd)"

if git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if [ -n "$(git -C "$TARGET" status --porcelain 2>/dev/null)" ]; then
    if [ "$ALLOW_DIRTY" -ne 1 ]; then
      echo "error: target repository has uncommitted changes." >&2
      echo "Commit or stash your work first, then re-run — or pass --allow-dirty if you understand" >&2
      echo "the risk (the updater only touches github-kit-owned files, but review the diff" >&2
      echo "afterwards either way)." >&2
      exit 1
    else
      echo "warning: target repository has uncommitted changes (--allow-dirty passed, continuing)."
    fi
  fi
fi

echo "github-kit source: $KIT_ROOT"
echo "Target repository:  $TARGET"
echo "force-config:        $FORCE_CONFIG"
echo "Workflow ref:        $WORKFLOW_REF$([ "$WORKFLOW_REF" = "main" ] && echo " (always-latest channel)" || echo " (pinned)")"
echo

cd "$TARGET"

if [ ! -e "AGENTS.md" ] && [ ! -e "CLAUDE.md" ] && [ ! -d "docs/ai" ]; then
  echo "warning: this repository doesn't look like it has github-kit installed yet." >&2
  echo "Run install-github-kit.sh first." >&2
fi

# --- files (every row of templates/docs/ai/KIT_MANIFEST.tsv) ---------------

# shellcheck source-path=SCRIPTDIR source=lib/kit.sh
. "$KIT_ROOT/scripts/lib/kit.sh"
KIT_OP=update
KIT_FORCE=false
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
  echo "github-kit update complete and verified."
else
  echo
  echo "github-kit updated, but verification reported issues — see output above."
fi

echo
echo "Next steps:"
echo "  1. Review the diff before committing — this script only touches github-kit-owned files,"
echo "     but always check (especially after --force-config)."
echo "  2. Optional: run scripts/project/create_standard_labels.sh if you haven't already."
echo "  3. Project Sync (.github/workflows/project-sync.yml) needs a real GitHub Project number"
echo "     and an AGENT_PROJECT_TOKEN secret before use — pass --include-project-sync to add it."
echo "  4. Private repos on the GitHub Free plan can't enforce branch protection rulesets — rely on"
echo "     PR review discipline and required status checks instead (see README.md)."
echo "  5. Reusable workflow callers auto-track pzoli6/github-kit@main on their own — this script (or"
echo "     /github_kit_update) only needs to run again when *local* bootstrap files have drifted."
