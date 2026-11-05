# The test-session steps on Windows: the kinds permission, new-chat and
# interrupt, on the backend conpty or psmux. It is the twin of
# steps/session-step.sh. The files permission.ps1, new-chat.ps1 and
# interrupt.ps1 run this script. kit step runs them with the KIT_*
# variables of the step contract.
#
# The step, with the fields of the steps.tsv line KIT_STEP:
#   1. Start a test session ("kit session start") in a new work folder.
#      The home is the home of the run (KIT_HOME).
#   2. Answer the screens of "pre", each pair one time at most, and wait
#      for the idle screen: a line matches idle_regex, and no line matches
#      busy_regex or dialog_regex. The limit is 60 s.
#   3. Start the guided watch (probes\run.ps1 -Guided KIND AGENT) in the
#      background on the pids of the session, and wait for its line
#      "kit: watch starts".
#   4. Send the prompt and the send key: Enter, or the key of "send=KEY"
#      in the column "windows" (Codex: Tab).
#   5. Wait for wait_regex. The limit is 90 s. No match in the limit is
#      "ok no-dialog": the step keeps the last screen and sends no answer.
#   6. Send the answer keys, and keep the screen 2 s later.
#   7. Wait for the end of the watch, then stop the session. The watch
#      ends before the stop, so that its last snapshot sees the session
#      and its home.
# The output: the log of the step, the guided watch file, and the screens
# "idle", "dialog" and "after" (or "last" with no dialog).
# The watch takes AGENT_SIGNALS_WATCH seconds (default 30). The wait of
# step 5 takes AGENT_SIGNALS_STEP_WAIT seconds (default 90). The tests
# make both short. The step stops only the pids of its session.
# Exit codes: 0 ok, 1 fail, 3 a needed tool is missing.
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib.ps1')
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }

$run = $env:KIT_RUN
$out = $env:KIT_OUT
if (-not $run -or -not $out) { Stop-Kit 2 'run this script with kit step' }
$env:AGENT_SIGNALS_RUN = $run
$Utf8 = New-Object System.Text.UTF8Encoding $false
$exe = (Get-Process -Id $PID).Path
$sessionPs1 = Join-Path (Split-Path -Parent $PSScriptRoot) 'session.ps1'
$runPs1 = Join-Path $script:KitRoot 'probes\run.ps1'

$step = $null
foreach ($s in @(Read-KitSteps)) { if ($s.name -ceq $env:KIT_STEP) { $step = $s } }
if (-not $step) { Stop-Kit 2 "unknown step: $env:KIT_STEP" }
function Get-Field([string]$Name) {
    $v = ''
    if ($step.PSObject.Properties[$Name]) { $v = [string]$step.$Name }
    if ($v -eq '-') { $v = '' }
    return $v
}
$kind = [string]$step.kind
$agent = [string]$env:KIT_AGENT
$backend = [string]$env:KIT_BACKEND
$prompt = Get-Field 'prompt'
$waitRe = Get-Field 'wait_regex'
$answer = Get-Field 'answer'
$idleRe = Get-Field 'idle_regex'
$busyRe = Get-Field 'busy_regex'
$dialogRe = Get-Field 'dialog_regex'
$sendKey = 'Enter'
foreach ($kv in ((Get-Field 'windows') -split ';')) {
    if ($kv -match '^\s*send\s*=\s*(\S+)\s*$') { $sendKey = $Matches[1] }
}
$pre = @()
foreach ($p in ((Get-Field 'pre') -split ';;')) {
    $i = $p.IndexOf('=>')
    if ($i -gt 0) { $pre += New-Object PSObject -Property @{ Re = $p.Substring(0, $i); Keys = @($p.Substring($i + 2) -split ' ' | Where-Object { $_ }); Used = $false } }
}
function Get-Seconds([string]$Value, [int]$Default) {
    if ($Value -match '^[1-9][0-9]*$' -and [int]$Value -le 600) { return [int]$Value }
    return $Default
}
$watchS = Get-Seconds $env:AGENT_SIGNALS_WATCH 30
$waitS = Get-Seconds $env:AGENT_SIGNALS_STEP_WAIT 90

$log = New-Object System.Text.StringBuilder
$t0 = Get-Date
function Add-Log([string]$Text) { [void]$log.Append(('t={0:N1}s {1}' -f ((Get-Date) - $t0).TotalSeconds, $Text) + "`n") }
$screens = New-Object System.Collections.ArrayList
function Add-Screen([string]$Name, [string]$Text) { [void]$screens.Add(@($Name, $Text)) }
$watchText = ''

