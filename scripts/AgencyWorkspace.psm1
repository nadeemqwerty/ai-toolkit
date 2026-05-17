<#
.SYNOPSIS
    Agency workspace isolation using Git worktrees + advisory registry.
    Prevents parallel Agency sessions from interfering with each other.
.DESCRIPTION
    Functions:
      New-AgencyWorkspace    — create an isolated worktree for a task
      Remove-AgencyWorkspace — clean up a worktree
      Get-AgencyWorkspaces   — list active workspaces
.NOTES
    Worktrees live at ~/repos/_worktrees/<Repo>/<Task>/
    Registry at ~/.copilot/workspace-registry.json (advisory, git worktree list is source of truth)
#>

$script:ReposRoot      = Join-Path $env:USERPROFILE 'repos'
$script:WorktreeRoot   = Join-Path $script:ReposRoot '_worktrees'
$script:RegistryPath   = Join-Path $env:USERPROFILE '.copilot' 'workspace-registry.json'
$script:LockPath       = "$($script:RegistryPath).lock"
$script:DefaultUser    = $env:USERNAME

# ── Helpers ──────────────────────────────────────────────────────────────

function ConvertTo-SafeSlug {
    param([string]$Name)
    $slug = $Name.ToLower() -replace '[^a-z0-9\-]', '-' -replace '--+', '-' -replace '^-|-$', ''
    if ($slug.Length -gt 60) { $slug = $slug.Substring(0, 60) -replace '-$', '' }
    if (-not $slug) { throw "Task name '$Name' produces an empty slug." }
    return $slug
}

function Get-RegistryLock {
    $dir = Split-Path $script:LockPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $retries = 0
    while ($retries -lt 10) {
        try {
            $lock = [System.IO.File]::Open($script:LockPath, 'OpenOrCreate', 'ReadWrite', 'None')
            return $lock
        } catch {
            $retries++
            Start-Sleep -Milliseconds 200
        }
    }
    throw "Could not acquire registry lock after 2 seconds. Another session may be updating."
}

function Read-Registry {
    if (-not (Test-Path $script:RegistryPath)) { return @() }
    try {
        $json = Get-Content $script:RegistryPath -Raw -ErrorAction Stop
        if (-not $json -or $json.Trim() -eq '') { return @() }
        $entries = $json | ConvertFrom-Json
        if ($entries -is [array]) { return $entries } else { return @($entries) }
    } catch {
        Write-Warning "Registry JSON corrupt, falling back to empty. Error: $_"
        return @()
    }
}

function Write-Registry {
    param([array]$Entries)
    $dir = Split-Path $script:RegistryPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $tmpPath = "$($script:RegistryPath).tmp"
    if ($null -eq $Entries -or $Entries.Count -eq 0) {
        '[]' | Set-Content -Path $tmpPath -Encoding UTF8 -Force
    } else {
        ConvertTo-Json -InputObject $Entries -Depth 5 | Set-Content -Path $tmpPath -Encoding UTF8 -Force
    }
    Move-Item -Path $tmpPath -Destination $script:RegistryPath -Force
}

function Get-MainClonePath {
    param([string]$Repo)
    $path = Join-Path $script:ReposRoot $Repo
    if (-not (Test-Path (Join-Path $path '.git'))) {
        throw "Main clone not found at '$path'. Ensure the repo is cloned in ~/repos/$Repo"
    }
    return $path
}

# ── Public Functions ─────────────────────────────────────────────────────

