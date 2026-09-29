<#
.SYNOPSIS
  Update a target repository that already has github-kit installed (Windows/PowerShell port of
  update-github-kit.sh).

.DESCRIPTION
  Refreshes github-kit-owned boilerplate (caller workflows, Cursor rules, skills, CODEOWNERS,
  copilot-instructions.md, project helper scripts, docs/ai/AGENT_WORKFLOW.md,
  docs/ai/HANDOFF_INDEX.md, docs/ai/PROJECT_CONFIG.env.example) and the managed block in
  AGENTS.md/CLAUDE.md/GEMINI.md. Never overwrites docs/ai/PROJECT_CONFIG.md, .github/ISSUE_TEMPLATE/
  agent_task.yml, or .github/PULL_REQUEST_TEMPLATE.md -- those may contain repo-specific
  customization and this script has no flag to force them, except -ForceConfig for
  docs/ai/PROJECT_CONFIG.md specifically (rarely what you want -- prefer editing it by hand).

.PARAMETER Target
  Target repository root. Default: current directory.

.PARAMETER ForceConfig
  Also overwrite docs/ai/PROJECT_CONFIG.md with the template default. Off by default -- this
  file is repo-specific and normally hand-edited.

.PARAMETER AllowDirty
  Proceed even if the target repo has uncommitted changes (default: refuse and ask you to
  commit/stash first).

.PARAMETER IncludeProjectSync
  Also create .github/workflows/project-sync.yml if it doesn't exist yet. If it already
  exists it is preserved as-is (create-only — it carries the repo's project_number), and
  this switch changes nothing.

.PARAMETER Ref
  Git ref used in caller workflows' uses: lines when referencing pzoli6/github-kit reusable
  workflows. Default: main, the always-latest channel -- most repos should leave this alone and
  let workflows auto-track pzoli6/github-kit@main. Pass a tag/sha here only to deliberately pin a
  repo to a fixed version (record that choice as `github-kit update mode: pinned` in
  docs/ai/PROJECT_CONFIG.md).

.PARAMETER WorkflowRef
  Backward-compatible alias for -Ref.

.EXAMPLE
  .\update-github-kit.ps1 -Target C:\repos\my-app

.EXAMPLE
  .\update-github-kit.ps1 -Target C:\repos\my-app -Ref v0.3.0 -IncludeProjectSync
.PARAMETER Tier
    Actions-budget tier for the refreshed caller workflows (CI, verify): 1 runs them
    automatically on production-bound changes (default); 2 runs them only when dispatched by
    hand. Omitted = keep each caller's current tier ("# github-kit tier: N" line), or 1 for a new
    file. The fan-out passes the tier from .github/fanout-targets.json.

#>
[CmdletBinding()]
param(
    [string]$Target = ".",
    [switch]$ForceConfig,
    [switch]$AllowDirty,
    [switch]$IncludeProjectSync,
    [string]$Ref,
    [string]$WorkflowRef,
    [ValidateSet("", "1", "2")]
    [string]$Tier = ""
)

$ErrorActionPreference = "Stop"

$DefaultWorkflowRef = "main"
if (-not $WorkflowRef) { $WorkflowRef = $Ref }
if (-not $WorkflowRef) { $WorkflowRef = $DefaultWorkflowRef }

$KitRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Templates = Join-Path $KitRoot "templates"

if (-not (Test-Path -LiteralPath $Target -PathType Container)) {
    Write-Error "target directory '$Target' does not exist."
}
$Target = (Resolve-Path -LiteralPath $Target).Path

# --- dirty check ------------------------------------------------------------

$gitInsideWorkTree = $false
try {
    & git -C $Target rev-parse --is-inside-work-tree 1>$null 2>$null
    if ($LASTEXITCODE -eq 0) { $gitInsideWorkTree = $true }
} catch { }

if ($gitInsideWorkTree) {
    $statusOutput = & git -C $Target status --porcelain 2>$null
    if ($statusOutput) {
        if (-not $AllowDirty) {
            Write-Error @"
target repository has uncommitted changes.
Commit or stash your work first, then re-run -- or pass -AllowDirty if you understand
the risk (the updater only touches github-kit-owned files, but review the diff
afterwards either way).
"@
        } else {
            Write-Warning "target repository has uncommitted changes (-AllowDirty passed, continuing)."
        }
    }
}

Write-Host "github-kit source: $KitRoot"
Write-Host "Target repository:  $Target"
Write-Host "force-config:        $($ForceConfig.IsPresent)"
$refLabel = if ($WorkflowRef -eq "main") { "(always-latest channel)" } else { "(pinned)" }
Write-Host "Workflow ref:        $WorkflowRef $refLabel"
Write-Host ""

Set-Location -LiteralPath $Target

if (-not (Test-Path -LiteralPath "AGENTS.md") -and -not (Test-Path -LiteralPath "CLAUDE.md") -and -not (Test-Path -LiteralPath "docs/ai" -PathType Container)) {
    Write-Warning "this repository doesn't look like it has github-kit installed yet."
    Write-Warning "Run install-github-kit.ps1 first."
}

# --- files (every row of templates/docs/ai/KIT_MANIFEST.tsv) ---------------

. (Join-Path $KitRoot "scripts/lib/Kit.ps1")
$KitOp = "update"
$KitForce = $false
$KitForceConfig = [bool]$ForceConfig
$KitIncludeSync = [bool]$IncludeProjectSync
$KitTier = $Tier
Sync-KitManifest
Write-KitStraySkillWarning
Set-KitGitignore

# --- summary --------------------------------------------------------------

Write-Host ""
Write-Host "Summary: $CreatedCount created, $UpdatedCount updated, $SkippedCount skipped."

# --- verify -------------------------------------------------------------

Write-Host ""
Write-Host "Running verifier..."
$bashCmd = Get-Command bash -ErrorAction SilentlyContinue
if ($bashCmd) {
    & $bashCmd.Source "scripts/project/verify_agent_workflow.sh"
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "github-kit update complete and verified."
    } else {
        Write-Host ""
        Write-Host "github-kit updated, but verification reported issues -- see output above."
    }
} else {
    Write-Host ""
    Write-Warning "bash not found on PATH -- skipping verification."
    Write-Host "Install Git for Windows (provides Git Bash) or WSL, then run:"
    Write-Host "  bash scripts/project/verify_agent_workflow.sh"
    Write-Host "manually to verify the update."
}

Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Review the diff before committing -- this script only touches github-kit-owned files,"
Write-Host "     but always check (especially after -ForceConfig)."
Write-Host "  2. Optional: run scripts/project/create_standard_labels.sh (via Git Bash/WSL) if you"
Write-Host "     haven't already."
Write-Host "  3. Project Sync (.github/workflows/project-sync.yml) needs a real GitHub Project number"
Write-Host "     and an AGENT_PROJECT_TOKEN secret before use -- pass -IncludeProjectSync to add it."
Write-Host "  4. Private repos on the GitHub Free plan can't enforce branch protection rulesets -- rely on"
Write-Host "     PR review discipline and required status checks instead (see README.md)."
Write-Host "  5. Reusable workflow callers auto-track pzoli6/github-kit@main on their own -- this"
Write-Host "     script (or /github_kit_update) only needs to run again when *local* bootstrap"
Write-Host "     files have drifted."
