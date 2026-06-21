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

foreach ($wf in @("reusable-agent-workflow-verify", "reusable-ci-node", "reusable-ci-python", "reusable-pr-policy", "reusable-project-sync")) {
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
Check-File "templates/.github/CODEOWNERS"
Check-File "templates/.github/copilot-instructions.md"
Check-File "templates/.github/ISSUE_TEMPLATE/agent_task.yml"
Check-File "templates/.github/PULL_REQUEST_TEMPLATE.md"
Check-File "templates/docs/ai/AGENT_WORKFLOW.md"
Check-File "templates/docs/ai/HANDOFF_INDEX.md"
Check-File "templates/docs/ai/PROJECT_CONFIG.md"
Check-File "templates/docs/ai/PROJECT_CONFIG.env.example"
Check-File "templates/docs/ai/handoffs/.gitkeep"
Check-File "templates/.agents/skills/issue-to-pr-project/SKILL.md"
Check-File "templates/.claude/skills/issue-to-pr-project/SKILL.md"
Check-File "templates/.cursor/rules/agent-workflow.mdc"
Check-File "templates/.cursor/rules/git-safety.mdc"
Check-File "templates/.cursor/rules/project-board.mdc"
Check-File "templates/scripts/project/project_add_item.sh"
Check-File "templates/scripts/project/project_set_status.sh"
Check-File "templates/scripts/project/project_set_text.sh"
Check-File "templates/scripts/project/verify_agent_workflow.sh"
Check-File "templates/scripts/project/create_standard_labels.sh"
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

# --- no literal @main in template caller workflows ---------------------------

$callerFiles = & git ls-files -- 'templates/.github/workflows/*.yml'
$mainFound = $false
foreach ($f in $callerFiles) {
    $matches = Select-String -Path $f -Pattern 'pzoli6/github-kit/.*@main' -ErrorAction SilentlyContinue
    if ($matches) {
        $matches | ForEach-Object { Write-Host "FLOATING @main in: $($_.Path):$($_.LineNumber): $($_.Line.Trim())" }
        $mainFound = $true
    }
}
if (-not $mainFound) {
    Write-Host "OK      no floating @main refs in template caller workflows"
} else {
    Write-Host "FAILED  template caller workflows must use @GITHUB_KIT_VERSION, not @main (see above)"
    $script:Missing = 1
}

$placeholderFiles = Get-ChildItem -Path "templates/.github/workflows" -Filter "*.yml" -ErrorAction SilentlyContinue |
    Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match 'GITHUB_KIT_VERSION' }
if ($placeholderFiles.Count -ge 4) {
    Write-Host "OK      caller workflows use the @GITHUB_KIT_VERSION placeholder ($($placeholderFiles.Count) files)"
} else {
    Write-Host "MISSING @GITHUB_KIT_VERSION placeholder in template caller workflows"
    $script:Missing = 1
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

# --- required phrases / Project statuses / handoff terms ---------------------

Check-Phrase "approve issue-to-pr-project"
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
