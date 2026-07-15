[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$CodexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
$AgentsDir = Join-Path $CodexHome 'agents'
$RoutingPath = Join-Path $CodexHome 'SUBAGENT_ROUTING.md'
$AgentsPath = Join-Path $CodexHome 'AGENTS.md'
$StatePath = Join-Path $CodexHome '.subagents_configs-state.json'
$Begin = '# BEGIN subagents_configs'
$End = '# END subagents_configs'

function Get-FileHashValue([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function New-Backup([string]$Path) {
    $stamp = Get-Date -Format 'yyyyMMddHHmmss'
    $candidate = "$Path.subagents_configs.bak-$stamp"
    $index = 1
    while (Test-Path -LiteralPath $candidate) {
        $candidate = "$Path.subagents_configs.bak-$stamp-$index"
        $index++
    }
    Copy-Item -LiteralPath $Path -Destination $candidate
    Write-Host "backup: $candidate"
    $candidate
}

function Write-AtomicBytes([string]$Path, [byte[]]$Bytes) {
    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    $temporary = Join-Path $directory ('.' + [IO.Path]::GetFileName($Path) + '.' + [Guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllBytes($temporary, $Bytes)
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    } finally {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
}

function Get-PriorFile([object]$State, [string]$Key) {
    if ($null -eq $State -or $null -eq $State.files) { return $null }
    $property = $State.files.PSObject.Properties[$Key]
    if ($null -eq $property) { return $null }
    $property.Value
}

$agentSources = @(Get-ChildItem -LiteralPath (Join-Path $ScriptRoot 'agents') -Filter '*.toml' -File | Sort-Object Name)
$routingSource = Join-Path $ScriptRoot 'rules\SUBAGENT_ROUTING.md'
if ($agentSources.Count -eq 0 -or -not (Test-Path -LiteralPath $routingSource -PathType Leaf)) {
    throw 'Required agent definitions or routing policy are missing; no files were changed.'
}
foreach ($source in $agentSources) {
    if ($source.Length -eq 0) { throw "Agent definition is empty: $($source.FullName); no files were changed." }
}

$oldState = $null
if (Test-Path -LiteralPath $StatePath -PathType Leaf) {
    try { $oldState = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json }
    catch { throw "Installer state is invalid JSON; no files were changed. $($_.Exception.Message)" }
}

New-Item -ItemType Directory -Force -Path $CodexHome, $AgentsDir | Out-Null
$currentFiles = [ordered]@{}

function Install-ManagedFile([string]$Source, [string]$Target, [string]$Key) {
    $sourceHash = Get-FileHashValue $Source
    $prior = Get-PriorFile $oldState $Key
    $ownership = 'created'
    $backup = $null

    if (Test-Path -LiteralPath $Target -PathType Leaf) {
        $targetHash = Get-FileHashValue $Target
        if ($targetHash -eq $sourceHash) {
            $ownership = if ($null -ne $prior) { $prior.ownership } else { 'preexisting' }
            if ($null -ne $prior) { $backup = $prior.backup }
            Write-Host "unchanged: $Target"
        } elseif ($null -ne $prior -and $targetHash -eq $prior.installed_hash -and $prior.ownership -in @('created', 'replaced')) {
            $ownership = $prior.ownership
            $backup = $prior.backup
            Write-AtomicBytes $Target ([IO.File]::ReadAllBytes($Source))
            Write-Host "updated managed: $Target"
        } else {
            $ownership = 'replaced'
            $backup = New-Backup $Target
            Write-AtomicBytes $Target ([IO.File]::ReadAllBytes($Source))
            Write-Host "installed: $Target"
        }
    } elseif (Test-Path -LiteralPath $Target) {
        throw "Target exists but is not a file: $Target"
    } else {
        Write-AtomicBytes $Target ([IO.File]::ReadAllBytes($Source))
        Write-Host "installed: $Target"
    }

    $currentFiles[$Key] = [ordered]@{
        target = $Target; installed_hash = $sourceHash; ownership = $ownership; backup = $backup
    }
}

foreach ($source in $agentSources) {
    Install-ManagedFile $source.FullName (Join-Path $AgentsDir $source.Name) ("agents/" + $source.Name)
}
Install-ManagedFile $routingSource $RoutingPath 'routing'

$block = "$Begin`r`n@$RoutingPath`r`n$End"
$oldAgentsBytes = if (Test-Path -LiteralPath $AgentsPath -PathType Leaf) { [IO.File]::ReadAllBytes($AgentsPath) } else { [byte[]]@() }
$oldAgents = [Text.Encoding]::UTF8.GetString($oldAgentsBytes)
$start = $oldAgents.IndexOf($Begin, [StringComparison]::Ordinal)
$originalSegment = ''
if ($start -ge 0) {
    $finish = $oldAgents.IndexOf($End, $start, [StringComparison]::Ordinal)
    if ($finish -lt 0) { throw "AGENTS.md contains an unterminated managed block: $AgentsPath" }
    $finish += $End.Length
    $originalSegment = $oldAgents.Substring($start, $finish - $start)
    $updatedAgents = $oldAgents.Substring(0, $start) + $block + $oldAgents.Substring($finish)
} else {
    $separator = if ($oldAgents.Length -gt 0) { "`r`n`r`n" } else { '' }
    $updatedAgents = $oldAgents + $separator + $block + "`r`n"
}

$globalRecord = [ordered]@{
    target = $AgentsPath
    block = $block
    before = [Convert]::ToBase64String($oldAgentsBytes)
    original_segment = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($originalSegment))
    ownership = 'unchanged'
    backup = $null
}
if ($updatedAgents -ne $oldAgents) {
    $globalRecord.ownership = 'managed'
    if (Test-Path -LiteralPath $AgentsPath -PathType Leaf) { $globalRecord.backup = New-Backup $AgentsPath }
    Write-AtomicBytes $AgentsPath ([Text.UTF8Encoding]::new($false).GetBytes($updatedAgents))
    Write-Host "updated: $AgentsPath"
} elseif ($null -ne $oldState -and $null -ne $oldState.global) {
    $globalRecord = $oldState.global
}

$state = [ordered]@{ files = $currentFiles; global = $globalRecord; platform = 'windows-powershell' }
$stateJson = ($state | ConvertTo-Json -Depth 8) + "`n"
Write-AtomicBytes $StatePath ([Text.UTF8Encoding]::new($false).GetBytes($stateJson))
Write-Host "Codex subagents installed under $CodexHome"
Write-Host 'config.toml was not modified; current Codex releases enable multi-agent support by default.'
