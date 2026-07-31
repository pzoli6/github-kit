<#
.SYNOPSIS
  Audit github-kit's own repo for packaging regressions (Windows/PowerShell port of
  doctor-github-kit.sh). Not a target-repo check -- see
  templates/scripts/project/verify_agent_workflow.sh for that.

.DESCRIPTION
  Run this before tagging a release. Exits 1 if any required file/phrase is missing or a
  regression (CRLF in .sh files, deprecated Action versions, floating @main refs) is found.
#>
[CmdletBinding()]
param()

$KitRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location -LiteralPath $KitRoot

$script:Missing = 0

function Check-File {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        Write-Host "OK      file: $Path"
    } else {
        Write-Host "MISSING file: $Path"
        $script:Missing = 1
    }
}

function Check-Phrase {
    param([string]$Phrase)
    $found = Get-ChildItem -Recurse -File -Include *.md,*.yml,*.yaml -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\(node_modules|\.git|dist|build)\\' } |
        Select-String -SimpleMatch $Phrase -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($found) {
        Write-Host "OK      phrase: $Phrase"
    } else {
        Write-Host "MISSING phrase: $Phrase"
        $script:Missing = 1
    }
}

# --- required reusable workflows --------------------------------------------

foreach ($wf in @("reusable-agent-workflow-verify", "reusable-ci-node", "reusable-ci-python", "reusable-pr-policy", "reusable-project-sync", "reusable-project-setup", "reusable-design-handoff-approval")) {
    Check-File ".github/workflows/$wf.yml"
}

# --- required installer/updater scripts -------------------------------------

Check-File "scripts/install-github-kit.sh"
Check-File "scripts/install-github-kit.ps1"
Check-File "scripts/update-github-kit.sh"
Check-File "scripts/update-github-kit.ps1"

# --- required templates ------------------------------------------------------

Check-File "templates/AGENTS.md"
Check-File "templates/CLAUDE.md"
Check-File "templates/GEMINI.md"
Check-File "templates/.github/CODEOWNERS"
Check-File "templates/.github/copilot-instructions.md"
Check-File "templates/.github/ISSUE_TEMPLATE/agent_task.yml"
Check-File "templates/.github/PULL_REQUEST_TEMPLATE.md"
Check-File "templates/docs/ai/AGENT_WORKFLOW.md"
Check-File "templates/docs/ai/HANDOFF_INDEX.md"
Check-File "templates/docs/ai/PROJECT_CONFIG.md"
Check-File "templates/docs/ai/PROJECT_CONFIG.env.example"
Check-File "templates/docs/ai/PROJECT_SETUP.md"
Check-File "templates/docs/ai/handoffs/.gitkeep"
Check-File "templates/.agents/skills/issue-to-pr-project/SKILL.md"
Check-File "templates/.claude/skills/issue-to-pr-project/SKILL.md"
Check-File "templates/.agents/skills/github_kit/SKILL.md"
Check-File "templates/.claude/skills/github_kit/SKILL.md"
Check-File "templates/.claude/commands/github_kit.md"
Check-File "templates/.claude/settings.json"
Check-File "templates/.cursor/rules/agent-workflow.mdc"
Check-File "templates/.cursor/rules/git-safety.mdc"
Check-File "templates/.cursor/rules/project-board.mdc"
Check-File "templates/.cursor/rules/github-kit-command.mdc"
Check-File "templates/scripts/project/project_add_item.sh"
Check-File "templates/scripts/project/project_set_status.sh"
Check-File "templates/scripts/project/project_set_text.sh"
Check-File "templates/scripts/project/verify_agent_workflow.sh"
Check-File "templates/scripts/project/create_standard_labels.sh"
Check-File "templates/scripts/project/create_agent_issue.sh"
Check-File "templates/scripts/project/publish_agent_branch.sh"
Check-File "templates/scripts/project/sync_project_fields.sh"
Check-File "templates/scripts/project/create_agent_pr.sh"
Check-File "templates/scripts/project/check_resume_safety.sh"
Check-File "templates/scripts/project/post_handoff_comment.sh"
Check-File "templates/scripts/project/setup_github_project.sh"
Check-File "templates/.github/workflows/project-setup.yml"
Check-File "templates/scripts/project/cleanup_merged_branches.sh"
Check-File "templates/.github/workflows/agent-workflow-verify.yml"
Check-File "templates/.github/workflows/pr-policy.yml"
Check-File "templates/.github/workflows/ci-node.yml"
Check-File "templates/.github/workflows/ci-python.yml"
Check-File "templates/.github/workflows/project-sync.yml"