# Invoke-Session ARG...: run session.ps1 in a new process. It returns
# Code, Out and Err. The output is UTF-8.
function Invoke-Session([string[]]$List, [int]$Seconds = 60) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' + (Format-KitArg $sessionPs1) + ' ' + (($List | ForEach-Object { Format-KitArg $_ }) -join ' ')
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = $Utf8
    $psi.StandardErrorEncoding = $Utf8
    $p = [System.Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEndAsync()
    $e = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($Seconds * 1000)) {
        try { $p.Kill() } catch { }
        return [pscustomobject]@{ Code = -1; Out = ''; Err = "no exit in $Seconds s" }
    }
    $p.WaitForExit()
    return [pscustomobject]@{ Code = $p.ExitCode; Out = $o.Result; Err = $e.Result }
}

# Read-Shared FILE: the text of a file that another process still writes.
function Read-Shared([string]$File) {
    try {
        $fs = New-Object System.IO.FileStream($File, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        try { return (New-Object System.IO.StreamReader($fs, $Utf8)).ReadToEnd() } finally { $fs.Dispose() }
    } catch { return '' }
}

function Test-Line([string]$Screen, [string]$Re) {
    if (-not $Re) { return $false }
    foreach ($l in ($Screen -split "`r?`n")) { if ([regex]::IsMatch($l, $Re)) { return $true } }
    return $false
}
# The idle rule: a line matches idle_regex, and no line matches busy_regex
# or dialog_regex. With no idle_regex, a screen with text and no busy or
# dialog line is idle.
function Test-Idle([string]$Screen) {
    if ((Test-Line $Screen $busyRe) -or (Test-Line $Screen $dialogRe)) { return $false }
    if ($idleRe) { return (Test-Line $Screen $idleRe) }
    return [bool]$Screen.Trim()
}

$name = 'st-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
$started = $false
$code = 0
$reason = ''
$watch = $null
$lastScreen = ''
function Get-Screen {
    $r = Invoke-Session @('screen', $name) 30
    if ($r.Code -eq 0) { $script:lastScreen = $r.Out }
    return $script:lastScreen
}
function Send-Keys([string[]]$Keys) {
    foreach ($k in $Keys) {
        $r = Invoke-Session @('key', $name, $k) 30
        if ($r.Code -ne 0) { throw "key ${k}: $($r.Err.Trim())" }
    }
}

try {
    Add-Log "start: $agent on $backend, home $env:KIT_HOME"
    $r = Invoke-Session @('start', $name, $agent, '--via', $backend, '--home', $env:KIT_HOME) 120
    if ($r.Code -eq 3) {
        $code = 3
        $why = $r.Err.Trim()
        if ($why -match 'Python') { $reason = 'needs-conpty-python' } elseif ($why -match 'psmux') { $reason = 'needs-psmux' } else { $reason = 'not-installed' }
        Add-Log "skip: $why"
        return
    }
    if ($r.Code -ne 0) { $code = 1; $reason = 'no-session'; Add-Log "start failed: exit $($r.Code) $($r.Err.Trim())"; return }
    $started = $true
    $sdir = Join-Path (Join-Path $run 'sessions') $name
    Add-Log 'session started'

    # 2. The pre answers and the idle screen.
    $idle = $false
    $end = (Get-Date).AddSeconds(60)
    while ((Get-Date) -lt $end) {
        $sc = Get-Screen
        $hit = $null
        foreach ($p in $pre) { if (-not $p.Used -and (Test-Line $sc $p.Re)) { $hit = $p; break } }
        if ($hit) {
            $hit.Used = $true
            Add-Log "pre: $($hit.Re) => $($hit.Keys -join ' ')"
            Send-Keys $hit.Keys
            Start-Sleep -Milliseconds 800
            continue
        }
        if (Test-Idle $sc) { $idle = $true; break }
        Start-Sleep -Milliseconds 500
    }
    Add-Screen 'idle' $lastScreen
    if (-not $idle) { $code = 1; $reason = 'no-idle'; Add-Log 'no idle screen in 60 s'; return }
    Add-Log 'idle'

    # 3. The guided watch, in the background.
    $watchOut = "$out.watch"
    $argText = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' + (Format-KitArg $runPs1) +
        " -Guided $kind $agent -Wait $watchS -PidsFile " + (Format-KitArg (Join-Path $sdir 'pids')) + ' -Out ' + (Format-KitArg $watchOut)
    if ($env:KIT_HOME -eq 'throwaway') { $argText += ' -StateHome ' + (Format-KitArg (Join-Path (Join-Path $run 'home') $name)) }
    $watch = Start-KitProcess $run "watch $name" $exe $argText "$out.watch.console" "$out.watch.err" $run
    $end = (Get-Date).AddSeconds(60)
    $began = $false
    while ((Get-Date) -lt $end -and -not $watch.HasExited) {
        if ((Read-Shared "$out.watch.console") -match '(?m)^kit: watch starts, ') { $began = $true; break }
        Start-Sleep -Milliseconds 200
    }
    if (-not $began) {
        $code = 1; $reason = 'no-watch'
        Add-Log ('the watch did not start: ' + ((Read-Shared "$out.watch.console") + (Read-Shared "$out.watch.err")).Trim())
        return
    }
    Add-Log "watch starts, $watchS s"

    # 4. The prompt.
    if ($prompt) {
        $r = Invoke-Session @('send', $name, $prompt) 30
        if ($r.Code -ne 0) { throw "send: $($r.Err.Trim())" }
        Send-Keys @($sendKey)
        Add-Log "prompt sent, then $sendKey"
    }

    # 5. The wait for wait_regex. For new-chat, wait_regex is the idle
    # screen, so the idle rule counts.
    $got = $false
    if ($waitRe) {
        if ($kind -eq 'new-chat') { Start-Sleep -Seconds 2 }
        $end = (Get-Date).AddSeconds($waitS)
        while ((Get-Date) -lt $end) {
            $sc = Get-Screen
            if ($kind -eq 'new-chat') { $hitWait = (Test-Line $sc $waitRe) -and (Test-Idle $sc) } else { $hitWait = Test-Line $sc $waitRe }
            if ($hitWait) { $got = $true; break }
            Start-Sleep -Milliseconds 400
        }
    }
    if ($got) {
        Add-Screen 'dialog' $lastScreen
        Add-Log 'wait_regex matches'
        # 6. The answer.
        $keys = @($answer -split ' ' | Where-Object { $_ })
        foreach ($k in $keys) { Send-Keys @($k); Start-Sleep -Milliseconds 500 }
        if ($keys.Count -gt 0) { Add-Log "answer: $($keys -join ' ')" }
        Start-Sleep -Seconds 2
        Add-Screen 'after' (Get-Screen)
    } else {
        $reason = 'no-dialog'
        Add-Log "no match of wait_regex in $waitS s"
        Add-Screen 'last' (Get-Screen)
    }
} catch {
    $code = 1
    if (-not $reason) { $reason = 'error' }
    Add-Log "error: $_"
} finally {
    # 7. The end of the watch, then the stop.
    if ($watch) {
        $w = Wait-KitProcess $run $watch ($watchS + 120)
        Add-Log "watch ends: exit $($w.Code)"
        if ($w.Code -ne 0 -and $code -eq 0) { $code = 1; $reason = 'watch-failed' }
        $watchText = Read-KitText "$out.watch"
        if (-not $watchText) { $watchText = (Read-KitText "$out.watch.console") + (Read-KitText "$out.watch.err") }
        foreach ($x in "$out.watch", "$out.watch.console", "$out.watch.err") { Remove-Item -LiteralPath $x -Force -ErrorAction SilentlyContinue }
    }
    if ($started) {
        $r = Invoke-Session @('stop', $name) 120
        Add-Log "stop: exit $($r.Code)"
        foreach ($l in ($r.Out -split "`r?`n" | Where-Object { $_ -match '^stop: ' })) { Add-Log $l }
        if ($r.Code -ne 0 -and $code -eq 0) { $code = 1; $reason = 'no-stop' }
    }
    $result = 'ok'
    if ($code -eq 1) { $result = 'fail' } elseif ($code -eq 3) { $result = 'skip' }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("# agent-signals session step: $env:KIT_STEP@$backend`n")
    [void]$sb.Append("kind: $kind`nagent: $agent`nbackend: $backend`nhome: $env:KIT_HOME`nsend key: $sendKey`n")
    [void]$sb.Append(("result: $result $reason").TrimEnd() + "`n")
    [void]$sb.Append("### log`n" + $log.ToString())
    if ($watchText) { [void]$sb.Append("### guided watch`n" + $watchText.TrimEnd() + "`n") }
    foreach ($s in $screens) {
        [void]$sb.Append("### screen $($s[0])`n")
        $t = [string]$s[1]
        if ($t -and -not $t.EndsWith("`n")) { $t += "`n" }
        [void]$sb.Append($t)
    }
    Write-KitText $out $sb.ToString()
    if ($reason) { Write-KitText "$out.reason" "$reason`n" }
    # The exit is here: a "return" in the try block ends the script after
    # this block.
    exit $code
}
