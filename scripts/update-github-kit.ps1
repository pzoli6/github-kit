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
  exists, it is always refreshed regardless of this flag.

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
#>
[CmdletBinding()]
param(
    [string]$Target = ".",
    [switch]$ForceConfig,
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

function Refresh-File {
    # Always overwrite $Dst with $Src (creating it if missing).
    param([string]$Src, [string]$Dst)
    Ensure-ParentDir $Dst
    if (Test-Path -LiteralPath $Dst) {
        Copy-Item -LiteralPath $Src -Destination $Dst -Force
        Write-Host "refreshed:       $Dst"
        $script:UpdatedCount++
    } else {
        Copy-Item -LiteralPath $Src -Destination $Dst
        Write-Host "created:         $Dst"
        $script:CreatedCount++
    }
}

function Refresh-Workflow {
    # Always overwrite $Dst with $Src (creating it if missing). Templates pin caller `uses:`
    # lines to @main (the always-latest channel); if -Ref/-WorkflowRef resolved to something
    # else, repoint only that `uses: pzoli6/github-kit/...` line to the requested ref -- never
    # touch unrelated occurrences of the word "main" (e.g. branch triggers).
    param([string]$Src, [string]$Dst)
    Ensure-ParentDir $Dst
    $pattern = '(uses: pzoli6/github-kit/[^@\s]+)@main'
    $content = (Get-Content -LiteralPath $Src -Raw) -replace $pattern, "`$1@$WorkflowRef"
    if (Test-Path -LiteralPath $Dst) {
        Set-Content -LiteralPath $Dst -Value $content -NoNewline
        Write-Host "refreshed:       $Dst"
        $script:UpdatedCount++
    } else {
        Set-Content -LiteralPath $Dst -Value $content -NoNewline
        Write-Host "created:         $Dst"
        $script:CreatedCount++
    }
}

function CreateOnly-Workflow {
    # Like Refresh-Workflow but NEVER overwrites an existing file. pr-policy.yml carries repo-specific
    # gate inputs (required_base_branch, require_agent_branch_prefix); overwriting it would reset a
    # repo's base branch and break its PR checks. Preserved once created, like PROJECT_CONFIG.md. The
    # reusable-pr-policy.yml@main logic it calls still auto-tracks @main.
    param([string]$Src, [string]$Dst)
    if (Test-Path -LiteralPath $Dst) {
        Write-Host "skip (repo-specific caller, preserved): $Dst"
        $script:SkippedCount++
        return
    }
    Ensure-ParentDir $Dst
    $pattern = '(uses: pzoli6/github-kit/[^@\s]+)@main'
    $content = (Get-Content -LiteralPath $Src -Raw) -replace $pattern, "`$1@$WorkflowRef"
    Set-Content -LiteralPath $Dst -Value $content -NoNewline
    Write-Host "created:         $Dst"
    $script:CreatedCount++
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
approve
```

Fast path: `/github_kit <task>` is a pre-approved alternative entry point — the invocation itself is the approval for the described task, scoped to that task only. See `docs/ai/AGENT_WORKFLOW.md` → "Fast-path trigger: /github_kit".

Agents must not push to protected branches, merge PRs, modify secrets, use `git add .`, or claim validation passed unless validation actually ran.

Solo mode: `docs/ai/PROJECT_CONFIG.md` → "Solo mode" (default `auto` — active until a real GitHub Project is configured) collapses the lifecycle to plan → approval → branch/worktree → implementation → validation → draft PR: no issue for pre-approved iterations, no Project-field updates, handoff files only when actually stopping mid-task. Approval gates and git/PR safety rules apply unchanged.

Before stopping mid-task, losing context, or handing off to another agent, agents must update:
- `docs/ai/handoffs/issue-<number>.md`
- Project field: `Last Agent Update` (full mode only)
- Project field: `Validation` (full mode only)
<!-- END GITHUB-KIT UNIVERSAL WORKFLOW -->
'@
    return ($block -replace "`r`n", "`n")
}

function Apply-ManagedBlock {
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

# --- AGENTS.md / CLAUDE.md (always refresh the managed block) -------------

Apply-ManagedBlock "AGENTS.md" (Join-Path $Templates "AGENTS.md")
Apply-ManagedBlock "CLAUDE.md" (Join-Path $Templates "CLAUDE.md")
Apply-ManagedBlock "GEMINI.md" (Join-Path $Templates "GEMINI.md")

# --- docs/ai/ (PROJECT_CONFIG.md protected unless -ForceConfig) ---------

if ($ForceConfig) {
    Refresh-File (Join-Path $Templates "docs/ai/PROJECT_CONFIG.md") "docs/ai/PROJECT_CONFIG.md"
} elseif (Test-Path -LiteralPath "docs/ai/PROJECT_CONFIG.md") {
    Write-Host "skip (repo-specific, use -ForceConfig to override): docs/ai/PROJECT_CONFIG.md"
    $SkippedCount++
} else {
    Refresh-File (Join-Path $Templates "docs/ai/PROJECT_CONFIG.md") "docs/ai/PROJECT_CONFIG.md"
}

Refresh-File (Join-Path $Templates "docs/ai/PROJECT_CONFIG.env.example") "docs/ai/PROJECT_CONFIG.env.example"
Refresh-File (Join-Path $Templates "docs/ai/AGENT_WORKFLOW.md") "docs/ai/AGENT_WORKFLOW.md"
Refresh-File (Join-Path $Templates "docs/ai/HANDOFF_INDEX.md") "docs/ai/HANDOFF_INDEX.md"
New-Item -ItemType Directory -Force -Path "docs/ai/handoffs" | Out-Null
if (-not (Test-Path -LiteralPath "docs/ai/handoffs/.gitkeep")) {
    Refresh-File (Join-Path $Templates "docs/ai/handoffs/.gitkeep") "docs/ai/handoffs/.gitkeep"
}

# --- .github/ (issue/PR templates are never auto-overwritten) -------------

if (Test-Path -LiteralPath ".github/ISSUE_TEMPLATE/agent_task.yml") {
    Write-Host "skip (may be customized): .github/ISSUE_TEMPLATE/agent_task.yml"
    $SkippedCount++
} else {
    Refresh-File (Join-Path $Templates ".github/ISSUE_TEMPLATE/agent_task.yml") ".github/ISSUE_TEMPLATE/agent_task.yml"
}

if (Test-Path -LiteralPath ".github/PULL_REQUEST_TEMPLATE.md") {
    Write-Host "skip (may be customized): .github/PULL_REQUEST_TEMPLATE.md"
    $SkippedCount++
} else {
    Refresh-File (Join-Path $Templates ".github/PULL_REQUEST_TEMPLATE.md") ".github/PULL_REQUEST_TEMPLATE.md"
}

Refresh-File (Join-Path $Templates ".github/copilot-instructions.md") ".github/copilot-instructions.md"
Refresh-File (Join-Path $Templates ".github/CODEOWNERS") ".github/CODEOWNERS"

foreach ($wf in @("agent-workflow-verify", "ci-node", "ci-python", "design-handoff-approval")) {
    Refresh-Workflow (Join-Path $Templates ".github/workflows/$wf.yml") ".github/workflows/$wf.yml"
}
# pr-policy.yml holds this repo's base-branch gate — preserve it if it already exists.
CreateOnly-Workflow (Join-Path $Templates ".github/workflows/pr-policy.yml") ".github/workflows/pr-policy.yml"

if ($IncludeProjectSync -or (Test-Path -LiteralPath ".github/workflows/project-sync.yml")) {
    Refresh-Workflow (Join-Path $Templates ".github/workflows/project-sync.yml") ".github/workflows/project-sync.yml"
} else {
    Write-Host "skip (default):  .github/workflows/project-sync.yml (pass -IncludeProjectSync to install it)"
    $SkippedCount++
}

# --- .agents / .claude / .cursor ------------------------------------------

Refresh-File (Join-Path $Templates ".agents/skills/issue-to-pr-project/SKILL.md") ".agents/skills/issue-to-pr-project/SKILL.md"
Refresh-File (Join-Path $Templates ".claude/skills/issue-to-pr-project/SKILL.md") ".claude/skills/issue-to-pr-project/SKILL.md"
Refresh-File (Join-Path $Templates ".agents/skills/github_kit/SKILL.md") ".agents/skills/github_kit/SKILL.md"
Refresh-File (Join-Path $Templates ".claude/skills/github_kit/SKILL.md") ".claude/skills/github_kit/SKILL.md"
Refresh-File (Join-Path $Templates ".claude/commands/github_kit.md") ".claude/commands/github_kit.md"
Refresh-File (Join-Path $Templates ".agents/skills/github_kit_update/SKILL.md") ".agents/skills/github_kit_update/SKILL.md"
Refresh-File (Join-Path $Templates ".claude/skills/github_kit_update/SKILL.md") ".claude/skills/github_kit_update/SKILL.md"

foreach ($rule in @("agent-workflow", "git-safety", "project-board", "github-kit-command")) {
    Refresh-File (Join-Path $Templates ".cursor/rules/$rule.mdc") ".cursor/rules/$rule.mdc"
}


# Legacy hygiene: only SKILL.md-based skill directories belong under .claude/skills/. Older kit
# versions/manual copies sometimes left workflow YAMLs or STATUS_BADGES.md there, which clutter
# the skills listing. Warn -- never delete automatically.
if (Test-Path -LiteralPath ".claude/skills") {
    $straySkills = Get-ChildItem -LiteralPath ".claude/skills" -File |
        Where-Object { $_.Extension -in @(".yml", ".yaml") -or $_.Name -eq "STATUS_BADGES.md" }
    if ($straySkills) {
        Write-Host "warning: non-skill files found directly under .claude/skills/ -- they aren't skills;"
        Write-Host "move workflow YAMLs to .github/workflows/ (or delete them):"
        foreach ($f in $straySkills) { Write-Host "  .claude/skills/$($f.Name)" }
    }
}

# --- docs/ai/design-handoffs/ ------------------------------------------

New-Item -ItemType Directory -Force "docs/ai/design-handoffs" | Out-Null
Refresh-File (Join-Path $Templates "docs/ai/design-handoffs/README.md") "docs/ai/design-handoffs/README.md"
Refresh-File (Join-Path $Templates "docs/ai/design-handoffs/_TEMPLATE.md") "docs/ai/design-handoffs/_TEMPLATE.md"

# --- scripts/design-handoffs/ ------------------------------------------

foreach ($script in @("stamp", "verify")) {
    Refresh-File (Join-Path $Templates "scripts/design-handoffs/$script.mjs") "scripts/design-handoffs/$script.mjs"
}

# --- scripts/project/ -------------------------------------------------

foreach ($script in @("project_add_item", "project_set_status", "project_set_text", "verify_agent_workflow", "create_standard_labels", "create_agent_issue", "publish_agent_branch", "sync_project_fields", "create_agent_pr", "check_resume_safety", "post_handoff_comment", "cleanup_merged_branches")) {
    Refresh-File (Join-Path $Templates "scripts/project/$script.sh") "scripts/project/$script.sh"
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