Write-Host ""

# --- no CRLF in tracked .sh files --------------------------------------------

$shFiles = & git ls-files -- '*.sh'
$crlfFound = $false
foreach ($f in $shFiles) {
    if (-not (Test-Path -LiteralPath $f)) { continue }
    $bytes = [System.IO.File]::ReadAllBytes($f)
    if ($bytes -contains 13) {
        Write-Host "CRLF    file: $f"
        $crlfFound = $true
    }
}
if (-not $crlfFound) {
    Write-Host "OK      no CRLF line endings in tracked .sh files"
} else {
    Write-Host "FAILED  CRLF line endings found in tracked .sh files (see above) -- check .gitattributes"
    $script:Missing = 1
}

Write-Host ""

# --- no deprecated Node-20-only action versions in reusable workflows -------

$reusableFiles = & git ls-files -- '.github/workflows/reusable-*.yml'
$deprecatedFound = $false
$deprecatedPattern = 'actions/(checkout|setup-node)@v[1-4]([^0-9]|$)|actions/setup-python@v[1-5]([^0-9]|$)'
foreach ($f in $reusableFiles) {
    $matches = Select-String -Path $f -Pattern $deprecatedPattern -ErrorAction SilentlyContinue
    if ($matches) {
        $matches | ForEach-Object { Write-Host "DEPRECATED action version in: $($_.Path):$($_.LineNumber): $($_.Line.Trim())" }
        $deprecatedFound = $true
    }
}
if (-not $deprecatedFound) {
    Write-Host "OK      no deprecated Node-20-only action versions in reusable workflows"
} else {
    Write-Host "FAILED  deprecated action versions found (see above) -- bump to a Node 24-compatible release"
    $script:Missing = 1
}

Write-Host ""

# --- template caller workflows use literal @main (always-latest channel) ----

$callerFiles = Get-ChildItem -Path "templates/.github/workflows" -Filter "*.yml" -ErrorAction SilentlyContinue
$mainFiles = $callerFiles | Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match 'pzoli6/github-kit/.*@main' }
if ($mainFiles.Count -ge 4) {
    Write-Host "OK      caller workflow templates use literal @main ($($mainFiles.Count) files)"
} else {
    Write-Host "MISSING literal @main in template caller workflows (found in $($mainFiles.Count) files, need >= 4)"
    $script:Missing = 1
}

$placeholderToken = "@GITHUB_KIT_VERSION"
$placeholderHit = Get-ChildItem -Recurse -File -Include *.md,*.yml,*.yaml,*.sh,*.ps1 -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\(node_modules|\.git|dist|build)\\' } |
    Where-Object { $_.Name -ne 'doctor-github-kit.sh' -and $_.Name -ne 'doctor-github-kit.ps1' } |
    Select-String -SimpleMatch $placeholderToken -ErrorAction SilentlyContinue |
    Select-Object -First 1
if ($placeholderHit) {
    Write-Host "FAILED  stale unsubstituted $placeholderToken placeholder still present (run: Select-String -Path **/* -SimpleMatch $placeholderToken)"
    $script:Missing = 1
} else {
    Write-Host "OK      no stale unsubstituted $placeholderToken placeholder remains"
}

Write-Host ""

# --- project-sync.yml: shipped in templates, but not part of default install -

Check-File "templates/.github/workflows/project-sync.yml"
$installerContent = Get-Content -LiteralPath "scripts/install-github-kit.sh" -Raw -ErrorAction SilentlyContinue
if ($installerContent -match 'INCLUDE_PROJECT_SYNC' -and $installerContent -match 'project-sync') {
    Write-Host "OK      install-github-kit.sh gates project-sync.yml behind --include-project-sync"
} else {
    Write-Host "MISSING --include-project-sync gating in scripts/install-github-kit.sh"
    $script:Missing = 1
}

