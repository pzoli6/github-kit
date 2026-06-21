#!/usr/bin/env bash
# Update a target repository that already has github-kit installed.
#
# Refreshes github-kit-owned boilerplate (caller workflows, Cursor rules, skills, CODEOWNERS,
# copilot-instructions.md, project helper scripts, docs/ai/AGENT_WORKFLOW.md,
# docs/ai/HANDOFF_INDEX.md, docs/ai/PROJECT_CONFIG.env.example) and the managed block in
# AGENTS.md/CLAUDE.md. Never overwrites docs/ai/PROJECT_CONFIG.md, .github/ISSUE_TEMPLATE/
# agent_task.yml, or .github/PULL_REQUEST_TEMPLATE.md — those may contain repo-specific
# customization and this script has no flag to force them. Use --force-config to additionally
# overwrite docs/ai/PROJECT_CONFIG.md (rarely what you want — prefer editing it by hand).
set -euo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATES="$KIT_ROOT/templates"

TARGET="."
FORCE_CONFIG="false"

usage() {
  cat <<'EOF'
Usage: update-github-kit.sh [--target <path>] [--force-config]

  --target <path>   Target repository root (default: current directory)
  --force-config    Also overwrite docs/ai/PROJECT_CONFIG.md with the template default.
                     Off by default — this file is repo-specific and normally hand-edited.

This always refreshes: the managed block in AGENTS.md/CLAUDE.md, caller workflows, Cursor
rules, skills, CODEOWNERS, copilot-instructions.md, project helper scripts,
docs/ai/AGENT_WORKFLOW.md, docs/ai/HANDOFF_INDEX.md, and docs/ai/PROJECT_CONFIG.env.example.

This never touches: docs/ai/PROJECT_CONFIG.env (local, git-ignored), or existing
.github/ISSUE_TEMPLATE/agent_task.yml / .github/PULL_REQUEST_TEMPLATE.md content.
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
    --force-config)
      FORCE_CONFIG="true"
      shift
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

[ -d "$TARGET" ] || { echo "error: target directory '$TARGET' does not exist." >&2; exit 1; }
TARGET="$(cd "$TARGET" && pwd)"

echo "github-kit source: $KIT_ROOT"
echo "Target repository:  $TARGET"
echo "force-config:        $FORCE_CONFIG"
echo

cd "$TARGET"

if [ ! -e "AGENTS.md" ] && [ ! -e "CLAUDE.md" ] && [ ! -d "docs/ai" ]; then
  echo "warning: this repository doesn't look like it has github-kit installed yet." >&2
  echo "Run install-github-kit.sh first." >&2
fi

# --- helpers ---------------------------------------------------------------

refresh() {
  # Always overwrite $2 with $1 (creating it if missing).
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [ -e "$dst" ]; then
    cp "$src" "$dst"
    echo "refreshed:       $dst"
  else
    cp "$src" "$dst"
    echo "created:         $dst"
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

# --- AGENTS.md / CLAUDE.md (always refresh the managed block) -------------

apply_managed_block "AGENTS.md" "$TEMPLATES/AGENTS.md"
apply_managed_block "CLAUDE.md" "$TEMPLATES/CLAUDE.md"

# --- docs/ai/ (PROJECT_CONFIG.md protected unless --force-config) ---------

if [ "$FORCE_CONFIG" = "true" ]; then
  refresh "$TEMPLATES/docs/ai/PROJECT_CONFIG.md" "docs/ai/PROJECT_CONFIG.md"
elif [ -e "docs/ai/PROJECT_CONFIG.md" ]; then
  echo "skip (repo-specific, use --force-config to override): docs/ai/PROJECT_CONFIG.md"
else
  refresh "$TEMPLATES/docs/ai/PROJECT_CONFIG.md" "docs/ai/PROJECT_CONFIG.md"
fi

refresh "$TEMPLATES/docs/ai/PROJECT_CONFIG.env.example" "docs/ai/PROJECT_CONFIG.env.example"
refresh "$TEMPLATES/docs/ai/AGENT_WORKFLOW.md" "docs/ai/AGENT_WORKFLOW.md"
refresh "$TEMPLATES/docs/ai/HANDOFF_INDEX.md" "docs/ai/HANDOFF_INDEX.md"
mkdir -p "docs/ai/handoffs"
[ -e "docs/ai/handoffs/.gitkeep" ] || refresh "$TEMPLATES/docs/ai/handoffs/.gitkeep" "docs/ai/handoffs/.gitkeep"

# --- .github/ (issue/PR templates are never auto-overwritten) -------------

if [ -e ".github/ISSUE_TEMPLATE/agent_task.yml" ]; then
  echo "skip (may be customized): .github/ISSUE_TEMPLATE/agent_task.yml"
else
  refresh "$TEMPLATES/.github/ISSUE_TEMPLATE/agent_task.yml" ".github/ISSUE_TEMPLATE/agent_task.yml"
fi

if [ -e ".github/PULL_REQUEST_TEMPLATE.md" ]; then
  echo "skip (may be customized): .github/PULL_REQUEST_TEMPLATE.md"
else
  refresh "$TEMPLATES/.github/PULL_REQUEST_TEMPLATE.md" ".github/PULL_REQUEST_TEMPLATE.md"
fi

refresh "$TEMPLATES/.github/copilot-instructions.md" ".github/copilot-instructions.md"
refresh "$TEMPLATES/.github/CODEOWNERS" ".github/CODEOWNERS"

for wf in agent-workflow-verify project-sync pr-policy ci-node ci-python; do
  refresh "$TEMPLATES/.github/workflows/$wf.yml" ".github/workflows/$wf.yml"
done

# --- .agents / .claude / .cursor ------------------------------------------

refresh "$TEMPLATES/.agents/skills/issue-to-pr-project/SKILL.md" ".agents/skills/issue-to-pr-project/SKILL.md"
refresh "$TEMPLATES/.claude/skills/issue-to-pr-project/SKILL.md" ".claude/skills/issue-to-pr-project/SKILL.md"

for rule in agent-workflow git-safety project-board; do
  refresh "$TEMPLATES/.cursor/rules/$rule.mdc" ".cursor/rules/$rule.mdc"
done

# --- scripts/project/ -------------------------------------------------

for script in project_add_item project_set_status project_set_text verify_agent_workflow; do
  refresh "$TEMPLATES/scripts/project/$script.sh" "scripts/project/$script.sh"
  chmod +x "scripts/project/$script.sh" 2>/dev/null || true
done

# --- .gitignore -------------------------------------------------------

GITIGNORE_LINE="docs/ai/PROJECT_CONFIG.env"
if [ -f .gitignore ]; then
  if ! grep -qxF "$GITIGNORE_LINE" .gitignore; then
    printf '\n%s\n' "$GITIGNORE_LINE" >> .gitignore
    echo "updated:         .gitignore (added $GITIGNORE_LINE)"
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
  echo "github-kit update complete and verified."
else
  echo
  echo "github-kit updated, but verification reported issues — see output above."
fi
