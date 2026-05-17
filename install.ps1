<#
.SYNOPSIS
    One-command installer for AI Toolkit assets on Windows.

.DESCRIPTION
    Installs selected AI Toolkit agents, skills, and knowledge templates into
    ~/.copilot for GitHub Copilot CLI.

.EXAMPLE
    .\install.ps1                    # Interactive — choose what to install
    .\install.ps1 -Preset all        # Install everything
    .\install.ps1 -Preset reliability # Evidence-driven + architect-first + critic
    .\install.ps1 -DryRun            # Preview only
#>
[CmdletBinding()]
param(
    [ValidateSet('reliability', 'productivity', 'all', 'custom')]
    [string]$Preset,

    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = $PSScriptRoot
$UserHome = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
$CopilotRoot = Join-Path $UserHome '.copilot'
$AgentsTarget = Join-Path $CopilotRoot 'agents'
$SkillsTarget = Join-Path $CopilotRoot 'skills'
$KnowledgeTarget = Join-Path $CopilotRoot 'knowledge'

$AgentSourceRoot = Join-Path $RepoRoot 'agents'
$SkillSourceRoot = Join-Path $RepoRoot 'skills'
$KnowledgeSourceRoot = Join-Path $RepoRoot 'knowledge-templates'

$script:ConflictPreference = $null
$script:Summary = [ordered]@{
    DirectoriesCreated = 0
    Copied             = 0
    Overwritten        = 0
    Skipped            = 0
    Planned            = 0
}

function Write-Info {
    param([string]$Message)
    Write-Host "ℹ️  $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "✅ $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "⚠️  $Message" -ForegroundColor Yellow
}

function Write-ErrorLine {
    param([string]$Message)
    Write-Host "❌ $Message" -ForegroundColor Red
}

function Write-Header {
    Write-Host ''
    Write-Host '🧰 AI Toolkit Installer (PowerShell)' -ForegroundColor Magenta
    Write-Host '===================================' -ForegroundColor Magenta
    if ($DryRun) {
        Write-Warn 'Dry run mode enabled — no files will be copied.'
    }
}

function Ensure-Directory {
    param([string]$Path)

    if (Test-Path -LiteralPath $Path) {
        return
    }

    if ($DryRun) {
        Write-Info "Would create directory: $Path"
        $script:Summary.Planned++
        return
    }

    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    $script:Summary.DirectoriesCreated++
    Write-Success "Created directory: $Path"
}

function Get-SortedFileNames {
    param(
        [string]$Path,
        [string]$Filter,
        [string[]]$Exclude = @()
    )

    return @(Get-ChildItem -Path $Path -File -Filter $Filter |
        Where-Object { $_.Name -notin $Exclude } |
        Sort-Object Name |
        ForEach-Object { $_.Name })
}

function Get-SortedDirectoryNames {
    param([string]$Path)

    return @(Get-ChildItem -Path $Path -Directory |
        Sort-Object Name |
        ForEach-Object { $_.Name })
}

$AllAgents = Get-SortedFileNames -Path $AgentSourceRoot -Filter '*.md' -Exclude @('README.md')
$AllSkills = Get-SortedDirectoryNames -Path $SkillSourceRoot
$KnowledgeFiles = Get-SortedFileNames -Path $KnowledgeSourceRoot -Filter '*.md' -Exclude @('README.md')

$PresetMap = @{
    reliability = @{
        Agents = @('critic.md')
        Skills = @('evidence-driven', 'architect-first')
    }
    productivity = @{
        Agents = @()
        Skills = @('cross-session-planner', 'flow-discovery', 'agent-output-contract')
    }
    all = @{
        Agents = $AllAgents
        Skills = $AllSkills
    }
}

function Read-InteractivePreset {
    while ($true) {
        Write-Host ''
        Write-Host 'Choose an install preset:' -ForegroundColor Cyan
        Write-Host '  1) reliability   — evidence-driven + architect-first + critic'
        Write-Host '  2) productivity  — cross-session-planner + flow-discovery + agent-output-contract'
        Write-Host '  3) all           — every available agent and skill'
        Write-Host '  4) custom        — choose agents and skills individually'
        $choice = (Read-Host 'Enter 1, 2, 3, or 4').Trim()
        switch ($choice) {
            '1' { return 'reliability' }
            '2' { return 'productivity' }
            '3' { return 'all' }
            '4' { return 'custom' }
            default { Write-Warn 'Invalid selection. Please try again.' }
        }
    }
}

function Select-CustomItems {
    param(
        [string]$Label,
        [string[]]$Items
    )

    $selected = New-Object System.Collections.Generic.List[string]
    Write-Host ''
    Write-Host "Custom $Label selection:" -ForegroundColor Cyan

    foreach ($item in $Items) {
        while ($true) {
            $answer = (Read-Host "Install $Label '$item'? [y/N]").Trim().ToLowerInvariant()
            if ([string]::IsNullOrWhiteSpace($answer) -or $answer -eq 'n' -or $answer -eq 'no') {
                break
            }
            if ($answer -eq 'y' -or $answer -eq 'yes') {
                $selected.Add($item)
                break
            }
            Write-Warn 'Please answer y or n.'
        }
    }

    return @($selected)
}

function Resolve-Selection {
    $resolvedPreset = if ($Preset) { $Preset } else { Read-InteractivePreset }

    if ($resolvedPreset -eq 'custom') {
        return @{
            Preset = 'custom'
            Agents = Select-CustomItems -Label 'agent' -Items $AllAgents
            Skills = Select-CustomItems -Label 'skill' -Items $AllSkills
        }
    }

    return @{
        Preset = $resolvedPreset
        Agents = @($PresetMap[$resolvedPreset].Agents)
        Skills = @($PresetMap[$resolvedPreset].Skills)
    }
}

function Format-ItemList {
    param([string[]]$Items)

    if (-not $Items -or $Items.Count -eq 0) {
        return 'none'
    }

    return ($Items -join ', ')
}

function Assert-SourcesExist {
    param([hashtable]$Selection)

    $missing = New-Object System.Collections.Generic.List[string]

    foreach ($agent in $Selection.Agents) {
        $path = Join-Path $AgentSourceRoot $agent
        if (-not (Test-Path -LiteralPath $path)) {
            $missing.Add($path)
        }
    }

    foreach ($skill in $Selection.Skills) {
        $path = Join-Path $SkillSourceRoot $skill
        if (-not (Test-Path -LiteralPath $path)) {
            $missing.Add($path)
        }
    }

    foreach ($knowledgeFile in $KnowledgeFiles) {
        $path = Join-Path $KnowledgeSourceRoot $knowledgeFile
        if (-not (Test-Path -LiteralPath $path)) {
            $missing.Add($path)
        }
    }

    if ($missing.Count -gt 0) {
        $missing | ForEach-Object { Write-ErrorLine "Missing source item: $_" }
        throw 'Installer source validation failed.'
    }
}

function Get-ConflictDecision {
    param([string]$Destination)

    if ($script:ConflictPreference -eq 'overwrite-all') {
        return 'overwrite'
    }
    if ($script:ConflictPreference -eq 'skip-all') {
        return 'skip'
    }

    while ($true) {
        $answer = (Read-Host "⚠️  '$Destination' already exists. [O]verwrite, [S]kip, overwrite [A]ll, skip [N]all").Trim().ToLowerInvariant()
        switch ($answer) {
            'o' { return 'overwrite' }
            'overwrite' { return 'overwrite' }
            's' { return 'skip' }
            'skip' { return 'skip' }
            'a' {
                $script:ConflictPreference = 'overwrite-all'
                return 'overwrite'
            }
            'all' {
                $script:ConflictPreference = 'overwrite-all'
                return 'overwrite'
            }
            'n' {
                $script:ConflictPreference = 'skip-all'
                return 'skip'
            }
            'none' {
                $script:ConflictPreference = 'skip-all'
                return 'skip'
            }
            default { Write-Warn 'Please choose O, S, A, or N.' }
        }
    }
}

function Install-Path {
    param(
        [string]$Source,
        [string]$Destination,
        [ValidateSet('File', 'Directory')]
        [string]$Type,
        [string]$Label
    )

    $exists = Test-Path -LiteralPath $Destination
    $action = 'copy'

    if ($exists) {
        if ($DryRun) {
            Write-Info "Would overwrite ${Label}: $Destination"
            $script:Summary.Planned++
            return
        }

        $decision = Get-ConflictDecision -Destination $Destination
        if ($decision -eq 'skip') {
            $script:Summary.Skipped++
            Write-Warn "Skipped ${Label}: $Destination"
            return
        }

        $action = 'overwrite'
    }
    elseif ($DryRun) {
        Write-Info "Would install ${Label}: $Destination"
        $script:Summary.Planned++
        return
    }

    $parent = Split-Path -Parent $Destination
    if ($parent) {
        Ensure-Directory -Path $parent
    }

    if ($Type -eq 'Directory') {
        if ($exists) {
            Remove-Item -LiteralPath $Destination -Recurse -Force
        }
        Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force
    }
    else {
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
    }

    if ($action -eq 'overwrite') {
        $script:Summary.Overwritten++
        Write-Success "Overwrote ${Label}: $Destination"
    }
    else {
        $script:Summary.Copied++
        Write-Success "Installed ${Label}: $Destination"
    }
}

function Validate-Installation {
    param([hashtable]$Selection)

    if ($DryRun) {
        Write-Success 'Dry-run validation passed — all source items are available and target paths were resolved.'
        return $true
    }

    $missing = New-Object System.Collections.Generic.List[string]

    foreach ($agent in $Selection.Agents) {
        $path = Join-Path $AgentsTarget $agent
        if (-not (Test-Path -LiteralPath $path)) {
            $missing.Add($path)
        }
    }

    foreach ($skill in $Selection.Skills) {
        $skillRoot = Join-Path $SkillsTarget $skill
        $skillFile = Join-Path $skillRoot 'SKILL.md'
        if (-not (Test-Path -LiteralPath $skillRoot) -or -not (Test-Path -LiteralPath $skillFile)) {
            $missing.Add($skillFile)
        }
    }

    foreach ($knowledgeFile in $KnowledgeFiles) {
        $path = Join-Path $KnowledgeTarget $knowledgeFile
        if (-not (Test-Path -LiteralPath $path)) {
            $missing.Add($path)
        }
    }

    if ($missing.Count -gt 0) {
        $missing | ForEach-Object { Write-ErrorLine "Missing installed item: $_" }
        return $false
    }

    Write-Success 'Installation validation passed.'
    return $true
}

function Show-Summary {
    param([hashtable]$Selection)

    Write-Host ''
    Write-Host '📦 Summary' -ForegroundColor Magenta
    Write-Host '----------' -ForegroundColor Magenta
    Write-Host "Preset:     $($Selection.Preset)"
    Write-Host "Agents:     $(Format-ItemList -Items $Selection.Agents)"
    Write-Host "Skills:     $(Format-ItemList -Items $Selection.Skills)"
    Write-Host "Knowledge:  $($KnowledgeFiles -join ', ')"
    Write-Host "Created:    $($script:Summary.DirectoriesCreated) directories"
    if ($DryRun) {
        Write-Host "Planned:    $($script:Summary.Planned) actions"
    }
    else {
        Write-Host "Copied:     $($script:Summary.Copied)"
        Write-Host "Overwritten:$($script:Summary.Overwritten)"
        Write-Host "Skipped:    $($script:Summary.Skipped)"
    }
    Write-Host ''
}

Write-Header
$selection = Resolve-Selection

Write-Info "Selected preset: $($selection.Preset)"
Write-Info "Agents to install: $(Format-ItemList -Items $selection.Agents)"
Write-Info "Skills to install: $(Format-ItemList -Items $selection.Skills)"
Write-Info "Knowledge templates: $($KnowledgeFiles -join ', ')"

Assert-SourcesExist -Selection $selection

Ensure-Directory -Path $CopilotRoot
Ensure-Directory -Path $AgentsTarget
Ensure-Directory -Path $SkillsTarget
Ensure-Directory -Path $KnowledgeTarget

foreach ($agent in $selection.Agents) {
    Install-Path -Source (Join-Path $AgentSourceRoot $agent) -Destination (Join-Path $AgentsTarget $agent) -Type File -Label "agent '$agent'"
}

foreach ($skill in $selection.Skills) {
    Install-Path -Source (Join-Path $SkillSourceRoot $skill) -Destination (Join-Path $SkillsTarget $skill) -Type Directory -Label "skill '$skill'"
}

foreach ($knowledgeFile in $KnowledgeFiles) {
    Install-Path -Source (Join-Path $KnowledgeSourceRoot $knowledgeFile) -Destination (Join-Path $KnowledgeTarget $knowledgeFile) -Type File -Label "knowledge template '$knowledgeFile'"
}

$valid = Validate-Installation -Selection $selection
Show-Summary -Selection $selection

if (-not $valid) {
    throw 'Installation validation failed.'
}

Write-Success 'Installer completed successfully.'