Write-Host ""

# --- opt-in Project field completeness gate: wired into reusable-pr-policy.yml, the caller -------
# template, and PROJECT_CONFIG.md docs (see "Project field completeness gate (CI)") ---------------

$reusablePrPolicy = Get-Content -LiteralPath ".github/workflows/reusable-pr-policy.yml" -Raw -ErrorAction SilentlyContinue
if ($reusablePrPolicy -match 'check_project_fields' -and $reusablePrPolicy -match 'project-fields:') {
    Write-Host "OK      reusable-pr-policy.yml has the check_project_fields input and project-fields job"
} else {
    Write-Host "MISSING check_project_fields input / project-fields job in .github/workflows/reusable-pr-policy.yml"
    $script:Missing = 1
}

$callerPrPolicy = Get-Content -LiteralPath "templates/.github/workflows/pr-policy.yml" -Raw -ErrorAction SilentlyContinue
if ($callerPrPolicy -match 'check_project_fields') {
    Write-Host "OK      templates/.github/workflows/pr-policy.yml wires up check_project_fields"
} else {
    Write-Host "MISSING check_project_fields wiring in templates/.github/workflows/pr-policy.yml"
    $script:Missing = 1
}

$projectConfigDoc = Get-Content -LiteralPath "templates/docs/ai/PROJECT_CONFIG.md" -Raw -ErrorAction SilentlyContinue
if ($projectConfigDoc -match [regex]::Escape('Project field completeness gate')) {
    Write-Host "OK      templates/docs/ai/PROJECT_CONFIG.md documents the Project field completeness gate"
} else {
    Write-Host "MISSING `"Project field completeness gate`" section in templates/docs/ai/PROJECT_CONFIG.md"
    $script:Missing = 1
}

Write-Host ""

# --- opt-in production-branch approval gate: wired into reusable-pr-policy.yml, the caller -------
# template, and PROJECT_CONFIG.md docs (see "Production-branch approval gate (CI)") ---------------

if ($reusablePrPolicy -match 'require_production_branch_approval' -and $reusablePrPolicy -match 'production_branch_marker') {
    Write-Host "OK      reusable-pr-policy.yml has the require_production_branch_approval input and marker check"
} else {
    Write-Host "MISSING require_production_branch_approval input / marker check in .github/workflows/reusable-pr-policy.yml"
    $script:Missing = 1
}

if ($callerPrPolicy -match 'require_production_branch_approval') {
    Write-Host "OK      templates/.github/workflows/pr-policy.yml wires up require_production_branch_approval"
} else {
    Write-Host "MISSING require_production_branch_approval wiring in templates/.github/workflows/pr-policy.yml"
    $script:Missing = 1
}

if ($projectConfigDoc -match [regex]::Escape('Production-branch approval gate')) {
    Write-Host "OK      templates/docs/ai/PROJECT_CONFIG.md documents the Production-branch approval gate"
} else {
    Write-Host "MISSING `"Production-branch approval gate`" section in templates/docs/ai/PROJECT_CONFIG.md"
    $script:Missing = 1
}

Write-Host ""

# --- checked-in Claude Code permissions: kills routine permission prompts in remote sessions -----
# while hard-denying MCP-based PR merging (humans merge -- see templates/.claude/settings.json) ----

$claudeSettingsOk = $false
try {
    $cs = Get-Content -LiteralPath "templates/.claude/settings.json" -Raw | ConvertFrom-Json
    if ($cs.permissions.deny -contains "mcp__github__merge_pull_request") { $claudeSettingsOk = $true }
} catch {}
if ($claudeSettingsOk) {
    Write-Host "OK      templates/.claude/settings.json is valid JSON and denies MCP PR merging"
} else {
    Write-Host "MISSING templates/.claude/settings.json invalid or no longer denies mcp__github__merge_pull_request"
    $script:Missing = 1
}

