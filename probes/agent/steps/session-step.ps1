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
#      "kit: watch starts". The watch shows only the work folder, the
#      project folder of the work folder (-ScopeNew), a throwaway home, and
#      the session files of the session.
#   4. Do the action of the kind. The send key is Enter, or the key of
#      "send=KEY" in the column "windows". A prompt that starts with "/"
#      always gets Enter. Codex on Windows is not measured: the Tab comes
#      from a report.
#      permission  send the prompt, wait for wait_regex (the dialog, 90 s),
#                  hold the dialog for 30 s so that the watch sees it, send
#                  the answer, wait for idle (10 s).
#      new-chat    send the prompt, wait for an idle screen that does not
#                  show the prompt text.
#      interrupt   send the prompt, wait for wait_regex (the busy screen),
#                  then send each key of the answer, 2 s apart.
#   5. Make the stop file of the watch, and wait for the end of the watch,
#      so that its last snapshot sees the session. Then stop the session.
# "resume" does not run on Windows: a stop deletes the work folder.
#
# Results and reasons, as in session-step.sh:
#   ok                     the step did its action, and the watch saw a
#                          file or a record.
#   ok no-records          the watch saw no changed file and no record.
#   ok no-dialog           permission only: no dialog in the time limit.
#   ok dialog-after-watch  the dialog came after the end of the watch.
#   ok no-idle-after       no idle screen after the answer.
#   fail no-idle, no-busy, prompt-on-screen, agent-ended, screen-failed,
#        send-failed, session-start, no-watch, watch-exit-N, watch-timeout,
#        no-guided
#   skip unmeasured        the step list has no idle regex or no wait regex
#                          for the agent (Cursor).
# A failed screen read is a failure: the step does not use an old screen.
#
# Caution: a real screen of Claude Code can show a display name or an
# organisation in its welcome box. The step blanks these lines before it
# saves a screen, and the file says so. No real screen was measured.
#
# One deadline of 225 s holds for the whole step. With AGENT_SIGNALS_WATCH
# set (the tests), each wait after the idle screen and the hold take that
# number of seconds at most. The step stops only the pids of its session.
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
# The mode of the agent: the words of "session start --args".
$stepArgs = Get-Field 'args'
# The outside folder: a new folder that is not in the work folder. The text
# @OUTSIDE@ in the prompt becomes the path of a file in it.
$outside = ''
if ($prompt.Contains('@OUTSIDE@')) {
    $outside = "$out.outside"
    New-Item -ItemType Directory -Force -Path $outside | Out-Null
    $prompt = $prompt.Replace('@OUTSIDE@', (Join-Path $outside 'agent-signals-write.txt'))
}
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
    if ($i -gt 0) { $pre += New-Object PSObject -Property @{ Re = $p.Substring(0, $i); Keys = @($p.Substring($i + 2) -split ' ' | Where-Object { $_ }); Used = 0; At = [datetime]::MinValue; Screen = '' } }
}
# Get-Limit SECONDS: a time limit. AGENT_SIGNALS_WATCH makes it shorter.
function Get-Limit([int]$Seconds) {
    if ($env:AGENT_SIGNALS_WATCH -match '^[1-9][0-9]*$' -and [int]$env:AGENT_SIGNALS_WATCH -lt $Seconds) { return [int]$env:AGENT_SIGNALS_WATCH }
    return $Seconds
}
$waitS = Get-Limit 90
$holdS = Get-Limit 30
$afterS = Get-Limit 10
$watchS = $waitS + $holdS + $afterS
# The limit for the last snapshot of the watch, after the stop file.
$endS = 20

