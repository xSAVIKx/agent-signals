# scenarios\kit-login.ps1: the login step of one agent in CI. The test uses
# a fake profile with no agent, so it holds no real key and starts no agent.
. (Join-Path $env:ROOT 'tools/agent-kit-tests/lib.ps1')

$script1 = Join-Path $env:ROOT 'scenarios\kit-login.ps1'
$fake = Join-Path $script:T 'profile'
$temp = Join-Path $script:T 'runner'
New-Item -ItemType Directory -Path $fake, $temp | Out-Null
$failed = Join-Path $temp 'kit-failed.txt'
$out = Join-Path $script:T 'out'

# Invoke-Login KEY AGENT: run the script with the fake profile and a PATH
# that holds no agent, and return its exit code.
function Invoke-Login([string]$Key, [string]$Name) {
    $ErrorActionPreference = 'Continue'
    $saved = @{}
    foreach ($v in 'USERPROFILE', 'LOCALAPPDATA', 'RUNNER_TEMP', 'KIT_KEY', 'PATH') { $saved[$v] = [Environment]::GetEnvironmentVariable($v) }
    $env:USERPROFILE = $fake
    $env:LOCALAPPDATA = $fake
    $env:RUNNER_TEMP = $temp
    $env:KIT_KEY = $Key
    $env:PATH = Join-Path $env:SystemRoot 'System32'
    & $script:Exe -NoProfile -ExecutionPolicy Bypass -File $script1 run $Name *> $out
    $rc = $LASTEXITCODE
    foreach ($v in $saved.Keys) { [Environment]::SetEnvironmentVariable($v, $saved[$v]) }
    return $rc
}

Expect-Code 'an agent that is not installed exits 0' 0 (Invoke-Login 'FAKE-LOGIN-KEY-0123456789' 'claude')
Expect-Line 'an agent with a key and no step is in the list' '^claude: ' $failed
Remove-Item -LiteralPath $failed

Expect-Code 'a cursor with no command exits 0' 0 (Invoke-Login 'FAKE-LOGIN-KEY-0123456789' 'cursor')
Expect-Line 'no wrapper prints a skip line' '^skip: no cursor-agent' $out
Expect-Line 'a cursor with no command is in the list' '^cursor: ' $failed
Remove-Item -LiteralPath $failed

Expect-Code 'a step with no key exits 0' 0 (Invoke-Login '' 'codex')
Expect-Line 'a step with no key is in the list' '^codex: ' $failed

$left = @(Get-ChildItem -LiteralPath $fake -Recurse -File -Force -ErrorAction SilentlyContinue | Select-String -SimpleMatch 'FAKE-LOGIN-KEY')
if ($left.Count -eq 0) { Pass 'no file holds the key' } else { Fail 'no file holds the key' 'a file holds it' }

Complete-Tests
