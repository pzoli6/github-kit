#!/usr/bin/env bash
# Audit github-kit's own repo for packaging regressions (not a target-repo check — see
# templates/scripts/project/verify_agent_workflow.sh for that). Run this before tagging a release.
set -uo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$KIT_ROOT"

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
  if grep -RFq \
      --include='*.md' --include='*.yml' --include='*.yaml' \
      --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist --exclude-dir=build \
      -- "$phrase" . 2>/dev/null; then
    echo "OK      phrase: $phrase"
  else
    echo "MISSING phrase: $phrase"
    missing=1
  fi
}

# --- required reusable workflows --------------------------------------------

for wf in reusable-agent-workflow-verify reusable-ci-node reusable-ci-python reusable-pr-policy reusable-project-sync reusable-project-setup reusable-design-handoff-approval; do
  check_file ".github/workflows/$wf.yml"
done

# --- required installer/updater scripts -------------------------------------

check_file "scripts/install-github-kit.sh"
check_file "scripts/install-github-kit.ps1"
check_file "scripts/update-github-kit.sh"
check_file "scripts/update-github-kit.ps1"

# --- required templates ------------------------------------------------------

check_file "templates/AGENTS.md"
check_file "templates/CLAUDE.md"
check_file "templates/GEMINI.md"
check_file "templates/.github/CODEOWNERS"
check_file "templates/.github/copilot-instructions.md"
check_file "templates/.github/ISSUE_TEMPLATE/agent_task.yml"
check_file "templates/.github/PULL_REQUEST_TEMPLATE.md"
check_file "templates/docs/ai/AGENT_WORKFLOW.md"
check_file "templates/docs/ai/HANDOFF_INDEX.md"
check_file "templates/docs/ai/PROJECT_CONFIG.md"
check_file "templates/docs/ai/PROJECT_CONFIG.env.example"
check_file "templates/docs/ai/PROJECT_SETUP.md"
check_file "templates/docs/ai/handoffs/.gitkeep"
check_file "templates/.agents/skills/issue-to-pr-project/SKILL.md"
check_file "templates/.claude/skills/issue-to-pr-project/SKILL.md"
check_file "templates/.agents/skills/github_kit/SKILL.md"
check_file "templates/.claude/skills/github_kit/SKILL.md"
check_file "templates/.claude/commands/github_kit.md"
check_file "templates/.cursor/rules/agent-workflow.mdc"
check_file "templates/.cursor/rules/git-safety.mdc"
check_file "templates/.cursor/rules/project-board.mdc"
check_file "templates/.cursor/rules/github-kit-command.mdc"
check_file "templates/scripts/project/project_add_item.sh"
check_file "templates/scripts/project/project_set_status.sh"
check_file "templates/scripts/project/project_set_text.sh"
check_file "templates/scripts/project/verify_agent_workflow.sh"
check_file "templates/scripts/project/create_standard_labels.sh"
check_file "templates/scripts/project/create_agent_issue.sh"
check_file "templates/scripts/project/publish_agent_branch.sh"
check_file "templates/scripts/project/sync_project_fields.sh"
check_file "templates/scripts/project/create_agent_pr.sh"
check_file "templates/scripts/project/check_resume_safety.sh"
check_file "templates/scripts/project/post_handoff_comment.sh"
check_file "templates/scripts/project/setup_github_project.sh"
check_file "templates/.github/workflows/project-setup.yml"
check_file "templates/scripts/project/cleanup_merged_branches.sh"
check_file "templates/.github/workflows/agent-workflow-verify.yml"
check_file "templates/.github/workflows/pr-policy.yml"
check_file "templates/.github/workflows/ci-node.yml"
check_file "templates/.github/workflows/ci-python.yml"
check_file "templates/.github/workflows/project-sync.yml"

echo

# --- no CRLF in tracked .sh files --------------------------------------------

crlf_found=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  if grep -qU $'\r' "$f" 2>/dev/null; then
    echo "CRLF    file: $f"
    crlf_found=1
  fi
done < <(git ls-files -- '*.sh')

if [ "$crlf_found" -eq 0 ]; then
  echo "OK      no CRLF line endings in tracked .sh files"
else
  echo "FAILED  CRLF line endings found in tracked .sh files (see above) — check .gitattributes"
  missing=1
fi

echo

# --- no deprecated Node-20-only action versions in reusable workflows -------

deprecated_found=0
while IFS= read -r f; do
  if grep -nE 'actions/(checkout|setup-node)@v[1-4]([^0-9]|$)|actions/setup-python@v[1-5]([^0-9]|$)' "$f" 2>/dev/null; then
    echo "DEPRECATED action version in: $f"
    deprecated_found=1
  fi
done < <(git ls-files -- '.github/workflows/reusable-*.yml')

if [ "$deprecated_found" -eq 0 ]; then
  echo "OK      no deprecated Node-20-only action versions in reusable workflows"
else
  echo "FAILED  deprecated action versions found (see above) — bump to a Node 24-compatible release"
  missing=1
fi

echo

# --- template caller workflows use literal @main (always-latest channel) ----