$log = New-Object System.Text.StringBuilder
$t0 = Get-Date
$deadline = $t0.AddSeconds(225)
# The invariant culture writes "t=11.8s", also where the decimal mark is a comma.
function Add-Log([string]$Text) { [void]$log.Append([string]::Format([Globalization.CultureInfo]::InvariantCulture, 't={0:N1}s {1}', ((Get-Date) - $t0).TotalSeconds, $Text) + "`n") }
$screens = New-Object System.Collections.ArrayList
$blankValues = @()
function Add-Screen([string]$Name, [string]$Text) {
    if ($agent -eq 'claude') { $Text = Clear-KitWelcomeBox $Text $blankValues }
    [void]$screens.Add(@($Name, $Text))
}

# Get-Clip SECONDS: SECONDS, or the time to the deadline when that is
# shorter, with 25 s kept for the end of the step. It is 1 at least.
function Get-Clip([int]$Seconds) {
    $l = [int][math]::Floor(($deadline - (Get-Date)).TotalSeconds) - 25
    if ($l -lt 1) { $l = 1 }
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
# The idle rule of steps.tsv.
function Test-Idle([string]$Screen) {
    if ((Test-Line $Screen $busyRe) -or (Test-Line $Screen $dialogRe)) { return $false }
    return (Test-Line $Screen $idleRe)
}

$name = 'st-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
$sdir = Join-Path (Join-Path $run 'sessions') $name
$code = 0
$reason = ''
$watch = $null
$sc = ''

# Stop-Step REASON: end the step with "fail".
function Stop-Step([string]$Why) {
    $script:code = 1
    $script:reason = $Why
    throw "the step fails: $Why"
}
# Test-Alive: true when the agent of the session runs.
function Test-Alive {
    $a = (Read-KitText (Join-Path $sdir 'pid')).Trim()
    return ($a -match '^\d+$' -and (Test-KitPidOurs $run ([int]$a)))
}
# Update-Screen: read the screen into $sc. A failed read ends the step. A
# blank screen is not a failure: an agent can start slowly.
function Update-Screen {
    $r = Invoke-Session @('screen', $name) (Get-Clip 30)
    if ($r.Code -ne 0) {
        if (-not (Test-Alive)) { Stop-Step 'agent-ended' }
        Add-Log "no screen: exit $($r.Code) $($r.Err.Trim())"
        Stop-Step 'screen-failed'
    }
    $script:sc = $r.Out
}
function Stop-Send([string]$Text) {
    Add-Log "${Text}: failed"
    if (-not (Test-Alive)) { Stop-Step 'agent-ended' }
    Stop-Step 'send-failed'
}
function Send-Keys([string[]]$Keys) {
    foreach ($k in $Keys) {
        $r = Invoke-Session @('key', $name, $k) (Get-Clip 30)
        if ($r.Code -ne 0) { Stop-Send "key $k" }
    }
}
# Send-Prompt: type the prompt and press the send key, as send of
# session-step.sh does. Codex can keep the text in its box and drop an early
# key (fact 76). So the step waits 2 s, looks for the text on the
# screen. When it is not there, the step clears the box with C-u and types
# it again, so that a slow agent does not get it twice.
function Send-Prompt {
    Start-Sleep -Seconds (Get-Clip 2)
    $want = if ($prompt.Length -gt 24) { $prompt.Substring(0, 24) } else { $prompt }
    for ($try = 0; $try -lt 3; $try++) {
        if ($try -gt 0) {
            Add-Log 'the prompt is not on the screen. Clear the box and type it again'
            Send-Keys @('C-u')
            Start-Sleep -Milliseconds 300
        }
        $r = Invoke-Session @('send', $name, $prompt) (Get-Clip 30)
        if ($r.Code -ne 0) { Stop-Send 'send' }
        $seen = $false
        for ($n = 0; $n -lt 3 -and -not $seen; $n++) {
            Update-Screen
            $seen = $sc.Contains($want)
            if (-not $seen) { Start-Sleep -Milliseconds 500 }
        }
        if ($seen) { break }
    }
    if (-not $seen) { Add-Log 'the prompt did not show on the screen in 3 tries' }
    Send-Keys @($sendKey)
    # The box still holds the text when the screen shows it and is not idle,
    # busy or a dialog.
    for ($n = 0; $n -lt 3; $n++) {
        Start-Sleep -Seconds 1
        Update-Screen
        if (-not $sc.Contains($want)) { break }
        if ((Test-Line $sc $idleRe) -or (Test-Line $sc $busyRe) -or (Test-Line $sc $dialogRe)) { break }
        if (Test-Line $sc $waitRe) { break }
        Add-Log 'the box still holds the prompt. Press the send key again'
        Send-Keys @($sendKey)
    }
    Add-Log "prompt sent, then $sendKey"
}
# Send-Pre: send the keys of the first "pre" pair that matches a line of the
# screen. It returns true when it sent keys. A key that comes before the
# agent reads keys is lost. So a pair gets its keys again, 3 times at most,
# when it still matches 3 s after its keys and the screen is the same as at
# the last send.
function Send-Pre {
    foreach ($p in $pre) {
        if ($p.Used -ge 3 -or -not (Test-Line $sc $p.Re)) { continue }
        if ($p.Used -gt 0 -and (((Get-Date) - $p.At).TotalSeconds -lt 3 -or $sc -cne $p.Screen)) { continue }
        $p.Used++
        $p.At = Get-Date
        $p.Screen = $sc
        Add-Log "pre: $($p.Re) => $($p.Keys -join ' ')"
        Send-Keys $p.Keys
        return $true
    }
    return $false
}
# Test-InBox TEXT: TEXT is at the end of the box line, the last line of the
# screen that starts with a prompt mark (U+276F, U+203A, U+2192 or >). With
# no such line, at the end of any line. Claude Code 2.1.318 shows a sent
# "/clear" on a line above the box.
function Test-InBox([string]$Text) {
    $lines = @($sc -split "`r?`n")
    $box = @($lines | Where-Object { $_ -match ('^\s*(' + [char]0x276F + '|' + [char]0x203A + '|' + [char]0x2192 + '|>)') })
    if ($box.Count -gt 0) { $lines = @($box[-1]) }
    $re = '(^|\s)' + [regex]::Escape($Text) + '\s*$'
    foreach ($l in $lines) { if ($l -match $re) { return $true } }
    return $false
}
# Wait-Idle SECONDS [TEXT]: answer the "pre" pairs and wait for the idle
# screen. With TEXT, the box line must not show TEXT (Test-InBox).
function Wait-Idle([int]$Seconds, [string]$Text) {
    $end = (Get-Date).AddSeconds((Get-Clip $Seconds))
    while ($true) {
        if (-not (Test-Alive)) { Stop-Step 'agent-ended' }
        Update-Screen
        if (-not (Send-Pre) -and (Test-Idle $sc) -and -not ($Text -and (Test-InBox $Text))) { return $true }
        if ((Get-Date) -ge $end) { return $false }
        Start-Sleep -Milliseconds 500
    }
}
# Wait-Regex RE SECONDS: wait until a line of the screen matches RE.
function Wait-Regex([string]$Re, [int]$Seconds) {
    $end = (Get-Date).AddSeconds((Get-Clip $Seconds))
    while ($true) {
        if (-not (Test-Alive)) { Stop-Step 'agent-ended' }
        Update-Screen
        if (Test-Line $sc $Re) { return $true }
        if ((Get-Date) -ge $end) { return $false }
        Start-Sleep -Milliseconds 400
    }
}
# Test-NoRecords TEXT: true when the guided file shows no changed file
# (section 1) and no record (section 3).
function Test-NoRecords([string]$Text) {
    $part = 0
    foreach ($l in ($Text -split "`r?`n")) {
        if ($l -match '^### ([0-9]+)\. ') { $part = [int]$Matches[1]; continue }
        if ($l -match '^### ') { $part = 0; continue }
        if ($part -eq 1 -and $l.Trim() -and $l -notmatch '^not measured:') { return $false }
        if ($part -eq 3 -and $l.StartsWith('== ')) { return $false }
    }
    return $true
}

try {
    if (-not $idleRe -or -not $waitRe) {
        $code = 3; $reason = 'unmeasured'
        Add-Log 'skip: the step list has no measured screen for this step'
        return
    }
    if ($backend -eq 'conpty' -and -not (Test-Path -LiteralPath (Join-Path $script:KitRoot 'scenarios\conpty.py') -PathType Leaf)) {
        $code = 3; $reason = 'needs-scenario'
        Add-Log 'skip: the kit has no scenarios\conpty.py'
        return
    }
    if ($agent -eq 'codex') { Add-Log 'not measured: Codex on Windows. The Tab send key comes from a report.' }
    Add-Log "start: $agent on $backend, home $env:KIT_HOME"
    $startArgs = @('start', $name, $agent, '--via', $backend, '--home', $env:KIT_HOME)
    if ($stepArgs) { $startArgs += @('--args', $stepArgs) }
    $r = Invoke-Session $startArgs (Get-Clip 120)
    if ($r.Code -eq 3) {
        $code = 3
        $why = $r.Err.Trim()
        if ($why -match 'Python') { $reason = 'needs-conpty-python' } elseif ($why -match 'psmux') { $reason = 'needs-psmux' } else { $reason = 'not-installed' }
        Add-Log "skip: $why"
        return
    }
    if ($r.Code -ne 0) { Add-Log "start failed: exit $($r.Code) $($r.Err.Trim())"; Stop-Step 'session-start' }
    Add-Log 'session started'

    $work = (Read-KitText (Join-Path $sdir 'work')).Trim()
    $stateHome = $env:USERPROFILE
    if ($env:KIT_HOME -ne 'real') { $stateHome = Join-Path (Join-Path $run 'home') $name }
    # The values of the login that a welcome box can show. They stay in
    # this process. The step never writes them.
    foreach ($f in (Join-Path $stateHome '.claude.json'), (Join-Path $stateHome '.claude\.claude.json')) {
        $j = Read-Shared $f
        foreach ($k in 'displayName', 'organizationName') {
            $m = [regex]::Match($j, '"' + $k + '"\s*:\s*"([^"]*)"')
            if ($m.Success) { $blankValues += $m.Groups[1].Value }
        }
    }

    # 2. The pre answers and the idle screen.
    if (-not (Wait-Idle 60 '')) { Stop-Step 'no-idle' }
    Add-Screen 'idle' $sc
    Add-Log 'idle'

    # 3. The guided watch, in the background. Claude names a project folder
    # by the path with each character that is not a letter or a digit
    # changed to "-", and it can make the folder after the first prompt.
    $scope = @($work)
    if ($env:KIT_HOME -ne 'real') { $scope += $stateHome }
    $scopeNew = @(
        (Join-Path $stateHome (".claude\projects\" + ($work -replace '[^A-Za-z0-9]', '-')))
        (Join-Path $stateHome (".cursor\projects\" + (($work -replace '[^A-Za-z0-9]+', '-').Trim('-'))))
    )
    $wsecs = Get-Clip $watchS
    $stopFile = "$out.watch.stop"
    $argText = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' + (Format-KitArg $runPs1) +
        " -Guided $kind $agent -Wait $wsecs -PidsFile " + (Format-KitArg (Join-Path $sdir 'pids')) +
        ' -StateHome ' + (Format-KitArg $stateHome) + ' -Scope ' + (Format-KitArg ($scope -join '|')) +
        ' -ScopeNew ' + (Format-KitArg ($scopeNew -join '|')) + ' -StopFile ' + (Format-KitArg $stopFile) +
        ' -Out ' + (Format-KitArg "$out.watch")
    $watch = Start-KitProcess $run "watch $name" $exe $argText "$out.watch.console" "$out.watch.err" $run
    $end = (Get-Date).AddSeconds((Get-Clip 60))
    $began = $false
    while ((Get-Date) -lt $end -and -not $watch.HasExited) {
        if ((Read-Shared "$out.watch.console") -match '(?m)^kit: watch starts, ') { $began = $true; break }
        Start-Sleep -Milliseconds 200
    }
    if (-not $began) {
        Add-Log ('the watch did not start: ' + ((Read-Shared "$out.watch.console") + (Read-Shared "$out.watch.err")).Trim())
        Stop-Step 'no-watch'
    }
    Add-Log "the watch runs, $wsecs s at most"

    # 4. The action of the kind.
    Send-Prompt
    switch ($kind) {
        'permission' {
            if (Wait-Regex $waitRe $waitS) {
                if ($watch.HasExited) { $reason = 'dialog-after-watch' }
                Add-Screen 'dialog' $sc
                $hold = Get-Clip $holdS
                Add-Log "the dialog shows. Hold it for $hold s"
                Start-Sleep -Seconds $hold
                if (-not (Test-Alive)) { Stop-Step 'agent-ended' }
            } else {
                $reason = 'no-dialog'
                Add-Screen 'last' $sc
                Add-Log 'no dialog in the time limit'
            }
            Add-Log "answer: $answer"
            Send-Keys @($answer -split ' ' | Where-Object { $_ })
            Start-Sleep -Seconds 1
            if (-not (Wait-Idle $afterS '')) {
                Add-Log 'no idle screen after the answer'
                if (-not $reason) { $reason = 'no-idle-after' }
            }
            Add-Screen 'after' $sc
        }
        'new-chat' {
            Start-Sleep -Seconds 2
            if (-not (Wait-Idle $waitS $prompt)) { Stop-Step 'prompt-on-screen' }
            Add-Screen 'after' $sc
        }
        'interrupt' {
            $keys = @($answer -split ' ' | Where-Object { $_ })
            if (-not (Wait-Regex $waitRe $waitS)) {
                if ($keys.Count -gt 0) { Send-Keys @($keys[0]) }
                Stop-Step 'no-busy'
            }
            Add-Screen 'busy' $sc
            foreach ($k in $keys) {
                Add-Log "send $k"
                Send-Keys @($k)
                Start-Sleep -Seconds 2
                Update-Screen
                Add-Screen "after $k" $sc
            }
        }
        default { Add-Log "unknown kind: $kind"; Stop-Step "unknown-kind-$kind" }
    }
} catch {
    $code = 1
    if (-not $reason) { $reason = 'error' }
    Add-Log "error: $_"
    if ($sc) { Add-Screen 'last' $sc }
} finally {
    # 5. The end of the watch, then the stop. A failure of the watch part
    # must not stop the rest of this block.
    $watchText = ''
    $watchBad = ''
    try {
        if ($watch) {
            [IO.File]::WriteAllText("$out.watch.stop", '')
            Add-Log 'end the watch'
            $w = Wait-KitProcess $run $watch $endS
            Add-Log "the watch ended, exit $($w.Code)"
            $watchText = Read-KitText "$out.watch"
            if ($w.TimedOut) { $watchBad = 'watch-timeout' }
            elseif ($w.Code -ne 0) { $watchBad = "watch-exit-$($w.Code)" }
            elseif (-not $watchText) { $watchBad = 'no-guided' }
            if (-not $watchText) { $watchText = "no guided-step file. Its output:`n" + (Read-Shared "$out.watch.console") + (Read-Shared "$out.watch.err") }
        }
    } catch {
        Add-Log "the wait for the watch failed: $_"
        $watchBad = 'watch-timeout'
    }
    foreach ($x in "$out.watch", "$out.watch.stop", "$out.watch.console", "$out.watch.err") { Remove-Item -LiteralPath $x -Force -ErrorAction SilentlyContinue }
    # The conditions of the session and the facts of the end. "session
    # stop" deletes the work folder, so the step reads it before the stop.
    $cond = New-Object System.Text.StringBuilder
    try {
        $cf = Join-Path $sdir 'conditions'
        if (Test-Path -LiteralPath $cf) { [void]$cond.Append((Read-KitText $cf).TrimEnd() + "`n") } else { [void]$cond.Append("no conditions file`n") }
        $idleText = ''
        foreach ($s in $screens) { if ($s[0] -eq 'idle') { $idleText = [string]$s[1]; break } }
        $modeLines = @($idleText -split "`r?`n" | Where-Object { $_ -match '(?i)(^|[^a-z])mode([^a-z]|$)' } | Select-Object -First 3 | ForEach-Object { $_.Trim() })
        if ($modeLines.Count -gt 0) { foreach ($l in $modeLines) { [void]$cond.Append("mode on the idle screen: $l`n") } }
        else { [void]$cond.Append("mode on the idle screen: no line names a mode`n") }
        $fl = Join-Path $sdir 'fake-model.log'
        if (Test-Path -LiteralPath $fl) {
            $counts = @{}
            foreach ($l in [IO.File]::ReadAllLines($fl)) {
                $w = $l -split ' '
                if ($w.Count -ge 4 -and $w[0] -eq 'POST') { $k = ($w[3..($w.Count - 1)] -join ' '); $counts[$k] = 1 + [int]$counts[$k] }
            }
            $parts = @($counts.Keys | Sort-Object | ForEach-Object { "$_ $($counts[$_])" })
            [void]$cond.Append("fake model answers: $(if ($parts.Count -gt 0) { $parts -join ', ' } else { 'none' })`n")
        }
        $wf = (Read-KitText (Join-Path $sdir 'work')).Trim()
        if ($wf -and (Test-Path -LiteralPath $wf)) {
            $names = @(Get-ChildItem -LiteralPath $wf -Force -Name | Sort-Object)
            [void]$cond.Append("files in the work folder at the end: $(if ($names.Count -gt 0) { $names -join ' ' } else { 'none' })`n")
        }
        if ($outside) {
            $names = @(Get-ChildItem -LiteralPath $outside -Force -Name -ErrorAction SilentlyContinue | Sort-Object)
            [void]$cond.Append("files in the outside folder at the end: $(if ($names.Count -gt 0) { $names -join ' ' } else { 'none' })`n")
        }
    } catch { [void]$cond.Append("the conditions failed: $_`n") }
    if ($outside) { Remove-Item -Recurse -Force -LiteralPath $outside -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath (Join-Path $sdir 'backend')) {
        $left = [int][math]::Ceiling(($deadline - (Get-Date)).TotalSeconds)
        $r = Invoke-Session @('stop', $name) ([math]::Max(10, $left))
        Add-Log "stop: exit $($r.Code)"
        foreach ($l in ($r.Out -split "`r?`n" | Where-Object { $_ -match '^stop: ' })) { Add-Log $l }
        if ($r.Code -ne 0 -and $code -eq 0) { $code = 1; $reason = 'no-stop' }
    }
    if ($watchBad) {
        if ($code -eq 0) { $reason = $watchBad }
        $code = 1
    }
    if ($code -eq 0 -and -not $reason -and $watch -and (Test-NoRecords $watchText)) { $reason = 'no-records' }
    $result = 'ok'
    if ($code -eq 1) { $result = 'fail' } elseif ($code -eq 3) { $result = 'skip' }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("# agent-signals session step: $env:KIT_STEP@$backend`n")
    [void]$sb.Append("kind: $kind`nagent: $agent`nbackend: $backend`nhome: $env:KIT_HOME`n$(if ($env:KIT_HOME -eq 'fixture') { "model: fake-model.py with fixed answers. No real model ran.`n" })send key: $sendKey`n")
    [void]$sb.Append(("result: $result $reason").TrimEnd() + "`n")
    if ($agent -eq 'claude') { [void]$sb.Append("screens: the kit blanks each welcome box line that can show a display name or an organisation. No real screen was measured.`n") }
    [void]$sb.Append("### conditions`n" + $cond.ToString())
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