function New-AgencyWorkspace {
    <#
    .SYNOPSIS
        Create an isolated git worktree for a task.
    .PARAMETER Repo
        Name of the repo (must exist as ~/repos/<Repo>).
    .PARAMETER Task
        Short task name (e.g., "jersey-fix"). Sanitized to a safe slug.
    .PARAMETER Branch
        Existing branch to check out. Mutually exclusive with -NewBranch.
    .PARAMETER NewBranch
        Create a new branch with this name. Defaults to users/<user>/<task-slug>.
    .PARAMETER Base
        Base ref for new branch creation (default: origin/main).
    .PARAMETER Fetch
        Run git fetch before creating worktree.
    .EXAMPLE
        New-AgencyWorkspace -Repo backend-api -Task jersey-fix
        New-AgencyWorkspace -Repo backend-api -Task repro -Branch bugfix/foo
        New-AgencyWorkspace -Repo backend-api -Task migration -NewBranch users/jane/migration -Base origin/main -Fetch
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][string]$Task,
        [string]$Branch,
        [string]$NewBranch,
        [string]$Base = 'origin/main',
        [switch]$Fetch
    )

    if ($Branch -and $NewBranch) {
        throw "Use either -Branch (existing) or -NewBranch (create), not both."
    }

    $slug = ConvertTo-SafeSlug $Task
    $mainClone = Get-MainClonePath $Repo
    $worktreePath = Join-Path $script:WorktreeRoot $Repo $slug

    # Check if worktree already exists
    if (Test-Path $worktreePath) {
        Write-Host "⚠ Workspace already exists at: $worktreePath" -ForegroundColor Yellow
        Write-Host "  Use 'Remove-AgencyWorkspace -Repo $Repo -Task $Task' to clean up first."
        return $worktreePath
    }

    # Ensure _worktrees/<Repo> dir exists
    $repoWorktreeDir = Join-Path $script:WorktreeRoot $Repo
    if (-not (Test-Path $repoWorktreeDir)) {
        New-Item -ItemType Directory -Path $repoWorktreeDir -Force | Out-Null
    }

    # Optional fetch
    if ($Fetch) {
        Write-Host "📡 Fetching latest from remote..." -ForegroundColor Cyan
        git -C $mainClone fetch --prune --quiet 2>&1 | Out-Null
    }

    # Determine branch strategy
    if ($Branch) {
        # Check if branch is already checked out in another worktree
        $wtList = git -C $mainClone worktree list --porcelain 2>&1
        $checkedOut = $wtList | Select-String "branch refs/heads/$Branch" | Measure-Object
        if ($checkedOut.Count -gt 0) {
            throw "Branch '$Branch' is already checked out in another worktree. Use a different branch or task name."
        }
        Write-Host "🌿 Creating worktree with existing branch: $Branch" -ForegroundColor Green
        git -C $mainClone worktree add $worktreePath $Branch 2>&1
    }
    elseif ($NewBranch) {
        # Validate branch name
        $refCheck = git check-ref-format --branch $NewBranch 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Invalid branch name '$NewBranch': $refCheck"
        }
        Write-Host "🌱 Creating worktree with new branch: $NewBranch (from $Base)" -ForegroundColor Green
        git -C $mainClone worktree add -b $NewBranch $worktreePath $Base 2>&1
    }
    else {
        # Default: create new branch users/<user>/<slug>
        $autoBranch = "users/$script:DefaultUser/$slug"
        Write-Host "🌱 Creating worktree with new branch: $autoBranch (from $Base)" -ForegroundColor Green
        git -C $mainClone worktree add -b $autoBranch $worktreePath $Base 2>&1
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create worktree. Check git output above."
    }

    # Determine actual branch
    $actualBranch = git -C $worktreePath rev-parse --abbrev-ref HEAD 2>&1

    # Register in advisory registry (atomic write with lock)
    $lock = $null
    try {
        $lock = Get-RegistryLock
        $entries = Read-Registry
        $entry = [PSCustomObject]@{
            repo          = $Repo
            task          = $slug
            branch        = $actualBranch
            worktreePath  = $worktreePath
            mainClonePath = $mainClone
            baseRef       = $Base
            createdAt     = (Get-Date -Format 'o')
            status        = 'active'
        }
        $entries = @($entries) + @($entry)
        Write-Registry $entries
    } finally {
        if ($lock) { $lock.Close() }
    }

    Write-Host ""
    Write-Host "✅ Workspace ready!" -ForegroundColor Green
    Write-Host "   Path:   $worktreePath" -ForegroundColor White
    Write-Host "   Branch: $actualBranch" -ForegroundColor White
    Write-Host "   Repo:   $Repo" -ForegroundColor White
    Write-Host ""
    Write-Host "   cd '$worktreePath'" -ForegroundColor Cyan
    Write-Host ""

    return $worktreePath
}