$installSh = Get-Content -LiteralPath "scripts/install-github-kit.sh" -Raw -ErrorAction SilentlyContinue
$updateSh = Get-Content -LiteralPath "scripts/update-github-kit.sh" -Raw -ErrorAction SilentlyContinue
if ($installSh -match '\.claude/settings\.json' -and $updateSh -match '\.claude/settings\.json') {
    Write-Host "OK      installers wire up .claude/settings.json (create-only)"
} else {
    Write-Host "MISSING .claude/settings.json wiring in scripts/install-github-kit.sh / update-github-kit.sh"
    $script:Missing = 1
}

Write-Host ""

# --- automatic Project setup: the board is bootstrapped by a workflow + script, and the caller ----
# files that carry a pinned project_number are preserved by the updaters (see PROJECT_SETUP.md) ----

$reusableProjectSetup = Get-Content -LiteralPath ".github/workflows/reusable-project-setup.yml" -Raw -ErrorAction SilentlyContinue
if ($reusableProjectSetup -match 'open_config_pr' -and $reusableProjectSetup -match 'setup_script') {
    Write-Host "OK      reusable-project-setup.yml has the setup_script and open_config_pr inputs"
} else {
    Write-Host "MISSING setup_script / open_config_pr inputs in .github/workflows/reusable-project-setup.yml"
    $script:Missing = 1
}

$callerProjectSetup = Get-Content -LiteralPath "templates/.github/workflows/project-setup.yml" -Raw -ErrorAction SilentlyContinue
if ($callerProjectSetup -match 'AGENT_PROJECT_TOKEN') {
    Write-Host "OK      templates/.github/workflows/project-setup.yml wires up AGENT_PROJECT_TOKEN"
} else {
    Write-Host "MISSING AGENT_PROJECT_TOKEN wiring in templates/.github/workflows/project-setup.yml"
    $script:Missing = 1
}

$setupScript = Get-Content -LiteralPath "templates/scripts/project/setup_github_project.sh" -Raw -ErrorAction SilentlyContinue
if ($setupScript -match 'REQUIRED_TEXT_FIELDS' -and $setupScript -match 'REQUIRED_STATUSES') {
    Write-Host "OK      setup_github_project.sh carries the board contract (REQUIRED_TEXT_FIELDS / REQUIRED_STATUSES)"
} else {
    Write-Host "MISSING REQUIRED_TEXT_FIELDS / REQUIRED_STATUSES contract in templates/scripts/project/setup_github_project.sh"
    $script:Missing = 1
}

$updaterSh = Get-Content -LiteralPath "scripts/update-github-kit.sh" -Raw -ErrorAction SilentlyContinue
$updaterPs = Get-Content -LiteralPath "scripts/update-github-kit.ps1" -Raw -ErrorAction SilentlyContinue
if ($updaterSh -match 'create_only_workflow "\$TEMPLATES/.github/workflows/project-sync.yml"' -and $updaterPs -match 'CreateOnly-Workflow \(Join-Path \$Templates "\.github/workflows/project-sync\.yml"\)') {
    Write-Host "OK      updaters preserve project-sync.yml once created (no more TBD reset on refresh)"
} else {
    Write-Host "MISSING create-only handling for project-sync.yml in scripts/update-github-kit.sh/.ps1 -- refreshing it resets a configured project_number to TBD"
    $script:Missing = 1
}

Write-Host ""

# --- comment-form spec approval: lets a solo repo approve its own spec PR, which GitHub's ---------
# no-self-approval rule otherwise makes impossible (see design-handoffs README, "Approving your ----
# own spec PR") -----------------------------------------------------------------------------------

$reusableDesignApproval = Get-Content -LiteralPath ".github/workflows/reusable-design-handoff-approval.yml" -Raw -ErrorAction SilentlyContinue
if ($reusableDesignApproval -match 'allow_comment_approval' -and $reusableDesignApproval -match 'comment_marker') {
    Write-Host "OK      reusable-design-handoff-approval.yml has the allow_comment_approval input and marker check"
} else {
    Write-Host "MISSING allow_comment_approval input / comment_marker in .github/workflows/reusable-design-handoff-approval.yml"
    $script:Missing = 1
}

