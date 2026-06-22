<#
.SYNOPSIS
  Install github-kit templates into a target repository (Windows/PowerShell port of
  install-github-kit.sh).

.DESCRIPTION
  Safe by default:
    - never overwrites AGENTS.md/CLAUDE.md content outside the managed block
    - never overwrites docs/ai/PROJECT_CONFIG.md or an existing PR/issue template
    - everything else is created only if missing, unless -Mode force is passed

.PARAMETER Target
  Target repository root. Default: current directory.

.PARAMETER Mode
  'merge' (default) copies missing files and never overwrites existing ones.
  'force' also refreshes github-kit-owned boilerplate that's already installed (caller
  workflows, Cursor rules, skills, CODEOWNERS, copilot-instructions.md, project helper
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
#>
[CmdletBinding()]
param(
    [string]$Target = ".",
    [ValidateSet("merge", "force")]
    [string]$Mode = "merge",
    [switch]$AllowDirty,
    [switch]$IncludeProjectSync,
    [string]$Ref,
    [string]$WorkflowRef
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

# --- counters ----------------------------------------------------------

$CreatedCount = 0
$UpdatedCount = 0
$SkippedCount = 0

# --- helpers -------------------------------------------------------------

function Ensure-ParentDir {
    param([string]$Path)
    $dir = Split-Path -Path $Path -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
}

function Copy-IfMissing {
    # Copies $Src -> $Dst. In merge mode, skips if $Dst exists. In force mode, overwrites.
    param([string]$Src, [string]$Dst)
    if (Test-Path -LiteralPath $Dst) {
        if ($Mode -eq "force") {
            Copy-Item -LiteralPath $Src -Destination $Dst -Force
            Write-Host "updated (force): $Dst"
            $script:UpdatedCount++
        } else {
            Write-Host "skip (exists):   $Dst"
            $script:SkippedCount++
        }
    } else {
        Ensure-ParentDir $Dst
        Copy-Item -LiteralPath $Src -Destination $Dst
        Write-Host "created:         $Dst"
        $script:CreatedCount++
    }
}

function Copy-CreateOnly {
    # Copies $Src -> $Dst only if $Dst doesn't exist. Never overwritten, regardless of mode.
    param([string]$Src, [string]$Dst)
    if (Test-Path -LiteralPath $Dst) {
        Write-Host "skip (never overwritten): $Dst"
        $script:SkippedCount++
    } else {
        Ensure-ParentDir $Dst
        Copy-Item -LiteralPath $Src -Destination $Dst
        Write-Host "created:                  $Dst"
        $script:CreatedCount++
    }
}

function Copy-Workflow {
    # Copies $Src -> $Dst. Templates pin caller `uses:` lines to @main (the always-latest
    # channel); if -Ref/-WorkflowRef resolved to something else, repoint only that
    # `uses: pzoli6/github-kit/...` line to the requested ref -- never touch unrelated occurrences
    # of the word "main" (e.g. branch triggers). Same merge/force semantics as Copy-IfMissing.
    param([string]$Src, [string]$Dst)
    $pattern = '(uses: pzoli6/github-kit/[^@\s]+)@main'
    if (Test-Path -LiteralPath $Dst) {
        if ($Mode -eq "force") {
            Ensure-ParentDir $Dst
            (Get-Content -LiteralPath $Src -Raw) -replace $pattern, "`$1@$WorkflowRef" | Set-Content -LiteralPath $Dst -NoNewline
            Write-Host "updated (force): $Dst"
            $script:UpdatedCount++
        } else {
            Write-Host "skip (exists):   $Dst"
            $script:SkippedCount++
        }
    } else {
        Ensure-ParentDir $Dst
        (Get-Content -LiteralPath $Src -Raw) -replace $pattern, "`$1@$WorkflowRef" | Set-Content -LiteralPath $Dst -NoNewline
        Write-Host "created:         $Dst"
        $script:CreatedCount++
    }
}

function Get-ManagedBlockText {
    $block = @'
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

Fast path: `/github_kit <task>` is a pre-approved alternative entry point — the invocation itself is the approval for the described task, scoped to that task only. See `docs/ai/AGENT_WORKFLOW.md` → "Fast-path trigger: /github_kit".

Agents must not push to protected branches, merge PRs, modify secrets, use `git add .`, or claim validation passed unless validation actually ran.

Before stopping, losing context, or handing off to another agent, agents must update:
- `docs/ai/handoffs/issue-<number>.md`
- Project field: `Last Agent Update`
- Project field: `Validation`
<!-- END GITHUB-KIT UNIVERSAL WORKFLOW -->
'@
    return ($block -replace "`r`n", "`n")
}

function Apply-ManagedBlock {
    # $TargetFile = file to update; $FullTemplate = full template to copy when $TargetFile doesn't exist at all.
    param([string]$TargetFile, [string]$FullTemplate)
    $beginMarker = '<!-- BEGIN GITHUB-KIT UNIVERSAL WORKFLOW -->'
    $endMarker = '<!-- END GITHUB-KIT UNIVERSAL WORKFLOW -->'

    if (-not (Test-Path -LiteralPath $TargetFile)) {
        Ensure-ParentDir $TargetFile
        Copy-Item -LiteralPath $FullTemplate -Destination $TargetFile
        Write-Host "created:                $TargetFile"
        $script:CreatedCount++
        return
    }

    $content = Get-Content -LiteralPath $TargetFile -Raw
    $block = Get-ManagedBlockText

    if ($content.Contains($beginMarker)) {
        $pattern = "(?ms)^$([regex]::Escape($beginMarker)).*?^$([regex]::Escape($endMarker))\r?\n?"
        $newContent = [regex]::Replace($content, $pattern, ($block + "`n"))
        Set-Content -LiteralPath $TargetFile -Value $newContent -NoNewline
        Write-Host "updated managed block:  $TargetFile"
        $script:UpdatedCount++
    } else {
        $newContent = $content + "`n" + $block + "`n"
        Set-Content -LiteralPath $TargetFile -Value $newContent -NoNewline
        Write-Host "appended managed block: $TargetFile"
        $script:UpdatedCount++
    }
}

# --- AGENTS.md / CLAUDE.md (managed block, never overwrite the rest) -------

Apply-ManagedBlock "AGENTS.md" (Join-Path $Templates "AGENTS.md")
Apply-ManagedBlock "CLAUDE.md" (Join-Path $Templates "CLAUDE.md")

# --- docs/ai/ ----------------------------------------------------------

Copy-CreateOnly (Join-Path $Templates "docs/ai/PROJECT_CONFIG.md") "docs/ai/PROJECT_CONFIG.md"
Copy-IfMissing  (Join-Path $Templates "docs/ai/PROJECT_CONFIG.env.example") "docs/ai/PROJECT_CONFIG.env.example"
Copy-IfMissing  (Join-Path $Templates "docs/ai/AGENT_WORKFLOW.md") "docs/ai/AGENT_WORKFLOW.md"
Copy-IfMissing  (Join-Path $Templates "docs/ai/HANDOFF_INDEX.md") "docs/ai/HANDOFF_INDEX.md"
New-Item -ItemType Directory -Force -Path "docs/ai/handoffs" | Out-Null
Copy-IfMissing  (Join-Path $Templates "docs/ai/handoffs/.gitkeep") "docs/ai/handoffs/.gitkeep"

# --- .github/ ------------------------------------------------------------

Copy-CreateOnly (Join-Path $Templates ".github/ISSUE_TEMPLATE/agent_task.yml") ".github/ISSUE_TEMPLATE/agent_task.yml"
Copy-CreateOnly (Join-Path $Templates ".github/PULL_REQUEST_TEMPLATE.md") ".github/PULL_REQUEST_TEMPLATE.md"
Copy-IfMissing  (Join-Path $Templates ".github/copilot-instructions.md") ".github/copilot-instructions.md"
Copy-IfMissing  (Join-Path $Templates ".github/CODEOWNERS") ".github/CODEOWNERS"

foreach ($wf in @("agent-workflow-verify", "pr-policy", "ci-node", "ci-python")) {
    Copy-Workflow (Join-Path $Templates ".github/workflows/$wf.yml") ".github/workflows/$wf.yml"
}

if ($IncludeProjectSync) {
    Copy-Workflow (Join-Path $Templates ".github/workflows/project-sync.yml") ".github/workflows/project-sync.yml"
} else {
    Write-Host "skip (default):  .github/workflows/project-sync.yml (pass -IncludeProjectSync to install it)"
    $SkippedCount++
}

# --- .agents / .claude / .cursor ------------------------------------------

Copy-IfMissing (Join-Path $Templates ".agents/skills/issue-to-pr-project/SKILL.md") ".agents/skills/issue-to-pr-project/SKILL.md"
Copy-IfMissing (Join-Path $Templates ".claude/skills/issue-to-pr-project/SKILL.md") ".claude/skills/issue-to-pr-project/SKILL.md"
Copy-IfMissing (Join-Path $Templates ".agents/skills/github_kit/SKILL.md") ".agents/skills/github_kit/SKILL.md"
Copy-IfMissing (Join-Path $Templates ".claude/skills/github_kit/SKILL.md") ".claude/skills/github_kit/SKILL.md"
Copy-IfMissing (Join-Path $Templates ".claude/commands/github_kit.md") ".claude/commands/github_kit.md"
Copy-IfMissing (Join-Path $Templates ".agents/skills/github_kit_update/SKILL.md") ".agents/skills/github_kit_update/SKILL.md"
Copy-IfMissing (Join-Path $Templates ".claude/skills/github_kit_update/SKILL.md") ".claude/skills/github_kit_update/SKILL.md"

foreach ($rule in @("agent-workflow", "git-safety", "project-board", "github-kit-command")) {
    Copy-IfMissing (Join-Path $Templates ".cursor/rules/$rule.mdc") ".cursor/rules/$rule.mdc"
}

# --- scripts/project/ --------------------------------------------------

foreach ($script in @("project_add_item", "project_set_status", "project_set_text", "verify_agent_workflow", "create_standard_labels", "create_agent_issue", "publish_agent_branch", "sync_project_fields", "create_agent_pr")) {
    Copy-IfMissing (Join-Path $Templates "scripts/project/$script.sh") "scripts/project/$script.sh"
}

# --- .gitignore -------------------------------------------------------

$GitignoreLine = "docs/ai/PROJECT_CONFIG.env"
if (Test-Path -LiteralPath ".gitignore" -PathType Leaf) {
    $existingLines = Get-Content -LiteralPath ".gitignore"
    if ($existingLines -notcontains $GitignoreLine) {
        Add-Content -LiteralPath ".gitignore" -Value "`n$GitignoreLine"
        Write-Host "updated:         .gitignore (added $GitignoreLine)"
        $UpdatedCount++
    } else {
        Write-Host "skip (exists):   .gitignore already ignores $GitignoreLine"
        $SkippedCount++
    }
} else {
    Set-Content -LiteralPath ".gitignore" -Value $GitignoreLine
    Write-Host "created:         .gitignore"
    $CreatedCount++
}

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