function Remove-AgencyWorkspace {
    <#
    .SYNOPSIS
        Remove a worktree workspace and deregister it.
    .PARAMETER Repo
        Name of the repo.
    .PARAMETER Task
        Task name (same slug used during creation).
    .PARAMETER Force
        Force removal even if worktree has uncommitted changes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][string]$Task,
        [switch]$Force
    )

    $slug = ConvertTo-SafeSlug $Task
    $mainClone = Get-MainClonePath $Repo
    $worktreePath = Join-Path $script:WorktreeRoot $Repo $slug

    if (-not (Test-Path $worktreePath)) {
        Write-Warning "Worktree path does not exist: $worktreePath"
    } else {
        # Check for dirty state
        $dirty = git -C $worktreePath status --porcelain 2>&1
        if ($dirty -and -not $Force) {
            Write-Host "⚠ Worktree has uncommitted changes:" -ForegroundColor Yellow
            Write-Host $dirty -ForegroundColor DarkYellow
            Write-Host ""
            Write-Host "Use -Force to discard, or commit/stash changes first." -ForegroundColor Yellow
            return
        }

        # Remove worktree
        $forceFlag = if ($Force) { '--force' } else { '' }
        Write-Host "🗑 Removing worktree: $worktreePath" -ForegroundColor Cyan
        if ($Force) {
            git -C $mainClone worktree remove $worktreePath --force 2>&1
        } else {
            git -C $mainClone worktree remove $worktreePath 2>&1
        }

        if ($LASTEXITCODE -ne 0) {
            Write-Warning "git worktree remove failed. You may need to clean up manually."
        }
    }

    # Deregister from registry
    $lock = $null
    try {
        $lock = Get-RegistryLock
        $entries = Read-Registry
        $entries = @($entries | Where-Object { -not ($_.repo -eq $Repo -and $_.task -eq $slug) })
        Write-Registry $entries
    } finally {
        if ($lock) { $lock.Close() }
    }

    # Prune stale worktree references
    git -C $mainClone worktree prune 2>&1 | Out-Null

    Write-Host "✅ Workspace removed: $Repo/$slug" -ForegroundColor Green
}

function Get-AgencyWorkspaces {
    <#
    .SYNOPSIS
        List all active Agency workspaces.
    .PARAMETER Repo
        Filter by repo name (optional).
    #>
    [CmdletBinding()]
    param(
        [string]$Repo
    )

    $entries = Read-Registry
    if ($Repo) {
        $entries = @($entries | Where-Object { $_.repo -eq $Repo })
    }

    if ($entries.Count -eq 0) {
        Write-Host "No active workspaces." -ForegroundColor DarkGray
        # Also check git worktree list for any unregistered worktrees
        if (Test-Path $script:WorktreeRoot) {
            $dirs = Get-ChildItem $script:WorktreeRoot -Directory -Recurse -Depth 1 |
                    Where-Object { Test-Path (Join-Path $_.FullName '.git') }
            if ($dirs.Count -gt 0) {
                Write-Host ""
                Write-Host "⚠ Found unregistered worktrees in _worktrees/:" -ForegroundColor Yellow
                $dirs | ForEach-Object { Write-Host "   $($_.FullName)" -ForegroundColor DarkYellow }
            }
        }
        return
    }

    Write-Host ""
    Write-Host "Agency Workspaces" -ForegroundColor Cyan
    Write-Host ("─" * 80) -ForegroundColor DarkGray

    foreach ($e in $entries) {
        $exists = Test-Path $e.worktreePath
        $statusIcon = if ($exists) { "🟢" } else { "🔴" }
        $dirty = ""
        if ($exists) {
            $dirtyFiles = git -C $e.worktreePath status --porcelain 2>&1
            if ($dirtyFiles) { $dirty = " [dirty]" }
        }

        Write-Host "$statusIcon $($e.repo)/$($e.task)$dirty" -ForegroundColor White
        Write-Host "   Branch:  $($e.branch)" -ForegroundColor Gray
        Write-Host "   Path:    $($e.worktreePath)" -ForegroundColor Gray
        Write-Host "   Created: $($e.createdAt)" -ForegroundColor DarkGray
        if (-not $exists) {
            Write-Host "   ⚠ Path no longer exists (stale entry)" -ForegroundColor Yellow
        }
        Write-Host ""
    }
}

# ── Aliases ──────────────────────────────────────────────────────────────
Set-Alias naw New-AgencyWorkspace
Set-Alias raw Remove-AgencyWorkspace
Set-Alias gaw Get-AgencyWorkspaces

# ── Exports ──────────────────────────────────────────────────────────────
Export-ModuleMember -Function New-AgencyWorkspace, Remove-AgencyWorkspace, Get-AgencyWorkspaces
Export-ModuleMember -Alias naw, raw, gaw
