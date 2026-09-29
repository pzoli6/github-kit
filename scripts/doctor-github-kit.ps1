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

# --- kit manifest: the single list of installed files ------------------------
#
# templates/docs/ai/KIT_MANIFEST.tsv drives install, update, and target-repo verification, so its
# integrity is checked here: every row points at a real template with a known mode and group,
# every template is listed, repo-owned files keep a non-overwriting mode, and managed blocks agree.

$Manifest = "templates/docs/ai/KIT_MANIFEST.tsv"
Check-File $Manifest
Check-File "scripts/lib/kit.sh"
Check-File "scripts/lib/Kit.ps1"

if (Test-Path -LiteralPath $Manifest) {
    $manifestOk = $true
    $modes = @{}
    foreach ($line in Get-Content -LiteralPath $Manifest) {
        if (-not $line -or $line.StartsWith('#')) { continue }
        $f = $line -split "`t"
        if ($f[0] -eq 'phrase') { continue }
        if ($f[0] -ne 'file') { Write-Host "FAILED  manifest row kind '$($f[0])' is unknown"; $manifestOk = $false; continue }
        $path = $f[1]; $mode = $f[2]; $group = $f[3]
        $modes[$path] = $mode
        Check-File "templates/$path"
        if ($mode -notin 'block', 'refresh', 'refresh-exec', 'workflow', 'workflow-create', 'workflow-opt', 'create', 'config') {
            Write-Host "FAILED  manifest mode '$mode' for $path is unknown"; $manifestOk = $false
        }
        if ($group -notin 'core', 'claude', 'cursor', 'skills', 'gemini', 'copilot', '-') {
            Write-Host "FAILED  manifest verify group '$group' for $path is unknown"; $manifestOk = $false
        }
        if ($mode -eq 'block' -and (Test-Path -LiteralPath "templates/$path")) {
            $markers = @(Get-Content -LiteralPath "templates/$path" | Where-Object { $_ -match '^<!-- (BEGIN|END) GITHUB-KIT [A-Z -]+ -->$' }).Count
            if ($markers -ne 2) {
                Write-Host "FAILED  templates/$path (mode block) needs exactly one BEGIN and one END GITHUB-KIT marker line"
                $manifestOk = $false
            }
        }
    }

    # Every template must be installable: a file under templates/ missing from the manifest would
    # silently never reach a target repo.
    $templateFiles = @(& git ls-files -- templates) + @(& git ls-files --others --exclude-standard -- templates)
    foreach ($t in $templateFiles) {
        if (-not $t) { continue }
        $rel = $t.Substring("templates/".Length)
        if (-not $modes.ContainsKey($rel)) {
            Write-Host "FAILED  $t exists but is not listed in $Manifest"
            $manifestOk = $false
        }
    }

    # Repo-owned files must never be overwritten by an update.
    $protected = [ordered]@{
        'docs/ai/PROJECT_CONFIG.md' = 'config'
        'docs/ai/design-handoffs/DESIGN_SYNC.md' = 'create'
        '.claude/settings.json' = 'create'
        '.github/ISSUE_TEMPLATE/agent_task.yml' = 'create'
        '.github/PULL_REQUEST_TEMPLATE.md' = 'create'
        '.github/workflows/pr-policy.yml' = 'workflow-create'
        '.github/workflows/project-setup.yml' = 'workflow-create'
        '.github/workflows/project-sync.yml' = 'workflow-opt'
    }
    foreach ($k in $protected.Keys) {
        $got = if ($modes.ContainsKey($k)) { $modes[$k] } else { 'none' }
        if ($got -ne $protected[$k]) {
            Write-Host "FAILED  $k must be mode '$($protected[$k])' in the manifest (found '$got') -- it holds repo-owned content"
            $manifestOk = $false
        }
    }

    # AGENTS.md, CLAUDE.md, and GEMINI.md carry the same universal block.
    $blockPattern = '(?ms)^<!-- BEGIN GITHUB-KIT UNIVERSAL WORKFLOW -->$.*?^<!-- END GITHUB-KIT UNIVERSAL WORKFLOW -->$'
    $blocks = @('AGENTS', 'CLAUDE', 'GEMINI' | ForEach-Object {
        [regex]::Match((Get-Content -LiteralPath "templates/$_.md" -Raw), $blockPattern).Value
    } | Sort-Object -Unique)
    if ($blocks.Count -ne 1) {
        Write-Host "FAILED  the UNIVERSAL WORKFLOW block differs between templates/AGENTS.md, CLAUDE.md, and GEMINI.md"
        $manifestOk = $false
    }

    if ($manifestOk) {
        Write-Host "OK      manifest: every row valid, every template listed, repo-owned files protected, blocks agree"
    } else {
        $script:Missing = 1
    }
}

Write-Host ""

# --- every reusable-workflow job honors the KIT_ACTIONS_PAUSED budget switch ------

$pauseOk = $true
foreach ($wf in Get-ChildItem -Path ".github/workflows" -Filter "reusable-*.yml") {
    $lines = Get-Content -LiteralPath $wf.FullName
    $inJobs = $false; $jobs = 0
    foreach ($l in $lines) {
        if ($l -match '^jobs:') { $inJobs = $true; continue }
        if ($inJobs -and $l -match '^  [A-Za-z0-9_-]+:\s*$') { $jobs++ }
    }
    $guards = @($lines | Where-Object { $_.Contains("vars.KIT_ACTIONS_PAUSED != 'true'") }).Count
    if ($guards -lt $jobs) {
        Write-Host "FAILED  .github/workflows/$($wf.Name) has $jobs job(s) but only $guards KIT_ACTIONS_PAUSED guard(s)"
        $pauseOk = $false
    }
}
if ($pauseOk) {
    Write-Host "OK      every reusable-workflow job carries the KIT_ACTIONS_PAUSED guard"
} else {
    $script:Missing = 1
}

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

# The install/update scripts hard-depend on both design-sync payload files existing; a missing
# one aborts an installer mid-run in a target repo, so catch it before tagging.
$applyScript = Get-Content -LiteralPath "templates/scripts/design-handoffs/apply-answers.mjs" -Raw -ErrorAction SilentlyContinue
if ($applyScript -match 'design-sync-answers/v1' -and (Test-Path -LiteralPath "templates/docs/ai/design-handoffs/DESIGN_SYNC.md")) {
    Write-Host "OK      apply-answers.mjs + DESIGN_SYNC.md ship the design-sync loop"
} else {
    Write-Host "MISSING design-sync loop payload (apply-answers.mjs with the design-sync-answers/v1 marker, DESIGN_SYNC.md)"
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
