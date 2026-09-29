<#
.SYNOPSIS
  Install github-kit templates into a target repository (Windows/PowerShell port of
  install-github-kit.sh).

.DESCRIPTION
  Safe by default:
    - never overwrites AGENTS.md/CLAUDE.md/GEMINI.md content outside the managed block
    - never overwrites docs/ai/PROJECT_CONFIG.md, docs/ai/design-handoffs/DESIGN_SYNC.md (repo
      sync state), or an existing PR/issue template
    - everything else is created only if missing, unless -Mode force is passed

.PARAMETER Target
  Target repository root. Default: current directory.

.PARAMETER Mode
  'merge' (default) copies missing files and never overwrites existing ones.
  'force' also refreshes github-kit-owned boilerplate that's already installed (caller
  workflows, Cursor rules, skills, CODEOWNERS, REVIEW.md block, project helper
  scripts, docs/ai/AGENT_WORKFLOW.md, docs/ai/HANDOFF_INDEX.md, docs/ai/PROJECT_CONFIG.env.example).

.PARAMETER AllowDirty
  Proceed even if the target repo has uncommitted changes (default: refuse and ask you to
  commit/stash first).

.PARAMETER IncludeProjectSync
  Also install .github/workflows/project-sync.yml. Off by default -- Project Sync needs a
  real GitHub Project number and an AGENT_PROJECT_TOKEN secret, so most repos should add it later.

.PARAMETER Ref
  Git ref used in caller workflows' uses: lines when referencing pzoli6/github-kit reusable
  workflows. Default: main, the always-latest channel -- most repos should leave this alone and
  let workflows auto-track pzoli6/github-kit@main. Pass a tag/sha here only to deliberately pin a
  repo to a fixed version (record that choice as `github-kit update mode: pinned` in
  docs/ai/PROJECT_CONFIG.md).

.PARAMETER WorkflowRef
  Backward-compatible alias for -Ref.

.EXAMPLE
  .\install-github-kit.ps1 -Target C:\repos\my-app -Mode merge

.EXAMPLE
  .\install-github-kit.ps1 -Target C:\repos\my-app -IncludeProjectSync -Ref v0.2.0
.PARAMETER Tier
    Actions-budget tier for the refreshed caller workflows (CI, verify): 1 runs them
    automatically on production-bound changes (default); 2 runs them only when dispatched by
    hand. Omitted = keep each caller's current tier ("# github-kit tier: N" line), or 1 for a new
    file. The fan-out passes the tier from .github/fanout-targets.json.

#>
[CmdletBinding()]
param(
    [string]$Target = ".",
    [ValidateSet("merge", "force")]
    [string]$Mode = "merge",
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
the risk (the installer only creates/updates github-kit-owned files, but review the diff
afterwards either way).
"@
        } else {
            Write-Warning "target repository has uncommitted changes (-AllowDirty passed, continuing)."
        }
    }
}

Write-Host "github-kit source: $KitRoot"
Write-Host "Target repository:  $Target"
Write-Host "Mode:                $Mode"
$refLabel = if ($WorkflowRef -eq "main") { "(always-latest channel)" } else { "(pinned)" }
Write-Host "Workflow ref:        $WorkflowRef $refLabel"
$projectSyncStatus = if ($IncludeProjectSync) { "included" } else { "not included (default)" }
Write-Host "Project Sync:        $projectSyncStatus"
Write-Host ""

Set-Location -LiteralPath $Target

# --- files (every row of templates/docs/ai/KIT_MANIFEST.tsv) ---------------

. (Join-Path $KitRoot "scripts/lib/Kit.ps1")
$KitOp = "install"
$KitForce = ($Mode -eq "force")
$KitForceConfig = $false
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
        Write-Host "github-kit install complete and verified."
    } else {
        Write-Host ""
        Write-Host "github-kit installed, but verification reported issues -- see output above."
        Write-Host "This is expected if you still need to fill in docs/ai/PROJECT_CONFIG.md."
    }
} else {
    Write-Host ""
    Write-Warning "bash not found on PATH -- skipping verification."
    Write-Host "Install Git for Windows (provides Git Bash) or WSL, then run:"
    Write-Host "  bash scripts/project/verify_agent_workflow.sh"
    Write-Host "manually to verify the install."
}

Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Fill in docs/ai/PROJECT_CONFIG.md with this repo's Project name/number, base branch,"
Write-Host "     validation commands, and forbidden files."
Write-Host "  2. Optional: run scripts/project/create_standard_labels.sh (via Git Bash/WSL) to create"
Write-Host "     the standard status:/type:/risk: labels (gh auth login with repo scope required)."
$projectSyncStep = if ($IncludeProjectSync) { "installed" } else { "NOT installed (default)" }
Write-Host "  3. Project Sync (.github/workflows/project-sync.yml) was $projectSyncStep."
Write-Host "     It needs a real GitHub Project number and an AGENT_PROJECT_TOKEN secret before use --"
Write-Host "     re-run with -IncludeProjectSync once those exist."
Write-Host "  4. Private repos on the GitHub Free plan can't enforce branch protection rulesets -- rely on"
Write-Host "     PR review discipline and required status checks instead (see README.md)."
Write-Host "  5. If you're picking this up after an AI usage-limit pause, see"
Write-Host "     docs/ai/AGENT_WORKFLOW.md for the resume procedure."
Write-Host "  6. Reusable workflow callers now auto-track pzoli6/github-kit@main -- no version bump"
Write-Host "     needed to pick up central workflow changes. Local bootstrap files only refresh when"
Write-Host "     you run /github_kit_update or update-github-kit.ps1 again -- see README.md."
