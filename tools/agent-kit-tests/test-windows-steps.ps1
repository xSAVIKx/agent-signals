# The session steps on Windows: kit step permission-*@conpty|psmux,
# new-chat, interrupt and real-session-*@operator, with the stub agent as
# a fake "claude" on PATH (a claude.ps1 that runs
# tools/testdata/agent-kit/stub-agent.ps1).
#
# A backend whose tool is missing prints "skip: <backend>: <reason>". When
# KIT_TEST_SESSIONS is "required", a missing tool is a failure instead.
. (Join-Path $env:ROOT 'tools/agent-kit-tests/lib.ps1')
. (Join-Path $env:ROOT 'probes/agent/lib.ps1')
$out = Join-Path $T 'out'
$data = Join-Path $env:ROOT 'tools/testdata/agent-kit'
function New-TextFile([string]$File, [string]$Text) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $File) | Out-Null
    [IO.File]::WriteAllText($File, $Text)
}
function Get-Text([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    return [IO.File]::ReadAllText($Path)
}
function Show-Out { Get-Content -LiteralPath $out -ErrorAction SilentlyContinue | ForEach-Object { "  | $_" } }
function Expect-Kit([string]$Name, [int]$Want) {
    $c = Invoke-Kit @args
    Expect-Code $Name $Want $c
    if ($c -ne $Want) { Show-Out }
}
function Expect-NoLine([string]$Name, [string]$Pattern, [string]$File) {
    if (Select-String -LiteralPath $File -Pattern $Pattern -Quiet) { Fail $Name "a line matches: $Pattern" } else { Pass $Name }
}
# Get-StepFile FILTER: the newest step file of the run with this name.
function Get-StepFile([string]$Filter) {
    return @(Get-ChildItem -LiteralPath $run -Filter $Filter -File | Sort-Object Name | Select-Object -Last 1)[0].FullName
}
function Start-Stub {
    return (Start-Process -FilePath $Exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$bin\claude.ps1`"") -WindowStyle Hidden -PassThru)
}

# The lines of a Claude welcome box that can show a name are blank.
$dot = [string][char]0x00B7
$box = "| Welcome back alice`n| Example Org Ltd`n| Opus $dot Claude Max $dot bob`nidle`n| Do you want to proceed?`n"
$clean = Clear-KitWelcomeBox $box @('Example Org')
if ($clean -notmatch 'alice|Example Org|bob') { Pass 'the welcome box lines are blank' } else { Fail 'the welcome box lines are blank' $clean }
if ($clean -match 'Claude Max' -and $clean -match '(?m)^idle$' -and $clean -match 'Do you want to proceed') { Pass 'the other lines stay' } else { Fail 'the other lines stay' $clean }

# A fake home: the session uses the home of the run ("real"), so the stub
# writes its key log in the Claude project folder of its work folder.
$h = Join-Path $T 'home'
New-Item -ItemType Directory -Force -Path $h | Out-Null
$env:USERPROFILE = $h

# The fake claude: a script file, so that the guided watch counts its
# PowerShell process as claude.
$bin = Join-Path $T 'bin'
$stub = Join-Path $data 'stub-agent.ps1'
New-TextFile (Join-Path $bin 'claude.ps1') (@(
        '$key = (Get-Location).Path -replace ''[^A-Za-z0-9]'', ''-'''
        '$d = Join-Path $env:USERPROFILE ".claude\projects\$key"'
        'New-Item -ItemType Directory -Force -Path $d | Out-Null'
        '$env:STUB_LOG = Join-Path $d ''keys.jsonl'''
        "& '$stub'"
    ) -join "`r`n")
# A fake agy writes no file, so its step has no records.
New-TextFile (Join-Path $bin 'agy.ps1') "& '$stub'`r`n"
$env:PATH = "$bin;$env:PATH"

# The step list of the test, with the columns of probes/agent/steps.tsv.
$steps = Join-Path $T 'steps.tsv'
$idle = "-`t^stub idle`$`t-`t^Do you want to create"
$head = "name`tkind`tagent`tbackends`tos`tneeds`tcost`tpre`tidle_regex`tbusy_regex`tdialog_regex`tprompt`twait_regex`tanswer`twindows`tmeasures`tfacts"
$common = "claude`tconpty,psmux`twindows`tlogin`tturns:1`t$idle"
New-TextFile $steps ((@(
            $head
            "permission-claude`tpermission`t$common`twrite`tDo you want to create`tEscape`t-`tthe permission dialog`t-"
            "nodialog-claude`tpermission`t$common`twrite`tDo you want to create`tEscape`tsend=Tab`tno dialog: Tab does not send`t-"
            "newchat-claude`tnew-chat`t$common`t/clear`t^stub idle`$`t-`tsend=Tab`ta slash prompt gets Enter`t-"
            "stays-claude`tnew-chat`t$common`thello`t^stub idle`$`t-`tsend=Tab`tthe prompt stays on the screen`t-"
            "nobusy-claude`tinterrupt`t$common`twrite`tno-such-text`tEscape C-c`t-`tno busy screen`t-"
            "unmeasured-claude`tnew-chat`t$common`t/new-chat`t-`t-`t-`tno wait_regex`t-"
            "ended-claude`tpermission`t$common`tnothing`tno-such-text`tEscape`t-`tthe agent ends`t-"
            "norecords-agy`tpermission`t$($common -replace '^claude', 'agy')`twrite`tDo you want to create`tEscape`t-`tno file changes`t-"
            "real-session-claude`treal-session`tclaude`toperator`twindows`toperator`tnone`t-`t-`t-`t-`t-`t-`t-`t-`tthe real session`t-"
        ) -join "`n") + "`n")
$env:KIT_STEPS = $steps
$env:AGENT_SIGNALS_WATCH = '8'

Remove-Item Env:\AGENT_SIGNALS_RUN -ErrorAction SilentlyContinue
$runs = Join-Path $T 'runs'
Expect-Kit 'start a run' 0 'start' '--out' $runs
$run = @(Get-ChildItem -LiteralPath $runs -Directory)[0].FullName
$env:AGENT_SIGNALS_RUN = $run

function Test-Conpty {
    $c = @()
    if ($env:AGENT_SIGNALS_PYTHON) { $c += $env:AGENT_SIGNALS_PYTHON }
    $g = Get-Command python -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($g -and $g.Source -notmatch '\\WindowsApps\\') { $c += $g.Source }
    foreach ($py in $c) {
        $ErrorActionPreference = 'Continue'
        & $py -c 'import winpty, pyte, wcwidth, psutil' 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { return '' }
    }
    return 'needs a Python with pywinpty, pyte, wcwidth and psutil'
}
function Test-Psmux {
    if (Get-Command psmux -CommandType Application -ErrorAction SilentlyContinue) { return '' }
    return 'needs psmux on PATH'
}
$have = @()
foreach ($b in 'conpty', 'psmux') {
    $why = if ($b -eq 'conpty') { Test-Conpty } else { Test-Psmux }
    if ($why) {
        if ($env:KIT_TEST_SESSIONS -eq 'required') { Fail "$b backend" $why } else { Write-Output "skip: ${b}: $why" }
    } else { $have += $b }
}

# kit plan lists the session steps of the backends that this machine has.
Expect-Kit 'plan exits 0' 0 'plan'
foreach ($b in $have) {
    Expect-Line "plan lists the permission step on $b" "^step: permission-claude@$b needs=login cost=turns:1 measures=the permission dialog$" $out
}
Expect-Line 'plan lists the real session' '^step: real-session-claude@operator needs=operator cost=none measures=the real session$' $out

# Get-LivePids: the pids of the session folders of the run that still run,
# with the start time of the pids file.
function Get-LivePids {
    $live = @()
    foreach ($f in @(Get-ChildItem -Path (Join-Path $run 'sessions\*\pids') -File -ErrorAction SilentlyContinue)) {
        foreach ($line in [IO.File]::ReadAllLines($f.FullName)) {
            $id = [int](($line -split ' ')[0])
            $want = ($line -split "`t")[-1].Trim()
            $p = Get-Process -Id $id -ErrorAction SilentlyContinue
            if ($p -and [string]$p.StartTime.ToUniversalTime().Ticks -eq $want) { $live += $id }
        }
    }
    return $live
}

# A transcript of another project gets new lines in each watch, and so
# does the transcript of the real session. The first must not show.
$sid = '0123abcd-4567-89ab-cdef-0123456789ab'
$otherLog = Join-Path $h '.claude\projects\-other-project\other.jsonl'
$realLog = Join-Path $h ".claude\projects\-real-project\$sid.jsonl"
New-TextFile $otherLog "{`"type`":`"other`"}`n"
New-TextFile $realLog "{`"type`":`"old`"}`n"
$writerPs1 = Join-Path $T 'writer.ps1'
New-TextFile $writerPs1 (@(
        'while ($true) {'
        "  [IO.File]::AppendAllText('$otherLog', '{`"type`":`"other`"}' + `"``n`")"
        "  [IO.File]::AppendAllText('$realLog', '{`"type`":`"counted`"}' + `"``n`")"
        '  Start-Sleep -Milliseconds 700'
        '}'
    ) -join "`r`n")
