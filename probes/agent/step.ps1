# kit step on Windows: run one step of the plan.
#
#   kit step NAME@BACKEND [ARGUMENTS]
#
# It reads the line NAME of probes\agent\steps.tsv and runs
# probes\agent\steps\<kind>.ps1 in a new PowerShell process, with the
# KIT_* variables of the step contract (KIT_RUN, KIT_ROOT, KIT_STEP,
# KIT_KIND, KIT_AGENT, KIT_BACKEND, KIT_PROMPT, KIT_ARGS, KIT_WAIT_REGEX, KIT_ANSWER,
# KIT_HOME, KIT_OUT). The ARGUMENTS go to the script. The script writes its
# output to KIT_OUT, and one line of reason to KIT_OUT.reason.
# The step then sends the output through tools\scrub.ps1 into
# NN-NAME@BACKEND.txt in the run folder, deletes KIT_OUT, appends a line
# to manifest.tsv:
#   step <name> <backend> <result> <start> <end> <file> <sha256>
# and prints:
#   step: <name>@<backend> ok|skip|fail|operator [<reason>]
# The exit code is the exit code of the script: 0 ok, 1 fail, 3 skip,
# 4 the operator must act. A skip of the plan (no-login, needs-fixture,
# no-fixture, by-operator, unattended) exits 0, as in step.sh. A call while another "kit step" of the same
# run runs is bad use (2). A run folder from another kit version is bad
# use (2). It reads no key.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')
# The arguments as strings (see Get-KitArgs in lib.ps1).
[string[]]$argv = @(Get-KitArgs $args)

$nm = $null
if ($argv.Count -gt 0) { $nm = [regex]::Match([string]$argv[0], '^([a-z0-9][a-z0-9-]*)@([a-z]+)$') }
if (-not $nm -or -not $nm.Success) { Stop-Kit 2 "usage: kit step NAME@BACKEND [ARGUMENTS] (got $($argv.Count) arguments)" }
$name = $nm.Groups[1].Value
$backend = $nm.Groups[2].Value
$extra = @()
if ($argv.Count -gt 1) { $extra = @($argv[1..($argv.Count - 1)] | ForEach-Object { [string]$_ }) }

$step = $null
foreach ($s in @(Read-KitSteps)) { if ($s.name -ceq $name) { $step = $s } }
if (-not $step) { Stop-Kit 2 "unknown step: $name" }
$run = Get-KitRunDir
# A run holds the steps of one kit version. A new kit in the same folder
# finds the run of the old kit from .agent-signals-run.
$made = [string](Get-KitMeta $run 'kit')
$kitVersion = [string](Get-KitVersion)
if ($made -and $made -ne $kitVersion) {
    Stop-Kit 2 "the run folder is from kit $made, and this kit is $kitVersion. Run 'kit start' for a new run"
}
$homeMode = Get-KitMeta $run 'home'
if (-not $homeMode) { $homeMode = 'real' }
$unattended = Get-KitMeta $run 'unattended'
$skipped = @(Get-KitMetaAll $run 'skip_agent')

$backends = @(Get-KitStepBackends $step)
if ($backends -notcontains $backend) {
    Stop-Kit 2 ("the step $name has no Windows backend $backend; it has: " + (($backends | ForEach-Object { $_ }) -join ', '))
}
$env:KIT_RUN = $run

# One step at a time in a run. Two "kit step" calls at the same time take
# the same file number and the same session name, and each one breaks the
# session of the other. The lock is the file RUN\.step.lock, open with no
# sharing while this process runs. Windows closes it when the process ends,
# also after a kill.
$lockPath = Join-Path $run '.step.lock'
try {
    $stepLock = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
} catch {
    # PowerShell wraps the IOException of a .NET call; a plain catch gets it.
    Stop-Kit 2 "another kit step runs in this run ($($_.Exception.InnerException.Message)). Wait until it ends, then run $name@$backend again"
}
# RUN\.step.script holds the pid of the step script. After a kill of "kit
# step" only, Windows frees the lock, but the script runs on until it sees
# the end of "kit step" and stops its session. Until then, a step waits.
$scriptPidPath = Join-Path $run '.step.script'
$old = ([string](Read-KitText $scriptPidPath)).Trim()
if ($old -match '^\d+$') {
    $op = Get-Process -Id ([int]$old) -ErrorAction SilentlyContinue
    if ($op -and $op.ProcessName -in 'pwsh', 'powershell') {
        $stepLock.Dispose()
        Stop-Kit 2 "the script of an ended kit step still runs (pid $old). Wait until it ends, then run $name@$backend again"
    }
}

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
# All raw files of the step start with "$base.": KIT_OUT, KIT_OUT.reason,
# the console files and the work folders of the step script.
$kitOut = Join-Path $raw "$base.out"
$start = Get-KitIsoTime
$code = 3
$reason = ''
# A skip of the plan (no-login, needs-fixture, no-fixture, by-operator,
# unattended) exits 0, as in step.sh. A missing tool exits 3.
$planSkip = $false
$console = ''

