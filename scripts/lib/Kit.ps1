# Shared helpers for install-github-kit.ps1 and update-github-kit.ps1. Dot-sourced, never run.
# PowerShell twin of scripts/lib/kit.sh: same manifest, same modes, same output files.
#
# The list of files, and how each is treated, lives in templates/docs/ai/KIT_MANIFEST.tsv. This
# library only knows the *modes* (see the manifest header); it never names a template file itself.
#
# Callers set before calling Sync-KitManifest:
#   $Templates           path to github-kit's templates/ directory
#   $KitOp               "install" | "update"
#   $KitForce            $true = install -Mode force (refresh kit-owned files that already exist)
#   $KitForceConfig      $true = update -ForceConfig (reset `config` files to the template)
#   $KitIncludeSync      $true = install `workflow-opt` files even when absent
#   $WorkflowRef         ref written into `uses: pzoli6/github-kit/...@<ref>` lines
#   $KitTier             "1" | "2" | "" (empty = keep each caller's current tier, default 1)
# and read back $script:CreatedCount, $script:UpdatedCount, $script:SkippedCount afterwards.

$script:CreatedCount = 0
$script:UpdatedCount = 0
$script:SkippedCount = 0

$KitTierBegin = '# >>> github-kit tier-1 triggers'
$KitTierEnd = '# <<< github-kit tier-1 triggers'
$KitBlockPattern = '(?ms)^<!-- BEGIN GITHUB-KIT [A-Z -]+ -->$.*?^<!-- END GITHUB-KIT [A-Z -]+ -->$'

function Get-KitManifestRows {
    # Returns objects with Kind, A (path or phrase), Mode, Verify for every non-comment row.
    param([string]$Manifest = (Join-Path $Templates "docs/ai/KIT_MANIFEST.tsv"))
    foreach ($line in Get-Content -LiteralPath $Manifest) {
        if (-not $line -or $line.StartsWith('#')) { continue }
        $f = $line -split "`t"
        [pscustomobject]@{
            Kind   = $f[0]
            A      = if ($f.Count -gt 1) { $f[1] } else { "" }
            Mode   = if ($f.Count -gt 2) { $f[2] } else { "" }
            Verify = if ($f.Count -gt 3) { $f[3] } else { "" }
            Retired = if ($f.Count -gt 4) { $f[4] } else { "" }
        }
    }
}

function Write-KitLog {
    param([string]$Action, [string]$Path)
    Write-Host ("{0,-26} {1}" -f "${Action}:", $Path)
}

function Ensure-KitParentDir {
    param([string]$Path)
    $dir = Split-Path -Path $Path -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
}

function Get-KitExistingTier {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return "" }
    $m = [regex]::Match((Get-Content -LiteralPath $Path -Raw), '(?m)^# github-kit tier: ([0-9]+)[ \t]*$')
    if ($m.Success) { return $m.Groups[1].Value }
    return ""
}

function Write-KitWorkflow {
    # Render a caller workflow template: point `uses: pzoli6/github-kit/...` at $WorkflowRef and
    # apply the tier. Other occurrences of "main" (branch filters) are left alone.
    param([string]$Src, [string]$Dst)
    $tier = $KitTier
    if (-not $tier) { $tier = Get-KitExistingTier $Dst }
    if (-not $tier) { $tier = "1" }
    $content = (Get-Content -LiteralPath $Src -Raw) -replace '(uses: pzoli6/github-kit/[^@\s]+)@main', "`$1@$WorkflowRef"
    $content = $content -replace '(?m)^# github-kit tier: [0-9]+[ \t]*$', "# github-kit tier: $tier"
    if ($tier -ne "1") {
        $b = [regex]::Escape($KitTierBegin); $e = [regex]::Escape($KitTierEnd)
        $content = [regex]::Replace($content, "(?ms)^[^\n]*$b[^\n]*\n.*?^[^\n]*$e[^\n]*\n", "")
    }
    Ensure-KitParentDir $Dst
    Set-Content -LiteralPath $Dst -Value $content -NoNewline
}

function Copy-KitFile {
    param([string]$Mode, [string]$Src, [string]$Dst)
    if ($Mode -like 'workflow*') {
        Write-KitWorkflow $Src $Dst
    } else {
        Ensure-KitParentDir $Dst
        Copy-Item -LiteralPath $Src -Destination $Dst -Force
    }
}

