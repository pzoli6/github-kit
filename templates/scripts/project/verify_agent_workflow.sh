#!/usr/bin/env bash
# Verify this repo has the files and key phrases the github-kit agent workflow requires.
# Mirrors .github/workflows/reusable-agent-workflow-verify.yml for local/offline use.
set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

REQUIRE_CLAUDE="${REQUIRE_CLAUDE:-true}"
REQUIRE_CURSOR="${REQUIRE_CURSOR:-true}"
REQUIRE_SKILLS="${REQUIRE_SKILLS:-true}"

missing=0

check_file() {
  local f="$1"
  if [ ! -e "$f" ]; then
    echo "MISSING file: $f"
    missing=1
  else
    echo "OK      file: $f"
  fi
}

check_phrase() {
  local phrase="$1"
  if grep -RFq -- "$phrase" \
      --include='*.md' --include='*.yml' --include='*.yaml' \
      --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist --exclude-dir=build \
      . 2>/dev/null; then
    echo "OK      phrase: $phrase"
  else
    echo "MISSING phrase: $phrase"
    missing=1
  fi
}

check_file "AGENTS.md"
check_file "docs/ai/PROJECT_CONFIG.md"
check_file "docs/ai/AGENT_WORKFLOW.md"
check_file "docs/ai/HANDOFF_INDEX.md"
check_file ".github/PULL_REQUEST_TEMPLATE.md"
check_file ".github/ISSUE_TEMPLATE/agent_task.yml"
check_file ".github/copilot-instructions.md"
check_file ".github/CODEOWNERS"
check_file "scripts/project/project_add_item.sh"
check_file "scripts/project/project_set_status.sh"
check_file "scripts/project/project_set_text.sh"
check_file "scripts/project/verify_agent_workflow.sh"

if [ "$REQUIRE_CLAUDE" = "true" ]; then
  check_file "CLAUDE.md"
  check_file ".claude/skills/issue-to-pr-project/SKILL.md"
  check_file ".claude/skills/github_kit/SKILL.md"
  check_file ".claude/commands/github_kit.md"
fi

if [ "$REQUIRE_CURSOR" = "true" ]; then
  check_file ".cursor/rules/agent-workflow.mdc"
  check_file ".cursor/rules/git-safety.mdc"
  check_file ".cursor/rules/project-board.mdc"
  check_file ".cursor/rules/github-kit-command.mdc"
fi

if [ "$REQUIRE_SKILLS" = "true" ]; then
  check_file ".agents/skills/issue-to-pr-project/SKILL.md"
  check_file ".agents/skills/github_kit/SKILL.md"
fi

check_phrase "approve issue-to-pr-project"
check_phrase "/github_kit"
check_phrase "Plan Review"
check_phrase "Ready"
check_phrase "In Progress"
check_phrase "In Review"
check_phrase "Changes Requested"
check_phrase "Validation"
check_phrase "Handoff"
check_phrase "Last Agent Update"

echo
if [ "$missing" -ne 0 ]; then
  echo "Agent workflow verification FAILED — see MISSING items above."
  exit 1
fi

echo "Agent workflow verification passed."
