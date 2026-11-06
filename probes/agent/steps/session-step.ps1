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
#      background on the pids of the session, for WAIT + WATCH seconds,
#      and wait for its line "kit: watch starts". The watch shows only the
#      work folder, the project folder of the work folder, a throwaway
#      home, and the session files of the session.
#   4. Send the prompt and the send key: Enter, or the key of "send=KEY"
#      in the column "windows". A prompt that starts with "/" always gets
#      Enter. Codex on Windows is not measured: the Tab comes from a
#      report.
#   5. Wait for wait_regex. The limit is WAIT seconds.
#      permission  No match is "ok no-dialog": the step keeps the last
#                  screen and sends no answer. After a match, the step
#                  holds the answer for WATCH seconds, so that the watch
#                  covers the dialog.
#      new-chat    A match needs the idle rule, and the prompt text must
#                  have left the screen. No match is "fail no-idle".
#      interrupt   No match is "fail no-busy".
#      A match after the end of the watch has the reason "late-match".
#   6. Send the answer keys, and keep the screen 2 s later.
#   7. Wait for the end of the watch, then stop the session. The watch
#      ends before the stop, so that its last snapshot sees the session
#      and its home.
# An empty wait_regex (the Cursor lines) is "skip unmeasured". A failed
# screen read is "fail no-screen": the step does not use an old screen.
# The output: the log of the step, the guided watch file, and the screens.
# The welcome box of a Claude screen is blank in the file.
#
# WATCH is AGENT_SIGNALS_WATCH (default 30). WAIT is
# AGENT_SIGNALS_STEP_WAIT (default 90). One deadline holds for the whole
# step: AGENT_SIGNALS_STEP_LIMIT (default 220 s). Each call gets the time
# that is left, and the stop has 30 s of its own. The tests make all of
# them short. The step stops only the pids of its session.
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
if ($prompt.StartsWith('/')) { $sendKey = 'Enter' }
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
$limitS = Get-Seconds $env:AGENT_SIGNALS_STEP_LIMIT 220

$log = New-Object System.Text.StringBuilder
$t0 = Get-Date
$deadline = $t0.AddSeconds($limitS)
function Add-Log([string]$Text) { [void]$log.Append(('t={0:N1}s {1}' -f ((Get-Date) - $t0).TotalSeconds, $Text) + "`n") }
$screens = New-Object System.Collections.ArrayList
function Add-Screen([string]$Name, [string]$Text) {
    if ($agent -eq 'claude') { $Text = Clear-KitWelcomeBox $Text }
    [void]$screens.Add(@($Name, $Text))
}
$watchText = ''

# Get-Left: the seconds that are left, without the 30 s of the stop.
function Get-Left { return [int][math]::Floor(($deadline - (Get-Date)).TotalSeconds) - 30 }
# Get-Call SECONDS: SECONDS, or the time that is left when it is shorter.
function Get-Call([int]$Seconds) {
    $l = Get-Left
    if ($l -lt 1) { throw 'time-limit' }
    return [math]::Min($Seconds, $l)
}