main_count="$(grep -l 'pzoli6/github-kit/.*@main' templates/.github/workflows/*.yml 2>/dev/null | wc -l)"
if [ "$main_count" -ge 4 ]; then
  echo "OK      caller workflow templates use literal @main ($main_count files)"
else
  echo "MISSING literal @main in template caller workflows (found in $main_count files, need >= 4)"
  missing=1
fi

placeholder="@GITHUB_KIT_VERSION"
if grep -RFq \
    --include='*.md' --include='*.yml' --include='*.yaml' --include='*.sh' --include='*.ps1' \
    --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist --exclude-dir=build \
    --exclude='doctor-github-kit.sh' --exclude='doctor-github-kit.ps1' \
    -- "$placeholder" . 2>/dev/null; then
  echo "FAILED  stale unsubstituted $placeholder placeholder still present (run: grep -RF $placeholder .)"
  missing=1
else
  echo "OK      no stale unsubstituted $placeholder placeholder remains"
fi

echo

# --- project-sync.yml: shipped in templates, but not part of default install -

check_file "templates/.github/workflows/project-sync.yml"
if grep -q 'INCLUDE_PROJECT_SYNC' scripts/install-github-kit.sh 2>/dev/null \
    && grep -q 'project-sync' scripts/install-github-kit.sh 2>/dev/null; then
  echo "OK      install-github-kit.sh gates project-sync.yml behind --include-project-sync"
else
  echo "MISSING --include-project-sync gating in scripts/install-github-kit.sh"
  missing=1
fi

echo

# --- opt-in Project field completeness gate: wired into reusable-pr-policy.yml, the caller -------
# template, and PROJECT_CONFIG.md docs (see "Project field completeness gate (CI)") ---------------

if grep -q 'check_project_fields' .github/workflows/reusable-pr-policy.yml 2>/dev/null \
    && grep -q 'project-fields:' .github/workflows/reusable-pr-policy.yml 2>/dev/null; then
  echo "OK      reusable-pr-policy.yml has the check_project_fields input and project-fields job"
else
  echo "MISSING check_project_fields input / project-fields job in .github/workflows/reusable-pr-policy.yml"
  missing=1
fi

if grep -q 'check_project_fields' templates/.github/workflows/pr-policy.yml 2>/dev/null; then
  echo "OK      templates/.github/workflows/pr-policy.yml wires up check_project_fields"
else
  echo "MISSING check_project_fields wiring in templates/.github/workflows/pr-policy.yml"
  missing=1
fi

if grep -Fq 'Project field completeness gate' templates/docs/ai/PROJECT_CONFIG.md 2>/dev/null; then
  echo "OK      templates/docs/ai/PROJECT_CONFIG.md documents the Project field completeness gate"
else
  echo "MISSING \"Project field completeness gate\" section in templates/docs/ai/PROJECT_CONFIG.md"
  missing=1
fi

echo

# --- opt-in production-branch approval gate: wired into reusable-pr-policy.yml, the caller -------
# template, and PROJECT_CONFIG.md docs (see "Production-branch approval gate (CI)") ---------------

if grep -q 'require_production_branch_approval' .github/workflows/reusable-pr-policy.yml 2>/dev/null \
    && grep -q 'production_branch_marker' .github/workflows/reusable-pr-policy.yml 2>/dev/null; then
  echo "OK      reusable-pr-policy.yml has the require_production_branch_approval input and marker check"
else
  echo "MISSING require_production_branch_approval input / marker check in .github/workflows/reusable-pr-policy.yml"
  missing=1
fi

if grep -q 'require_production_branch_approval' templates/.github/workflows/pr-policy.yml 2>/dev/null; then
  echo "OK      templates/.github/workflows/pr-policy.yml wires up require_production_branch_approval"
else
  echo "MISSING require_production_branch_approval wiring in templates/.github/workflows/pr-policy.yml"
  missing=1
fi

if grep -Fq 'Production-branch approval gate' templates/docs/ai/PROJECT_CONFIG.md 2>/dev/null; then
  echo "OK      templates/docs/ai/PROJECT_CONFIG.md documents the Production-branch approval gate"
else
  echo "MISSING \"Production-branch approval gate\" section in templates/docs/ai/PROJECT_CONFIG.md"
  missing=1
fi

echo

# --- automatic Project setup: the board is bootstrapped by a workflow + script, and the caller ----
# files that carry a pinned project_number are preserved by the updaters (see PROJECT_SETUP.md) ----

if grep -q 'open_config_pr' .github/workflows/reusable-project-setup.yml 2>/dev/null \
    && grep -q 'setup_script' .github/workflows/reusable-project-setup.yml 2>/dev/null; then
  echo "OK      reusable-project-setup.yml has the setup_script and open_config_pr inputs"
else
  echo "MISSING setup_script / open_config_pr inputs in .github/workflows/reusable-project-setup.yml"
  missing=1
fi

if grep -q 'AGENT_PROJECT_TOKEN' templates/.github/workflows/project-setup.yml 2>/dev/null; then
  echo "OK      templates/.github/workflows/project-setup.yml wires up AGENT_PROJECT_TOKEN"
