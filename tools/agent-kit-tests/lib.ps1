# Helpers for the agent kit tests on Windows. A test file starts with:
#   . (Join-Path $env:ROOT 'tools/agent-kit-tests/lib.ps1')
$ErrorActionPreference = 'Stop'
$script:Exe = (Get-Process -Id $PID).Path
$script:KitPs1 = Join-Path $env:ROOT 'probes/agent/kit.ps1'
$script:T = Join-Path ([IO.Path]::GetTempPath()) ("kit-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $script:T | Out-Null
$script:Fail = 0

# Invoke-Kit ARGS: run the kit in a new process. Returns the exit code;
# the output is in $T\out.
# In Windows PowerShell 5.1, a line on stderr from a native command is an
# error record, and "Stop" makes it end the test. So the function uses
# "Continue".
function Invoke-Kit {
    $ErrorActionPreference = 'Continue'
    & $script:Exe -NoProfile -ExecutionPolicy Bypass -File $script:KitPs1 @args *> (Join-Path $script:T 'out')
    return $LASTEXITCODE
}
function Pass([string]$Name) { Write-Output "pass: $Name" }
function Fail([string]$Name, [string]$Why) { Write-Output "fail: ${Name}: $Why"; $script:Fail = 1 }
function Expect-Code([string]$Name, [int]$Want, [int]$Got) {
    if ($Want -eq $Got) { Pass $Name } else { Fail $Name "exit $Got, want $Want" }
}
function Expect-Line([string]$Name, [string]$Pattern, [string]$File) {
    if (Select-String -LiteralPath $File -Pattern $Pattern -Quiet) { Pass $Name } else { Fail $Name "no line matches: $Pattern" }
}
function Complete-Tests {
    Remove-Item -Recurse -Force -LiteralPath $script:T -ErrorAction SilentlyContinue
    exit $script:Fail
}
