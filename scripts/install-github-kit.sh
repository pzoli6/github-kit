#!/usr/bin/env bash
# Install github-kit templates into a target repository.
#
# Safe by default:
#   - never overwrites AGENTS.md/CLAUDE.md content outside the managed block
#   - never overwrites docs/ai/PROJECT_CONFIG.md or an existing PR/issue template
#   - everything else is created only if missing, unless --mode force is passed
set -euo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATES="$KIT_ROOT/templates"

TARGET="."
MODE="merge"

usage() {
  cat <<'EOF'
Usage: install-github-kit.sh [--target <path>] [--mode merge|force]

  --target <path>   Target repository root (default: current directory)
  --mode merge      Copy missing files, never overwrite existing ones (default)
  --mode force      Also refresh github-kit-owned boilerplate that's already installed
                     (caller workflows, Cursor rules, skills, CODEOWNERS,
                     copilot-instructions.md, project helper scripts, docs/ai/AGENT_WORKFLOW.md,
                     docs/ai/HANDOFF_INDEX.md, docs/ai/PROJECT_CONFIG.env.example).

  Regardless of mode, this script NEVER overwrites:
    - docs/ai/PROJECT_CONFIG.md (repo-specific, edit it yourself)
    - .github/ISSUE_TEMPLATE/agent_task.yml or .github/PULL_REQUEST_TEMPLATE.md, if they already
      exist (they may already contain repo-specific customization)
    - AGENTS.md / CLAUDE.md content outside the managed block markers
EOF
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

[ -d "$TARGET" ] || { echo "error: target directory '$TARGET' does not exist." >&2; exit 1; }
TARGET="$(cd "$TARGET" && pwd)"

echo "github-kit source: $KIT_ROOT"
echo "Target repository:  $TARGET"
echo "Mode:                $MODE"
echo

cd "$TARGET"

# --- helpers ---------------------------------------------------------------

copy_if_missing() {
  # Copies $1 -> $2. In merge mode, skips if $2 exists. In force mode, overwrites.
  local src="$1" dst="$2"
  if [ -e "$dst" ]; then
    if [ "$MODE" = "force" ]; then
      mkdir -p "$(dirname "$dst")"
      cp "$src" "$dst"
      echo "updated (force): $dst"
    else
      echo "skip (exists):   $dst"
    fi
  else
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    echo "created:         $dst"
  fi
}

copy_create_only() {
  # Copies $1 -> $2 only if $2 doesn't exist. Never overwritten, regardless of mode.
  local src="$1" dst="$2"
  if [ -e "$dst" ]; then
    echo "skip (never overwritten): $dst"
  else
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    echo "created:                  $dst"
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
approve issue-to-pr-project
```

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

for wf in agent-workflow-verify project-sync pr-policy ci-node ci-python; do
  copy_if_missing "$TEMPLATES/.github/workflows/$wf.yml" ".github/workflows/$wf.yml"
done

# --- .agents / .claude / .cursor ------------------------------------------

copy_if_missing "$TEMPLATES/.agents/skills/issue-to-pr-project/SKILL.md" ".agents/skills/issue-to-pr-project/SKILL.md"
copy_if_missing "$TEMPLATES/.claude/skills/issue-to-pr-project/SKILL.md" ".claude/skills/issue-to-pr-project/SKILL.md"

for rule in agent-workflow git-safety project-board; do
  copy_if_missing "$TEMPLATES/.cursor/rules/$rule.mdc" ".cursor/rules/$rule.mdc"
done

# --- scripts/project/ --------------------------------------------------

for script in project_add_item project_set_status project_set_text verify_agent_workflow; do
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
