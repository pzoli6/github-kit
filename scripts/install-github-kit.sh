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

usage() {
  cat <<'EOF'
Usage: install-github-kit.sh [--target <path>] [--mode merge|force] [--allow-dirty]
                              [--include-project-sync] [--ref <ref>]

  --target <path>          Target repository root (default: current directory)
  --mode merge              Copy missing files, never overwrite existing ones (default)
  --mode force              Also refresh github-kit-owned boilerplate that's already installed
                             (caller workflows, Cursor rules, skills, CODEOWNERS,
                             copilot-instructions.md, project helper scripts,
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

  Regardless of mode, this script NEVER overwrites:
    - docs/ai/PROJECT_CONFIG.md (repo-specific, edit it yourself)
    - .github/ISSUE_TEMPLATE/agent_task.yml or .github/PULL_REQUEST_TEMPLATE.md, if they already
      exist (they may already contain repo-specific customization)
    - AGENTS.md / CLAUDE.md / GEMINI.md content outside the managed block markers
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

# --- helpers ---------------------------------------------------------------

CREATED_COUNT=0
UPDATED_COUNT=0
SKIPPED_COUNT=0

copy_if_missing() {
  # Copies $1 -> $2. In merge mode, skips if $2 exists. In force mode, overwrites.
  local src="$1" dst="$2"
  if [ -e "$dst" ]; then
    if [ "$MODE" = "force" ]; then
      mkdir -p "$(dirname "$dst")"
      cp "$src" "$dst"
      echo "updated (force): $dst"
      UPDATED_COUNT=$((UPDATED_COUNT + 1))
    else
      echo "skip (exists):   $dst"
      SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    fi
  else
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    echo "created:         $dst"
    CREATED_COUNT=$((CREATED_COUNT + 1))
  fi
}

copy_create_only() {
  # Copies $1 -> $2 only if $2 doesn't exist. Never overwritten, regardless of mode.
  local src="$1" dst="$2"
  if [ -e "$dst" ]; then
    echo "skip (never overwritten): $dst"
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
  else
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    echo "created:                  $dst"
    CREATED_COUNT=$((CREATED_COUNT + 1))
  fi
}

copy_workflow() {
  # Copies $1 -> $2. Templates pin caller `uses:` lines to @main (the always-latest channel); if
  # --ref/--workflow-ref resolved to something else, repoint only that `uses: pzoli6/github-kit/...`
  # line to the requested ref — never touch unrelated occurrences of the word "main" (e.g. branch
  # triggers). Same merge/force semantics as copy_if_missing.
  local src="$1" dst="$2"
  if [ -e "$dst" ]; then
    if [ "$MODE" = "force" ]; then
      mkdir -p "$(dirname "$dst")"
      sed -E "s#(uses: pzoli6/github-kit/[^@[:space:]]+)@main#\1@$WORKFLOW_REF#" "$src" > "$dst"
      echo "updated (force): $dst"
      UPDATED_COUNT=$((UPDATED_COUNT + 1))
    else
      echo "skip (exists):   $dst"
      SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    fi
  else
    mkdir -p "$(dirname "$dst")"
    sed -E "s#(uses: pzoli6/github-kit/[^@[:space:]]+)@main#\1@$WORKFLOW_REF#" "$src" > "$dst"
    echo "created:         $dst"
    CREATED_COUNT=$((CREATED_COUNT + 1))
  fi
}

write_managed_block() {
  cat <<'GKBLOCK'
<!-- BEGIN GITHUB-KIT UNIVERSAL WORKFLOW -->
## Universal AI-Agent Workflow

This repository follows the universal issue-to-PR workflow from `pzoli6/github-kit`.

Agents must read:
- `AGENTS.md`
- `docs/ai/PROJECT_CONFIG.md`
- `docs/ai/AGENT_WORKFLOW.md`

Every implementation task must follow:
User task → plan → human approval → GitHub issue → Project update → agent branch/worktree → implementation → validation → draft PR → handoff → human review.

Required approval phrase:
```text
approve
```

Fast path: `/github_kit <task>` is a pre-approved alternative entry point — the invocation itself is the approval for the described task, scoped to that task only. See `docs/ai/AGENT_WORKFLOW.md` → "Fast-path trigger: /github_kit".

Agents must not push to protected branches, merge PRs, modify secrets, use `git add .`, or claim validation passed unless validation actually ran.

Before stopping, losing context, or handing off to another agent, agents must update:
- `docs/ai/handoffs/issue-<number>.md`
- Project field: `Last Agent Update`
- Project field: `Validation`
<!-- END GITHUB-KIT UNIVERSAL WORKFLOW -->
GKBLOCK
}

apply_managed_block() {
  # $1 = target file, $2 = full template to copy when target file doesn't exist at all.
  local target_file="$1" full_template="$2"
  local begin='<!-- BEGIN GITHUB-KIT UNIVERSAL WORKFLOW -->'
  local end='<!-- END GITHUB-KIT UNIVERSAL WORKFLOW -->'

  if [ ! -e "$target_file" ]; then
    mkdir -p "$(dirname "$target_file")"
    cp "$full_template" "$target_file"
    echo "created:                $target_file"
    return
  fi

  if grep -qF "$begin" "$target_file"; then
    local block_tmp
    block_tmp="$(mktemp)"
    write_managed_block > "$block_tmp"
    awk -v begin="$begin" -v end="$end" -v blockfile="$block_tmp" '
      BEGIN { while ((getline line < blockfile) > 0) block = block line "\n" }
      $0 == begin { printf "%s", block; skip=1; next }
      $0 == end { skip=0; next }
      skip { next }
      { print }
    ' "$target_file" > "$target_file.gktmp"
    mv "$target_file.gktmp" "$target_file"
    rm -f "$block_tmp"
    echo "updated managed block:  $target_file"
  else
    {
      cat "$target_file"
      echo
      write_managed_block
    } > "$target_file.gktmp"
    mv "$target_file.gktmp" "$target_file"
    echo "appended managed block: $target_file"
  fi
}

# --- AGENTS.md / CLAUDE.md (managed block, never overwrite the rest) -------

apply_managed_block "AGENTS.md" "$TEMPLATES/AGENTS.md"
apply_managed_block "CLAUDE.md" "$TEMPLATES/CLAUDE.md"
apply_managed_block "GEMINI.md" "$TEMPLATES/GEMINI.md"

# --- docs/ai/ ----------------------------------------------------------

copy_create_only "$TEMPLATES/docs/ai/PROJECT_CONFIG.md" "docs/ai/PROJECT_CONFIG.md"
copy_if_missing  "$TEMPLATES/docs/ai/PROJECT_CONFIG.env.example" "docs/ai/PROJECT_CONFIG.env.example"
copy_if_missing  "$TEMPLATES/docs/ai/AGENT_WORKFLOW.md" "docs/ai/AGENT_WORKFLOW.md"
copy_if_missing  "$TEMPLATES/docs/ai/HANDOFF_INDEX.md" "docs/ai/HANDOFF_INDEX.md"
mkdir -p "docs/ai/handoffs"
copy_if_missing  "$TEMPLATES/docs/ai/handoffs/.gitkeep" "docs/ai/handoffs/.gitkeep"

# --- .github/ ------------------------------------------------------------

copy_create_only "$TEMPLATES/.github/ISSUE_TEMPLATE/agent_task.yml" ".github/ISSUE_TEMPLATE/agent_task.yml"
copy_create_only "$TEMPLATES/.github/PULL_REQUEST_TEMPLATE.md" ".github/PULL_REQUEST_TEMPLATE.md"
copy_if_missing  "$TEMPLATES/.github/copilot-instructions.md" ".github/copilot-instructions.md"
copy_if_missing  "$TEMPLATES/.github/CODEOWNERS" ".github/CODEOWNERS"

for wf in agent-workflow-verify pr-policy ci-node ci-python; do
  copy_workflow "$TEMPLATES/.github/workflows/$wf.yml" ".github/workflows/$wf.yml"
done

if [ "$INCLUDE_PROJECT_SYNC" -eq 1 ]; then
  copy_workflow "$TEMPLATES/.github/workflows/project-sync.yml" ".github/workflows/project-sync.yml"
else
  echo "skip (default):  .github/workflows/project-sync.yml (pass --include-project-sync to install it)"
  SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
fi

# --- .agents / .claude / .cursor ------------------------------------------

copy_if_missing "$TEMPLATES/.agents/skills/issue-to-pr-project/SKILL.md" ".agents/skills/issue-to-pr-project/SKILL.md"
copy_if_missing "$TEMPLATES/.claude/skills/issue-to-pr-project/SKILL.md" ".claude/skills/issue-to-pr-project/SKILL.md"
copy_if_missing "$TEMPLATES/.agents/skills/github_kit/SKILL.md" ".agents/skills/github_kit/SKILL.md"
copy_if_missing "$TEMPLATES/.claude/skills/github_kit/SKILL.md" ".claude/skills/github_kit/SKILL.md"
copy_if_missing "$TEMPLATES/.claude/commands/github_kit.md" ".claude/commands/github_kit.md"
copy_if_missing "$TEMPLATES/.agents/skills/github_kit_update/SKILL.md" ".agents/skills/github_kit_update/SKILL.md"
copy_if_missing "$TEMPLATES/.claude/skills/github_kit_update/SKILL.md" ".claude/skills/github_kit_update/SKILL.md"

for rule in agent-workflow git-safety project-board github-kit-command; do
  copy_if_missing "$TEMPLATES/.cursor/rules/$rule.mdc" ".cursor/rules/$rule.mdc"
done

# --- scripts/project/ --------------------------------------------------

for script in project_add_item project_set_status project_set_text verify_agent_workflow create_standard_labels \
              create_agent_issue publish_agent_branch sync_project_fields create_agent_pr \
              check_resume_safety post_handoff_comment cleanup_merged_branches; do
  copy_if_missing "$TEMPLATES/scripts/project/$script.sh" "scripts/project/$script.sh"
  chmod +x "scripts/project/$script.sh" 2>/dev/null || true
done

# --- .gitignore -------------------------------------------------------

GITIGNORE_LINE="docs/ai/PROJECT_CONFIG.env"
if [ -f .gitignore ]; then
  if ! grep -qxF "$GITIGNORE_LINE" .gitignore; then
    printf '\n%s\n' "$GITIGNORE_LINE" >> .gitignore
    echo "updated:         .gitignore (added $GITIGNORE_LINE)"
  else
    echo "skip (exists):   .gitignore already ignores $GITIGNORE_LINE"
  fi
else
  printf '%s\n' "$GITIGNORE_LINE" > .gitignore
  echo "created:         .gitignore"
fi

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
