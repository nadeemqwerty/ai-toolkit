<#
.SYNOPSIS
    Workspace status dashboard — shows all repo clones, branches, dirty state.
    Run at session start or before any write operation.

.DESCRIPTION
    Scans all known repo clones under ~\repos\ and reports:
    - Current branch
    - Dirty file count (uncommitted changes)
    - Stash count
    - Last commit (date + message)
    Outputs a compact table for quick situational awareness.

.EXAMPLE
    .\workspace-status.ps1
    .\workspace-status.ps1 -Repo Catalog   # single repo only
#>
param(
    [string]$Repo = "",        # Filter to single repo (empty = all)
    [switch]$Detailed          # Show dirty file list
)

$repoRoot = "$env:USERPROFILE\repos"

# Known repos (add new ones here)
$knownRepos = @(
    @{ Name = "backend-api";    Lang = "Java" }
    @{ Name = "frontend-app";   Lang = "TypeScript" }
    @{ Name = "data-pipeline";  Lang = "Python" }
    @{ Name = "infra";          Lang = "Terraform" }
    @{ Name = "docs";           Lang = "Markdown" }
)

if ($Repo) {
    $knownRepos = $knownRepos | Where-Object { $_.Name -like "*$Repo*" }
}

$results = @()

foreach ($r in $knownRepos) {
    $path = Join-Path $repoRoot $r.Name
    if (-not (Test-Path "$path\.git")) {
        $results += [PSCustomObject]@{
            Repo     = $r.Name
            Branch   = "NOT CLONED"
            Dirty    = "—"
            Stashes  = "—"
            LastCommit = "—"
        }
        continue
    }

    $branch = git -C $path rev-parse --abbrev-ref HEAD 2>$null
    $dirty = (git -C $path status --porcelain 2>$null | Measure-Object).Count
    $stashes = (git -C $path stash list 2>$null | Measure-Object).Count
    $lastCommit = git -C $path log -1 --format="%ar | %s" 2>$null

    $dirtyLabel = if ($dirty -gt 0) { "⚠️ $dirty files" } else { "✅ clean" }
    $stashLabel = if ($stashes -gt 0) { "📦 $stashes" } else { "0" }

    $results += [PSCustomObject]@{
        Repo       = $r.Name
        Branch     = $branch
        Dirty      = $dirtyLabel
        Stashes    = $stashLabel
        LastCommit = ($lastCommit | Select-Object -First 1)
    }

    if ($Detailed -and $dirty -gt 0) {
        Write-Host "`n  Dirty files in $($r.Name):" -ForegroundColor Yellow
        git -C $path status --porcelain | ForEach-Object { Write-Host "    $_" }
    }
}

Write-Host "`n📊 WORKSPACE STATUS" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
$results | Format-Table -AutoSize
Write-Host ""

# Summary warnings
$dirtyRepos = $results | Where-Object { $_.Dirty -like "*⚠️*" }
if ($dirtyRepos) {
    Write-Host "⚠️  DIRTY REPOS (have uncommitted changes):" -ForegroundColor Yellow
    $dirtyRepos | ForEach-Object { Write-Host "   - $($_.Repo) on branch '$($_.Branch)'" -ForegroundColor Yellow }
    Write-Host ""
}
