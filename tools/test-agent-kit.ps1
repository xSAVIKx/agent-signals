# Runs the tests of the agent kit on Windows: each file
# tools/agent-kit-tests/test-*.ps1, in the PowerShell that runs this file.
# A test file writes "pass: <name>" or "fail: <name>: <reason>" for each
# case and exits 1 when a case fails.
# Run: pwsh -NoProfile -File tools/test-agent-kit.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$exe = (Get-Process -Id $PID).Path
$fail = 0
foreach ($t in Get-ChildItem -Path (Join-Path $root 'tools/agent-kit-tests') -Filter 'test-*.ps1') {
    Write-Output "== $($t.Name)"
    $env:ROOT = $root
    & $exe -NoProfile -ExecutionPolicy Bypass -File $t.FullName
    if ($LASTEXITCODE -ne 0) { $fail = 1 }
}
exit $fail