else
  echo "MISSING AGENT_PROJECT_TOKEN wiring in templates/.github/workflows/project-setup.yml"
  missing=1
fi

if grep -q 'REQUIRED_TEXT_FIELDS' templates/scripts/project/setup_github_project.sh 2>/dev/null \
    && grep -q 'REQUIRED_STATUSES' templates/scripts/project/setup_github_project.sh 2>/dev/null; then
  echo "OK      setup_github_project.sh carries the board contract (REQUIRED_TEXT_FIELDS / REQUIRED_STATUSES)"
else
  echo "MISSING REQUIRED_TEXT_FIELDS / REQUIRED_STATUSES contract in templates/scripts/project/setup_github_project.sh"
  missing=1
fi

if grep -q 'create_only_workflow "$TEMPLATES/.github/workflows/project-sync.yml"' scripts/update-github-kit.sh 2>/dev/null \
    && grep -q 'CreateOnly-Workflow (Join-Path $Templates ".github/workflows/project-sync.yml")' scripts/update-github-kit.ps1 2>/dev/null; then
  echo "OK      updaters preserve project-sync.yml once created (no more TBD reset on refresh)"
else
  echo "MISSING create-only handling for project-sync.yml in scripts/update-github-kit.sh/.ps1 — refreshing it resets a configured project_number to TBD"
  missing=1
fi

echo

# --- comment-form spec approval: lets a solo repo approve its own spec PR, which GitHub's ---------
# no-self-approval rule otherwise makes impossible (see design-handoffs README, "Approving your ----
# own spec PR") -----------------------------------------------------------------------------------

if grep -q 'allow_comment_approval' .github/workflows/reusable-design-handoff-approval.yml 2>/dev/null \
    && grep -q 'comment_marker' .github/workflows/reusable-design-handoff-approval.yml 2>/dev/null; then
  echo "OK      reusable-design-handoff-approval.yml has the allow_comment_approval input and marker check"
else
  echo "MISSING allow_comment_approval input / comment_marker in .github/workflows/reusable-design-handoff-approval.yml"
  missing=1
fi

if grep -q 'allow_comment_approval: true' templates/.github/workflows/design-handoff-approval.yml 2>/dev/null \
    && grep -q 'issue_comment' templates/.github/workflows/design-handoff-approval.yml 2>/dev/null; then
  echo "OK      templates/.github/workflows/design-handoff-approval.yml wires up allow_comment_approval + issue_comment"
else
  echo "MISSING allow_comment_approval: true / issue_comment trigger in templates/.github/workflows/design-handoff-approval.yml"
  missing=1
fi

if grep -q 'approval-comment-id' templates/scripts/design-handoffs/stamp.mjs 2>/dev/null \
    && grep -q 'approval-comment-id' templates/scripts/design-handoffs/verify.mjs 2>/dev/null; then
  echo "OK      stamp.mjs and verify.mjs both handle the comment approval form"
else
  echo "MISSING approval-comment-id handling in templates/scripts/design-handoffs/{stamp,verify}.mjs"
  missing=1
fi

echo

# --- require_gemini: wired into reusable-agent-workflow-verify.yml and the caller template --------
# (see "Gemini agent identity support" — GEMINI.md adapter) ----------------------------------------

if grep -q 'require_gemini' .github/workflows/reusable-agent-workflow-verify.yml 2>/dev/null; then
  echo "OK      reusable-agent-workflow-verify.yml has the require_gemini input"
else
  echo "MISSING require_gemini input in .github/workflows/reusable-agent-workflow-verify.yml"
  missing=1
fi

if grep -q 'require_gemini: true' templates/.github/workflows/agent-workflow-verify.yml 2>/dev/null; then
  echo "OK      templates/.github/workflows/agent-workflow-verify.yml wires up require_gemini: true"
else
  echo "MISSING require_gemini: true wiring in templates/.github/workflows/agent-workflow-verify.yml"
  missing=1
fi

echo

# --- require_copilot: the Copilot adapter file must be opt-outable, keeping CI subscription-free --
# (the adapter file is inert text; repos without a Copilot subscription may drop it) --------------

if grep -q 'require_copilot' .github/workflows/reusable-agent-workflow-verify.yml 2>/dev/null; then
  echo "OK      reusable-agent-workflow-verify.yml has the require_copilot input"
else
  echo "MISSING require_copilot input in .github/workflows/reusable-agent-workflow-verify.yml"
  missing=1
fi

if grep -q 'REQUIRE_COPILOT' templates/scripts/project/verify_agent_workflow.sh 2>/dev/null; then
  echo "OK      templates/scripts/project/verify_agent_workflow.sh honours REQUIRE_COPILOT"
else
  echo "MISSING REQUIRE_COPILOT gating in templates/scripts/project/verify_agent_workflow.sh"
  missing=1
fi

echo

# --- required phrases / Project statuses / handoff terms ---------------------

check_phrase "approve"
check_phrase "approve main"
check_phrase "Production-branch authorization"
check_phrase "Stop-and-ask gates"
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
  echo "github-kit doctor FAILED — see MISSING/FAILED items above."
  exit 1
fi

echo "github-kit doctor passed."