function Set-KitManagedBlock {
    # Refresh only the text between the template's own markers inside $Dst; create $Dst from the
    # whole template if it doesn't exist; append the block if $Dst exists without markers.
    param([string]$Src, [string]$Dst)
    $m = [regex]::Match((Get-Content -LiteralPath $Src -Raw), $KitBlockPattern)
    if (-not $m.Success) { throw "$Src has no <!-- BEGIN/END GITHUB-KIT ... --> managed block" }
    $block = $m.Value
    $lines = $block -split "`n"
    $begin = $lines[0]; $end = $lines[-1]

    if (-not (Test-Path -LiteralPath $Dst)) {
        Ensure-KitParentDir $Dst
        Copy-Item -LiteralPath $Src -Destination $Dst
        Write-KitLog "created" $Dst
        $script:CreatedCount++
        return
    }

    $content = Get-Content -LiteralPath $Dst -Raw
    if ($null -eq $content) { $content = "" }
    if ([regex]::IsMatch($content, "(?m)^$([regex]::Escape($begin))\r?$")) {
        $pattern = "(?ms)^$([regex]::Escape($begin))\r?$.*?^$([regex]::Escape($end))\r?\n?"
        $evaluator = [System.Text.RegularExpressions.MatchEvaluator] { param($x) $block + "`n" }
        $newContent = [regex]::Replace($content, $pattern, $evaluator)
        Set-Content -LiteralPath $Dst -Value $newContent -NoNewline
        Write-KitLog "updated managed block" $Dst
    } else {
        Set-Content -LiteralPath $Dst -Value ($content + "`n" + $block + "`n") -NoNewline
        Write-KitLog "appended managed block" $Dst
    }
    $script:UpdatedCount++
}

function Remove-KitRetiredFile {
    # A file the kit no longer ships: delete it only if it is exactly a version the kit shipped
    # ($Shas = comma-separated git blob SHAs). An edited copy belongs to the repo now, so it stays.
    param([string]$Path, [string]$Shas)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $sha = (& git hash-object -- $Path 2>$null)
    if ($sha -and (($Shas -split ',') -contains $sha.Trim())) {
        Remove-Item -LiteralPath $Path -Force
        Write-KitLog "removed (retired)" $Path
        $script:UpdatedCount++
    } else {
        Write-KitLog "kept (retired, edited)" "$Path -- the kit no longer ships it; delete it if unused"
        $script:SkippedCount++
    }
}

function Sync-KitFile {
    param([string]$Path, [string]$Mode, [string]$Retired = "")
    if ($Mode -eq 'retired') { Remove-KitRetiredFile $Path $Retired; return }
    $src = Join-Path $Templates $Path
    if (-not (Test-Path -LiteralPath $src)) { throw "manifest lists $Path but $src does not exist" }

    if ($Mode -eq 'block') { Set-KitManagedBlock $src $Path; return }

    if ($Mode -eq 'workflow-opt' -and -not $KitIncludeSync -and ($KitOp -eq 'install' -or -not (Test-Path -LiteralPath $Path))) {
        Write-KitLog "skip (default)" "$Path (pass -IncludeProjectSync to install it)"
        $script:SkippedCount++
        return
    }

    $overwrite = $false
    switch ($Mode) {
        { $_ -in 'refresh', 'refresh-exec', 'workflow' } { $overwrite = ($KitOp -eq 'update') -or [bool]$KitForce }
        'config' { $overwrite = ($KitOp -eq 'update') -and [bool]$KitForceConfig }
        { $_ -in 'create', 'workflow-create', 'workflow-opt' } { }
        default { throw "unknown manifest mode '$Mode' for $Path" }
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        Copy-KitFile $Mode $src $Path
        Write-KitLog "created" $Path
        $script:CreatedCount++
    } elseif ($overwrite) {
        Copy-KitFile $Mode $src $Path
        Write-KitLog "refreshed" $Path
        $script:UpdatedCount++
    } else {
        $label = if ($Mode -in 'refresh', 'refresh-exec', 'workflow') { "skip (exists)" } else { "skip (repo-owned, kept)" }
        Write-KitLog $label $Path
        $script:SkippedCount++
    }

    if ($Mode -eq 'refresh-exec' -and -not $IsWindows) {
        & chmod +x $Path 2>$null
    }
}

function Sync-KitManifest {
    foreach ($row in Get-KitManifestRows) {
        if ($row.Kind -eq 'file') { Sync-KitFile $row.A $row.Mode $row.Retired }
    }
}

function Write-KitStraySkillWarning {
    # Only SKILL.md-based skill directories belong under .claude/skills/. Warn; never delete.
    if (-not (Test-Path -LiteralPath ".claude/skills" -PathType Container)) { return }
    $stray = Get-ChildItem -LiteralPath ".claude/skills" -File |
        Where-Object { $_.Name -like '*.yml' -or $_.Name -like '*.yaml' -or $_.Name -eq 'STATUS_BADGES.md' }
    if ($stray) {
        Write-Warning "non-skill files found directly under .claude/skills/ -- they aren't skills;"
        Write-Host "move workflow YAMLs to .github/workflows/ (or delete them):"
        $stray | ForEach-Object { Write-Host "  $($_.Name)" }
    }
}

function Set-KitGitignore {
    $line = "docs/ai/PROJECT_CONFIG.env"
    if (Test-Path -LiteralPath ".gitignore" -PathType Leaf) {
        if ((Get-Content -LiteralPath ".gitignore") -notcontains $line) {
            Add-Content -LiteralPath ".gitignore" -Value "`n$line"
            Write-KitLog "updated" ".gitignore (added $line)"
        } else {
            Write-KitLog "skip (exists)" ".gitignore already ignores $line"
        }
    } else {
        Set-Content -LiteralPath ".gitignore" -Value $line
        Write-KitLog "created" ".gitignore"
    }
}