$p = $null
try {
    if (-not (Test-KitStepRuns $step $backend)) {
        $reason = 'not-on-windows'
    } elseif (Get-KitLoginSkip $homeMode $step.needs $step.agent) {
        $reason = Get-KitLoginSkip $homeMode $step.needs $step.agent
        $planSkip = $true
    } elseif (Get-KitOperatorSkip $skipped $step.agent) {
        $reason = Get-KitOperatorSkip $skipped $step.agent
        $planSkip = $true
    } elseif (Get-KitUnattendedSkip $unattended $step.needs $backend) {
        $reason = Get-KitUnattendedSkip $unattended $step.needs $backend
        $planSkip = $true
    } else {
        $scriptFile = Join-Path $PSScriptRoot ("steps\{0}.ps1" -f $step.kind)
        if (-not (Test-Path -LiteralPath $scriptFile -PathType Leaf)) { Stop-Kit 1 "no script for the kind $($step.kind)" }
        $env:KIT_ROOT = $script:KitRoot
        $env:KIT_STEP = $name
        $env:KIT_KIND = [string]$step.kind
        $env:KIT_AGENT = [string]$step.agent
        $env:KIT_BACKEND = $backend
        $env:KIT_PROMPT = [string]$step.prompt
        $env:KIT_ARGS = if ($step.PSObject.Properties['args'] -and [string]$step.args -ne '-') { [string]$step.args } else { '' }
        $env:KIT_WAIT_REGEX = [string]$step.wait_regex
        $env:KIT_ANSWER = [string]$step.answer
        $env:KIT_HOME = $homeMode
        $env:KIT_OUT = $kitOut
        # The script ends itself when this process is gone.
        $env:KIT_STEP_PID = [string]$PID
        $exe = (Get-Process -Id $PID).Path
        $argText = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' + (Format-KitArg $scriptFile)
        foreach ($x in $extra) { $argText += ' ' + (Format-KitArg $x) }
        $p = Start-KitProcess $run "step $name@$backend" $exe $argText "$kitOut.console" "$kitOut.err" $run
        Write-KitText $scriptPidPath ([string]$p.Id + "`n")
        $w = Wait-KitProcess $run $p 1800
        $code = $w.Code
        if ($w.TimedOut) { $code = 1; $reason = 'time-limit' }
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
    $why = if ($reason) { $reason } else { '-' }
    Add-KitManifest $run @('step', $name, $backend, $result, $start, (Get-KitIsoTime), "$base.txt", (Get-KitSha256 $file), $why)
} finally {
    # A script that did not stop at the time limit keeps its marker: the
    # next step refuses to start while that process runs.
    if (-not $p -or $p.HasExited) {
        Remove-Item -LiteralPath $scriptPidPath -Force -ErrorAction SilentlyContinue
    }
    $stepLock.Dispose()
    Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
    # Delete the raw files of this step, also after an error.
    foreach ($x in @(Get-ChildItem -LiteralPath $raw -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name.StartsWith("$base.") })) {
        Remove-Item -LiteralPath $x.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (@(Get-ChildItem -LiteralPath $raw -Force -ErrorAction SilentlyContinue).Count -eq 0) {
        Remove-Item -LiteralPath $raw -Force -ErrorAction SilentlyContinue
    }
}
Write-Output ("step: $name@$backend $result $reason".TrimEnd())
if ($planSkip) { exit 0 }
exit $code
