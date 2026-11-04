# The agent kit on Windows: the same commands, files and exit codes as
# probes/agent/kit.sh. Read docs/design/2026-11-01-agent-run-kit.md.
#
#   pwsh -NoProfile -File probes/agent/kit.ps1 <command> [arguments]
#
# Each command is the file probes/agent/<command>.ps1. Exit codes: 0 ok,
# 1 fail, 2 bad use, 3 a needed tool is missing, 4 the operator must act.
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'lib.ps1')

$cmd = if ($args.Count -gt 0) { [string]$args[0] } else { '' }
$rest = if ($args.Count -gt 1) { $args[1..($args.Count - 1)] } else { @() }

if ($cmd -in '', '-h', '--help', 'help') {
    Write-Output 'usage: kit <command> [arguments]'
    Write-Output 'commands:'
    Get-ChildItem -Path $here -Filter '*.ps1' | ForEach-Object {
        $n = $_.BaseName
        if ($n -notin 'kit', 'lib') { Write-Output "  $n" }
    }
    if ($cmd -eq '') { exit 2 }
    exit 0
}
if ($cmd -eq 'version') { Write-Output (Get-KitVersion); exit 0 }
if ($cmd -cnotmatch '^[a-z-]+$') { Stop-Kit 2 "unknown command: $cmd" }
$file = Join-Path $here "$cmd.ps1"
if (-not (Test-Path -LiteralPath $file)) { Stop-Kit 2 "unknown command: $cmd" }
& $file @rest
exit $LASTEXITCODE