$writer = Start-Process -FilePath $Exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$writerPs1`"") -WindowStyle Hidden -PassThru

# A stub that the kit does not start, and that starts before the ask of
# the real session. No step may count it or stop it.
$other = Start-Stub
Start-Sleep -Seconds 2
$late = $null
$late2 = $null
try {
    foreach ($b in $have) {
        # test_permission_step: ok, three screens, and only the session pids.
        Expect-Kit "${b}: the permission step exits 0" 0 'step' "permission-claude@$b"
        Expect-Line "${b}: the permission step prints ok" "^step: permission-claude@$b ok$" $out
        $f = Get-StepFile "*-permission-claude@$b.txt"
        foreach ($s in 'idle', 'dialog', 'after') { Expect-Line "${b}: the step file has the $s screen" "^### screen $s$" $f }
        Expect-Line "${b}: the dialog screen shows the dialog" '^Do you want to create agent-signals-test\.txt\?$' $f
        Expect-Line "${b}: the step file has the guided watch" '^### guided watch$' $f
        Expect-Line "${b}: the watch covers the wait and the hold" '^kit: watch starts, 24 s$' $f
        Expect-Line "${b}: the step holds the answer" '^t=\S+ the dialog shows\. Hold it for 8 s$' $f
        Expect-Line "${b}: the watch counts only the session pids" '^processes: claude=1$' $f
        Expect-NoLine "${b}: the watch does not count the other stub" "pid=$($other.Id) " $f
        Expect-Line "${b}: the watch reads the new JSONL lines" '^== ~\\\.claude\\projects\\<key>\\<file>\.jsonl \(bytes 0 -> \d+, \d+ new lines\)$' $f
        Expect-Line "${b}: the changed file has a masked path" '^claude \d+ ~\\\.claude\\projects\\<key>\\<file>\.jsonl$' $f
        Expect-NoLine "${b}: the file stem does not show" 'keys\.jsonl' $f
        Expect-NoLine "${b}: another project does not show" 'type=other' $f
        Expect-NoLine "${b}: one transcript shows" 'type=counted' $f
        Expect-Line "${b}: the step stops the session" '^t=\S+ stop: exit 0$' $f
        # The stop file ends the watch, and the last snapshot sees the agent.
        $seen = @(Select-String -LiteralPath $f -Pattern '^claude pid=').Count
        if ($seen -ge 2) { Pass "${b}: the last snapshot sees the session" } else { Fail "${b}: the last snapshot sees the session" "$seen lines" }
        Expect-Line "${b}: the step ends the watch before the stop" '^t=\S+ end the watch$' $f
        $live = @(Get-LivePids)
        if ($live.Count -eq 0) { Pass "${b}: no session pid runs after the step" } else { Fail "${b}: no session pid runs after the step" ($live -join ' ') }
        if (Get-Process -Id $other.Id -ErrorAction SilentlyContinue) { Pass "${b}: the step leaves the other stub" } else { Fail "${b}: the step leaves the other stub" 'it stopped' }
    }

    if ($have.Count -gt 0) {
        $b = $have[0]
        # test_no_dialog_is_not_a_failure. The windows column gives Tab as
        # the send key, so the stub gets no Enter and draws no dialog.
        Expect-Kit "${b}: the no-dialog step exits 0" 0 'step' "nodialog-claude@$b"
        Expect-Line "${b}: the no-dialog step prints ok no-dialog" "^step: nodialog-claude@$b ok no-dialog$" $out
        $f = Get-StepFile "*-nodialog-claude@$b.txt"
        Expect-Line "${b}: no-dialog keeps the last screen" '^### screen last$' $f
        Expect-Line "${b}: the send key is Tab" '^send key: Tab$' $f
        $log = @(Get-ChildItem -Path (Join-Path $h '.claude\projects') -Recurse -Filter 'keys.jsonl' -File | Sort-Object LastWriteTimeUtc | Select-Object -Last 1)[0].FullName
        $keyLines = @((Get-Text $log) -split '\r?\n' | Where-Object { $_ })
        if ($keyLines -contains 'key Tab' -and $keyLines -notcontains 'key Enter') { Pass "${b}: the stub got Tab, not Enter" } else { Fail "${b}: the stub got Tab, not Enter" ($keyLines -join ',') }

        # A prompt that starts with "/" gets Enter, also with send=Tab.
        Expect-Kit "${b}: the new-chat step exits 0" 0 'step' "newchat-claude@$b"
        $f = Get-StepFile "*-newchat-claude@$b.txt"
        Expect-Line "${b}: a slash prompt gets Enter" '^send key: Enter$' $f
        Expect-Line "${b}: the new-chat step keeps the after screen" '^### screen after$' $f

        # The prompt text stays on the screen: no new chat.
        Expect-Kit "${b}: new-chat with the prompt on the screen fails" 1 'step' "stays-claude@$b"
        Expect-Line "${b}: the reason is prompt-on-screen" "^step: stays-claude@$b fail prompt-on-screen$" $out

        # no-dialog is only for permission.
        Expect-Kit "${b}: interrupt with no busy screen fails" 1 'step' "nobusy-claude@$b"
        Expect-Line "${b}: the reason is no-busy" "^step: nobusy-claude@$b fail no-busy$" $out

        # A line with no wait_regex is not measured.
        Expect-Kit "${b}: a line with no wait_regex skips" 3 'step' "unmeasured-claude@$b"
        Expect-Line "${b}: the reason is unmeasured" "^step: unmeasured-claude@$b skip unmeasured$" $out

        # The agent writes no file: the step is ok, and says so.
        Expect-Kit "${b}: a step with no records exits 0" 0 'step' "norecords-agy@$b"
        # The stub in Windows PowerShell 5.1 writes a cache file in its work
        # folder (the driver gives it no LOCALAPPDATA), and the watch sees
        # that file. So this case holds only in PowerShell 7.
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            Expect-Line "${b}: the reason is no-records" "^step: norecords-agy@$b ok no-records$" $out
        } else {
            Expect-Line "${b}: the step with a cache file is ok" "^step: norecords-agy@$b ok$" $out
        }

        # The agent ends in the step.
        $killPs1 = Join-Path $T 'kill.ps1'
        New-TextFile $killPs1 (@(
                '$end = (Get-Date).AddSeconds(60)'
                '$f = $null'
                'while (-not $f -and (Get-Date) -lt $end) {'
                "  `$f = @(Get-ChildItem -Path '$run\sessions\st-*\pid' -File -ErrorAction SilentlyContinue | Where-Object { -not (Test-Path -LiteralPath (Join-Path `$_.DirectoryName 'stopped')) }) | Select-Object -First 1"
                '  Start-Sleep -Milliseconds 300'
                '}'
                'Start-Sleep -Seconds 4'
                'if ($f) { Stop-Process -Id ([int](Get-Content -LiteralPath $f.FullName)) -Force }'
            ) -join "`r`n")
        $killer = Start-Process -FilePath $Exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$killPs1`"") -WindowStyle Hidden -PassThru
        Expect-Kit "${b}: a step whose agent ends fails" 1 'step' "ended-claude@$b"
        Expect-Line "${b}: the reason is agent-ended" "^step: ended-claude@$b fail agent-ended$" $out
        Stop-Process -Id $killer.Id -Force -ErrorAction SilentlyContinue
    }

    # test_real_session_asks_first.
    Expect-Kit 'real-session asks first' 4 'step' 'real-session-claude@operator'
    Expect-Line 'real-session prints operator' '^step: real-session-claude@operator operator ask$' $out
    $f = Get-StepFile '*-real-session-claude@operator.txt'
    Expect-Line 'real-session has an operator line' '^operator: start claude in a real terminal app' $f
    Expect-Line 'real-session names --ready' '^operator: .*kit step real-session-claude@operator --ready$' $f

    # A stub that started before the ask does not count.
    Expect-Kit 'real-session --ready leaves a stub from before the ask' 4 'step' 'real-session-claude@operator' '--ready'
    Expect-Line 'the reason is no-session' '^step: real-session-claude@operator operator no-session$' $out

    # test_real_session_ready: an orchestrator named claude runs the kit,
    # and starts a stub below it. The watch counts only the late stub.
    Start-Sleep -Seconds 1
    $late = Start-Stub
    Start-Sleep -Seconds 2
    New-TextFile (Join-Path $h ".claude\sessions\$($late.Id).json") "{`"sessionId`":`"$sid`",`"status`":`"busy`"}"
    $orch = Join-Path $T 'orch\claude.ps1'
    $orchOut = Join-Path $T 'orch.out'
    New-TextFile $orch (@(
            '$ErrorActionPreference = ''Continue'''
            "`$kid = Start-Process -FilePath '$Exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', '`"$bin\claude.ps1`"') -WindowStyle Hidden -PassThru"
            'Start-Sleep -Seconds 2'
            "& '$Exe' -NoProfile -ExecutionPolicy Bypass -File '$KitPs1' step real-session-claude@operator --ready *> '$orchOut'"
            '$code = $LASTEXITCODE'
            'Stop-Process -Id $kid.Id -Force -ErrorAction SilentlyContinue'
            'exit $code'
        ) -join "`r`n")
    $ErrorActionPreference = 'Continue'
    & $Exe -NoProfile -ExecutionPolicy Bypass -File $orch *> $out
    $c = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    Get-Content -LiteralPath $orchOut -ErrorAction SilentlyContinue | Add-Content -LiteralPath $out
    Expect-Code 'real-session --ready exits 0' 0 $c
    if ($c -ne 0) { Show-Out }
    Expect-Line 'real-session --ready prints ok' '^step: real-session-claude@operator ok$' $out
    $f = Get-StepFile '*-real-session-claude@operator.txt'
    Expect-Line 'real-session --ready counts one process' '^processes: claude=1$' $f
    Expect-Line 'real-session --ready counts the late stub' "^claude pid=$($late.Id) " $f
    Expect-NoLine 'real-session --ready leaves the stub from before' "^claude pid=$($other.Id) " $f
    Expect-Line 'real-session reads the transcript of the pid file' 'type=counted' $f
    Expect-NoLine 'real-session reads only from the start length' 'type=old' $f
    Expect-NoLine 'real-session does not read another project' 'type=other' $f
    $starts = @(Select-String -LiteralPath $f -Pattern '^kit: watch starts, 8 s$').Count
    if ($starts -ge 2) { Pass 'real-session prints the watch start line' } else { Fail 'real-session prints the watch start line' "$starts lines" }

    # Two sessions: the kit cannot know the session of the operator.
    $late2 = Start-Stub
    Start-Sleep -Seconds 2
    Expect-Kit 'real-session --ready refuses two sessions' 4 'step' 'real-session-claude@operator' '--ready'
    Expect-Line 'the reason is many-sessions' '^step: real-session-claude@operator operator many-sessions$' $out

    # test_stop_ends_only_the_pids: a stop --all after the steps leaves
    # the stubs that the kit did not start.
    Expect-Kit 'stop --all after the steps' 0 'session' 'stop' '--all'
    Start-Sleep -Milliseconds 500
    if (Get-Process -Id $other.Id -ErrorAction SilentlyContinue) { Pass 'stop --all leaves a stub that the kit did not start' } else { Fail 'stop --all leaves a stub that the kit did not start' 'it stopped' }

    # kit check passes: no pid of pids\ runs, and the scrub ran.
    Expect-Kit 'check passes after the steps' 0 'check'
} catch {
    Fail 'the step cases' "$_"
    $null = Invoke-Kit 'session' 'stop' '--all'
}
foreach ($p in @($other, $late, $late2, $writer)) {
    if ($p) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
}
Complete-Tests
