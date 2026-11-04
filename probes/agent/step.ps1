# kit step on Windows: run one step of the plan.
#
#   kit step NAME@BACKEND [ARGUMENTS]
#
# It reads the line NAME of probes\agent\steps.tsv and runs
# probes\agent\steps\<kind>.ps1 in a new PowerShell process, with the
# KIT_* variables of the step contract (KIT_RUN, KIT_ROOT, KIT_STEP,
# KIT_KIND, KIT_AGENT, KIT_BACKEND, KIT_PROMPT, KIT_WAIT_REGEX, KIT_ANSWER,
# KIT_HOME, KIT_OUT). The ARGUMENTS go to the script. The script writes its
# output to KIT_OUT, and one line of reason to KIT_OUT.reason.
# The step then sends the output through tools\scrub.ps1 into
# NN-NAME@BACKEND.txt in the run folder, deletes KIT_OUT, appends a line
# to manifest.tsv:
#   step <name> <backend> <result> <start> <end> <file> <sha256>
# and prints:
#   step: <name>@<backend> ok|skip|fail|operator [<reason>]
# The exit code is the exit code of the script: 0 ok, 1 fail, 3 skip,
# 4 the operator must act. It reads no key.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')
# kit.ps1 can pass one $null for no arguments.
$argv = @($args | Where-Object { $null -ne $_ })

$nm = $null
if ($argv.Count -gt 0) { $nm = [regex]::Match([string]$argv[0], '^([a-z0-9][a-z0-9-]*)@([a-z]+)$') }
if (-not $nm -or -not $nm.Success) { Stop-Kit 2 'usage: kit step NAME@BACKEND [ARGUMENTS]' }
$name = $nm.Groups[1].Value
$backend = $nm.Groups[2].Value
$extra = @()
if ($argv.Count -gt 1) { $extra = @($argv[1..($argv.Count - 1)] | ForEach-Object { [string]$_ }) }

$step = $null
foreach ($s in @(Read-KitSteps)) { if ($s.name -ceq $name) { $step = $s } }
if (-not $step) { Stop-Kit 2 "unknown step: $name" }
$run = Get-KitRunDir
$homeMode = Get-KitMeta $run 'home'
if (-not $homeMode) { $homeMode = 'real' }

$want = Get-KitWindowsBackend $step
if ($want -and $want -ne $backend) { Stop-Kit 2 "the step $name runs on $want on Windows, not on $backend" }

# The number of the file: one more than the highest number in the manifest.
$n = 0
foreach ($f in @(Read-KitManifest $run)) {
    if ($f.Count -ge 7 -and $f[0] -eq 'step' -and $f[6] -match '^([0-9]+)-') {
        if ([int]$Matches[1] -gt $n) { $n = [int]$Matches[1] }
    }
}
$base = '{0:D2}-{1}@{2}' -f ($n + 1), $name, $backend
$file = Join-Path $run "$base.txt"
$raw = Join-Path $run '.raw'
New-Item -ItemType Directory -Force -Path $raw | Out-Null
$kitOut = Join-Path $raw "$base.out"
$start = Get-KitTime
$code = 3
$reason = ''
$console = ''

if (-not $want) {
    $reason = 'not-on-windows'
} elseif ($homeMode -eq 'throwaway' -and $step.needs -eq 'login') {
    $reason = 'no-login'
} else {
    $scriptFile = Join-Path $PSScriptRoot ("steps\{0}.ps1" -f $step.kind)
    if (-not (Test-Path -LiteralPath $scriptFile -PathType Leaf)) { Stop-Kit 1 "no script for the kind $($step.kind)" }
    $env:KIT_RUN = $run
    $env:KIT_ROOT = $script:KitRoot
    $env:KIT_STEP = $name
    $env:KIT_KIND = [string]$step.kind
    $env:KIT_AGENT = [string]$step.agent
    $env:KIT_BACKEND = $backend
    $env:KIT_PROMPT = [string]$step.prompt
    $env:KIT_WAIT_REGEX = [string]$step.wait_regex
    $env:KIT_ANSWER = [string]$step.answer
    $env:KIT_HOME = $homeMode
    $env:KIT_OUT = $kitOut
    $exe = (Get-Process -Id $PID).Path
    $argText = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' + (Format-KitArg $scriptFile)
    foreach ($x in $extra) { $argText += ' ' + (Format-KitArg $x) }
    $p = Start-KitProcess $run "step $name@$backend" $exe $argText "$kitOut.console" "$kitOut.err" $run
    $code = Wait-KitProcess $run $p 1800
    if ($code -eq -1) { $code = 1; $reason = 'time-limit' }
    $r = (Read-KitText "$kitOut.reason") -split "`r?`n" | Where-Object { $_ } | Select-Object -First 1
    if ($r -and -not $reason) { $reason = [string]$r }
    $console = (Read-KitText "$kitOut.console") + (Read-KitText "$kitOut.err")
}

switch ($code) {
    0 { $result = 'ok' }
    3 { $result = 'skip' }
    4 { $result = 'operator' }
    default { $result = 'fail'; $code = 1 }
}
$text = Read-KitText $kitOut
if ($console.Trim()) {
    if ($text -and -not $text.EndsWith("`n")) { $text += "`n" }
    $text += "### console`n" + $console
}
if (-not $text.Trim()) { $text = "result: $result $reason".TrimEnd() + "`n" }
Write-KitText $file (ConvertTo-KitScrubbed $text)
foreach ($x in @($kitOut, "$kitOut.reason", "$kitOut.console", "$kitOut.err")) {
    Remove-Item -LiteralPath $x -Force -ErrorAction SilentlyContinue
}
if (@(Get-ChildItem -LiteralPath $raw -Force).Count -eq 0) { Remove-Item -LiteralPath $raw -Force }
Add-KitManifest $run @('step', $name, $backend, $result, $start, (Get-KitTime), "$base.txt", (Get-KitSha256 $file))
Write-Output ("step: $name@$backend $result $reason".TrimEnd())
exit $code
