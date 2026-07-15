[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$CodexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
$StatePath = Join-Path $CodexHome '.subagents_configs-state.json'

function Get-FileHashValue([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Write-AtomicBytes([string]$Path, [byte[]]$Bytes) {
    $directory = Split-Path -Parent $Path
    $temporary = Join-Path $directory ('.' + [IO.Path]::GetFileName($Path) + '.' + [Guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllBytes($temporary, $Bytes)
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    } finally {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
}

if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) {
    Write-Host 'No installer state; nothing removed safely.'
    exit 0
}
try { $state = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json }
catch { throw "Installer state is invalid JSON; nothing was removed. $($_.Exception.Message)" }

foreach ($property in $state.files.PSObject.Properties) {
    $item = $property.Value
    if (-not (Test-Path -LiteralPath $item.target -PathType Leaf) -or (Get-FileHashValue $item.target) -ne $item.installed_hash) {
        Write-Host "preserved modified/missing: $($item.target)"
    } elseif ($item.ownership -eq 'created') {
        Remove-Item -LiteralPath $item.target -Force
        Write-Host "removed: $($item.target)"
    } elseif ($item.ownership -eq 'replaced' -and $item.backup -and (Test-Path -LiteralPath $item.backup -PathType Leaf)) {
        Write-AtomicBytes $item.target ([IO.File]::ReadAllBytes($item.backup))
        Write-Host "restored: $($item.target)"
    } else {
        Write-Host "preserved pre-existing: $($item.target)"
    }
}

$global = $state.global
if ($null -ne $global -and $global.ownership -eq 'managed' -and (Test-Path -LiteralPath $global.target -PathType Leaf)) {
    $data = [IO.File]::ReadAllText($global.target)
    $position = $data.IndexOf($global.block, [StringComparison]::Ordinal)
    if ($position -ge 0) {
        $before = [Convert]::FromBase64String($global.before)
        $beforeText = [Text.Encoding]::UTF8.GetString($before)
        $original = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($global.original_segment))
        $expected = if ($beforeText.Contains('# BEGIN subagents_configs')) {
            $begin = $beforeText.IndexOf('# BEGIN subagents_configs', [StringComparison]::Ordinal)
            $end = $beforeText.IndexOf('# END subagents_configs', $begin, [StringComparison]::Ordinal) + '# END subagents_configs'.Length
            $beforeText.Substring(0, $begin) + $global.block + $beforeText.Substring($end)
        } else {
            $separator = if ($beforeText.Length -gt 0) { "`r`n`r`n" } else { '' }
            $beforeText + $separator + $global.block + "`r`n"
        }
        if ($data -eq $expected) {
            Write-AtomicBytes $global.target $before
        } else {
            $updated = $data.Substring(0, $position) + $original + $data.Substring($position + $global.block.Length)
            Write-AtomicBytes $global.target ([Text.UTF8Encoding]::new($false).GetBytes($updated))
        }
        Write-Host "removed exact managed block: $($global.target)"
    } else {
        Write-Host 'preserved AGENTS.md: managed block changed or missing'
    }
}

Remove-Item -LiteralPath $StatePath -Force
Write-Host "Codex subagents uninstalled from $CodexHome"