$callerDesignApproval = Get-Content -LiteralPath "templates/.github/workflows/design-handoff-approval.yml" -Raw -ErrorAction SilentlyContinue
if ($callerDesignApproval -match 'allow_comment_approval:\s*true' -and $callerDesignApproval -match 'issue_comment') {
    Write-Host "OK      templates/.github/workflows/design-handoff-approval.yml wires up allow_comment_approval + issue_comment"
} else {
    Write-Host "MISSING allow_comment_approval: true / issue_comment trigger in templates/.github/workflows/design-handoff-approval.yml"
    $script:Missing = 1
}

$stampScript = Get-Content -LiteralPath "templates/scripts/design-handoffs/stamp.mjs" -Raw -ErrorAction SilentlyContinue
$verifyScript = Get-Content -LiteralPath "templates/scripts/design-handoffs/verify.mjs" -Raw -ErrorAction SilentlyContinue
if ($stampScript -match 'approval-comment-id' -and $verifyScript -match 'approval-comment-id') {
    Write-Host "OK      stamp.mjs and verify.mjs both handle the comment approval form"
} else {
    Write-Host "MISSING approval-comment-id handling in templates/scripts/design-handoffs/{stamp,verify}.mjs"
    $script:Missing = 1
}

Write-Host ""

# --- require_gemini: wired into reusable-agent-workflow-verify.yml and the caller template --------
# (see "Gemini agent identity support" -- GEMINI.md adapter) ---------------------------------------

$reusableAgentWorkflowVerify = Get-Content -LiteralPath ".github/workflows/reusable-agent-workflow-verify.yml" -Raw -ErrorAction SilentlyContinue
if ($reusableAgentWorkflowVerify -match 'require_gemini') {
    Write-Host "OK      reusable-agent-workflow-verify.yml has the require_gemini input"
} else {
    Write-Host "MISSING require_gemini input in .github/workflows/reusable-agent-workflow-verify.yml"
    $script:Missing = 1
}

$callerAgentWorkflowVerify = Get-Content -LiteralPath "templates/.github/workflows/agent-workflow-verify.yml" -Raw -ErrorAction SilentlyContinue
if ($callerAgentWorkflowVerify -match 'require_gemini:\s*true') {
    Write-Host "OK      templates/.github/workflows/agent-workflow-verify.yml wires up require_gemini: true"
} else {
    Write-Host "MISSING require_gemini: true wiring in templates/.github/workflows/agent-workflow-verify.yml"
    $script:Missing = 1
}

Write-Host ""

# --- require_copilot: the Copilot adapter file must be opt-outable, keeping CI subscription-free --
# (the adapter file is inert text; repos without a Copilot subscription may drop it) ---------------

if ($reusableAgentWorkflowVerify -match 'require_copilot') {
    Write-Host "OK      reusable-agent-workflow-verify.yml has the require_copilot input"
} else {
    Write-Host "MISSING require_copilot input in .github/workflows/reusable-agent-workflow-verify.yml"
    $script:Missing = 1
}

$verifyScript = Get-Content -LiteralPath "templates/scripts/project/verify_agent_workflow.sh" -Raw -ErrorAction SilentlyContinue
if ($verifyScript -match 'REQUIRE_COPILOT') {
    Write-Host "OK      templates/scripts/project/verify_agent_workflow.sh honours REQUIRE_COPILOT"
} else {
    Write-Host "MISSING REQUIRE_COPILOT gating in templates/scripts/project/verify_agent_workflow.sh"
    $script:Missing = 1
}

Write-Host ""

# --- required phrases / Project statuses / handoff terms ---------------------

Check-Phrase "approve"
Check-Phrase "approve main"
Check-Phrase "Production-branch authorization"
Check-Phrase "Stop-and-ask gates"
Check-Phrase "/github_kit"
Check-Phrase "Plan Review"
Check-Phrase "Ready"
Check-Phrase "In Progress"
Check-Phrase "In Review"
Check-Phrase "Changes Requested"
Check-Phrase "Validation"
Check-Phrase "Handoff"
Check-Phrase "Last Agent Update"

Write-Host ""
if ($script:Missing -ne 0) {
    Write-Host "github-kit doctor FAILED -- see MISSING/FAILED items above."
    exit 1
}

Write-Host "github-kit doctor passed."