# Invoke-Session ARGS SECONDS: run session.ps1 in a new process. It returns
# Code, Out and Err. The output is UTF-8.
function Invoke-Session([string[]]$List, [int]$Seconds) {
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
$sdir = Join-Path (Join-Path $run 'sessions') $name
$code = 0
$reason = ''
$watch = $null
$watchEnd = $null
# Get-Screen: the screen now. A failed read stops the step.
function Get-Screen {
    $r = Invoke-Session @('screen', $name) (Get-Call 30)
    if ($r.Code -ne 0) {
        $script:reason = 'no-screen'
        throw "screen: exit $($r.Code) $($r.Err.Trim())"
    }
    return $r.Out
}
function Send-Keys([string[]]$Keys) {
    foreach ($k in $Keys) {
        $r = Invoke-Session @('key', $name, $k) (Get-Call 30)
        if ($r.Code -ne 0) { throw "key ${k}: $($r.Err.Trim())" }
    }
}

try {
    if (-not $waitRe) {
        $code = 3; $reason = 'unmeasured'
        Add-Log 'skip: this step has no wait_regex, so the kit has no measured screen to wait for'
        return
    }
    if ($backend -eq 'conpty' -and -not (Test-Path -LiteralPath (Join-Path $script:KitRoot 'scenarios\conpty.py') -PathType Leaf)) {
        $code = 3; $reason = 'needs-scenario'
        Add-Log 'skip: the kit has no scenarios\conpty.py'
        return
    }
    if ($agent -eq 'codex') { Add-Log 'not measured: Codex on Windows. The Tab send key comes from a report.' }
    Add-Log "start: $agent on $backend, home $env:KIT_HOME"
    $r = Invoke-Session @('start', $name, $agent, '--via', $backend, '--home', $env:KIT_HOME) (Get-Call 120)
    if ($r.Code -eq 3) {
        $code = 3
        $why = $r.Err.Trim()
        if ($why -match 'Python') { $reason = 'needs-conpty-python' } elseif ($why -match 'psmux') { $reason = 'needs-psmux' } else { $reason = 'not-installed' }
        Add-Log "skip: $why"
        return
    }
    if ($r.Code -ne 0) { $code = 1; $reason = 'no-session'; Add-Log "start failed: exit $($r.Code) $($r.Err.Trim())"; return }
    Add-Log 'session started'

    # 2. The pre answers and the idle screen.
    $idle = $false
    $sc = ''
    $end = (Get-Date).AddSeconds((Get-Call 60))
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
    Add-Screen 'idle' $sc
    if (-not $idle) { $code = 1; $reason = 'no-idle'; Add-Log 'no idle screen in the limit'; return }
    Add-Log 'idle'

    # 3. The guided watch, in the background. Claude names a project folder
    # by the path with each character that is not a letter or a digit
    # changed to "-". The folder can appear after the first prompt.
    $work = (Read-KitText (Join-Path $sdir 'work')).Trim()
    $stateHome = $env:USERPROFILE
    $scope = @($work)
    if ($env:KIT_HOME -eq 'throwaway') {
        $stateHome = Join-Path (Join-Path $run 'home') $name
        $scope += $stateHome
    }
    $key = $work -replace '[^A-Za-z0-9]', '-'
    $scope += Join-Path $stateHome ".claude\projects\$key"
    $scope += Join-Path $stateHome (".cursor\projects\" + (($work -replace '[^A-Za-z0-9]+', '-').Trim('-')))
    $watchLen = [math]::Min($waitS + $watchS, (Get-Left) - 2)
    if ($watchLen -lt 1) { throw 'time-limit' }
    $watchOut = "$out.watch"
    $argText = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' + (Format-KitArg $runPs1) +
        " -Guided $kind $agent -Wait $watchLen -PidsFile " + (Format-KitArg (Join-Path $sdir 'pids')) +
        ' -StateHome ' + (Format-KitArg $stateHome) + ' -Scope ' + (Format-KitArg ($scope -join '|')) + ' -Out ' + (Format-KitArg $watchOut)
    $watch = Start-KitProcess $run "watch $name" $exe $argText "$out.watch.console" "$out.watch.err" $run
    $end = (Get-Date).AddSeconds((Get-Call 60))
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
    $watchEnd = (Get-Date).AddSeconds($watchLen)
    Add-Log "watch starts, $watchLen s"

    # 4. The prompt.
    if ($prompt) {
        $r = Invoke-Session @('send', $name, $prompt) (Get-Call 30)
        if ($r.Code -ne 0) { throw "send: $($r.Err.Trim())" }
        Send-Keys @($sendKey)
        Add-Log "prompt sent, then $sendKey"
    }

    # 5. The wait for wait_regex.
    $got = $false
    if ($kind -eq 'new-chat') { Start-Sleep -Seconds 2 }
    $end = (Get-Date).AddSeconds((Get-Call $waitS))
    while ((Get-Date) -lt $end) {
        $sc = Get-Screen
        if ($kind -eq 'new-chat') {
            $hitWait = (Test-Line $sc $waitRe) -and (Test-Idle $sc) -and -not ($prompt -and $sc.Contains($prompt))
        } else { $hitWait = Test-Line $sc $waitRe }
        if ($hitWait) { $got = $true; break }
        Start-Sleep -Milliseconds 400
    }
    if (-not $got) {
        Add-Log "no match of wait_regex in the limit"
        Add-Screen 'last' $sc
        if ($kind -eq 'permission') { $reason = 'no-dialog' }
        elseif ($kind -eq 'interrupt') { $code = 1; $reason = 'no-busy' }
        else { $code = 1; $reason = 'no-idle' }
    } else {
        $matchAt = Get-Date
        Add-Log 'wait_regex matches'
        if ($matchAt -gt $watchEnd) {
            $reason = 'late-match'
            Add-Log 'flag: the match came after the end of the watch'
        }
        if ($kind -eq 'new-chat') {
            Add-Screen 'after' $sc
        } else {
            $label = 'dialog'
            if ($kind -eq 'interrupt') { $label = 'busy' }
            Add-Screen $label $sc
            # 6. The answer. For a permission dialog, the watch sees the
            # dialog for WATCH seconds first.
            if ($kind -eq 'permission') {
                $hold = [math]::Min($watchS, (Get-Left) - 5)
                if ($hold -gt 0) {
                    Add-Log "hold the answer for $hold s"
                    Start-Sleep -Seconds $hold
                }
            }
            $keys = @($answer -split ' ' | Where-Object { $_ })
            foreach ($k in $keys) {
                Send-Keys @($k)
                if ($keys.Count -gt 1) { Start-Sleep -Seconds 2 }
            }
            if ($keys.Count -gt 0) { Add-Log "answer: $($keys -join ' ')" }
            Start-Sleep -Seconds 2
            Add-Screen 'after' (Get-Screen)
        }
    }
} catch {
    $code = 1
    if ("$_" -match 'time-limit') { $reason = 'time-limit' }
    if (-not $reason) { $reason = 'error' }
    Add-Log "error: $_"
} finally {
    # 7. The end of the watch, then the stop. A failure of the watch part
    # must not stop the rest of this block.
    try {
        if ($watch) {
            $rest = 0
            if ($watchEnd) { $rest = [int][math]::Ceiling(($watchEnd - (Get-Date)).TotalSeconds) }
            if ($rest -lt 0) { $rest = 0 }
            $w = Wait-KitProcess $run $watch ($rest + 15)
            Add-Log "watch ends: exit $($w.Code)"
            if ($w.Code -ne 0 -and $code -eq 0) { $code = 1; $reason = 'watch-failed' }
            $watchText = Read-KitText "$out.watch"
            if (-not $watchText) { $watchText = (Read-Shared "$out.watch.console") + (Read-Shared "$out.watch.err") }
        }
    } catch {
        Add-Log "the wait for the watch failed: $_"
        if ($code -eq 0) { $code = 1; $reason = 'watch-failed' }
    }
    foreach ($x in "$out.watch", "$out.watch.console", "$out.watch.err") { Remove-Item -LiteralPath $x -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath (Join-Path $sdir 'backend')) {
        $r = Invoke-Session @('stop', $name) 30
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
