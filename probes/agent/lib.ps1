# Shared functions of the agent kit on Windows. Dot-source it:
#   . (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'lib.ps1')
# It must run in Windows PowerShell 5.1 and in PowerShell 7.

$script:KitDir = Split-Path -Parent $PSCommandPath
$script:KitRoot = Split-Path -Parent (Split-Path -Parent $script:KitDir)

# Stop-Kit CODE TEXT: write "kit: TEXT" on stderr and exit with CODE.
function Stop-Kit([int]$Code, [string]$Text) {
    [Console]::Error.WriteLine("kit: $Text")
    exit $Code
}

# Get-KitVersion: the version from the release manifest, or "dev".
function Get-KitVersion {
    $m = Join-Path $script:KitRoot '.release-please-manifest.json'
    if (Test-Path -LiteralPath $m) {
        $j = Get-Content -Raw -LiteralPath $m | ConvertFrom-Json
        $v = $j.'.'
        if ($v) { return [string]$v }
    }
    return 'dev'
}

# Get-KitRunDir: the path of the current run folder, from
# $env:AGENT_SIGNALS_RUN or the file .agent-signals-run in the current
# folder. With no run, it exits 2.
function Get-KitRunDir {
    $r = $env:AGENT_SIGNALS_RUN
    if (-not $r -and (Test-Path -LiteralPath '.agent-signals-run')) {
        $r = (Get-Content -LiteralPath '.agent-signals-run' -TotalCount 1)
    }
    if (-not $r) { Stop-Kit 2 "no run: do 'kit start' first" }
    if (-not (Test-Path -LiteralPath $r -PathType Container)) { Stop-Kit 2 "the run folder does not exist: $r" }
    return $r
}

# Add-KitPid RUN PID LABEL: record a pid that the kit started. The kit
# stops only the pids in RUN\pids\, never a process found by its name.
function Add-KitPid([string]$Run, [int]$ProcessId, [string]$Label) {
    $d = Join-Path $Run 'pids'
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    Set-Content -LiteralPath (Join-Path $d "$ProcessId") -Value $Label
}
