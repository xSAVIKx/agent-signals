# The session steps on Windows: kit step permission-*@conpty|psmux and
# real-session-*@operator, with the stub agent as a fake "claude" on PATH
# (a claude.ps1 that runs tools/testdata/agent-kit/stub-agent.ps1).
#
# A backend whose tool is missing prints "skip: <backend>: <reason>". When
# KIT_TEST_SESSIONS is "required", a missing tool is a failure instead.
. (Join-Path $env:ROOT 'tools/agent-kit-tests/lib.ps1')
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

# A fake home: the session uses the home of the run ("real"), so the stub
# writes its key log in the Claude folder of this home. The guided watch
# sees the new lines there.
$h = Join-Path $T 'home'
New-Item -ItemType Directory -Force -Path $h | Out-Null
$env:USERPROFILE = $h
$keysLog = Join-Path $h '.claude\projects\-work-example\keys.jsonl'

# The fake claude: a script file, so that the guided watch counts its
# PowerShell process as claude.
$bin = Join-Path $T 'bin'
$stub = Join-Path $data 'stub-agent.ps1'
New-TextFile (Join-Path $bin 'claude.ps1') (@(
        '$d = Join-Path $env:USERPROFILE ''.claude\projects\-work-example'''
        'New-Item -ItemType Directory -Force -Path $d | Out-Null'
        '$env:STUB_LOG = Join-Path $d ''keys.jsonl'''
        "& '$stub'"
    ) -join "`r`n")
$env:PATH = "$bin;$env:PATH"

# The step list of the test, with the columns of probes/agent/steps.tsv.
$steps = Join-Path $T 'steps.tsv'
$head = "name`tkind`tagent`tbackends`tos`tneeds`tcost`tpre`tidle_regex`tbusy_regex`tdialog_regex`tprompt`twait_regex`tanswer`twindows`tmeasures`tfacts"
New-TextFile $steps ((@(
            $head
            "permission-claude`tpermission`tclaude`tconpty,psmux`twindows`tlogin`tturns:1`t-`t^stub idle`$`t-`t^Do you want to create`twrite`tDo you want to create`tEscape`t-`tthe permission dialog`t-"
            "nodialog-claude`tpermission`tclaude`tconpty,psmux`twindows`tlogin`tturns:1`t-`t^stub idle`$`t-`t^Do you want to create`twrite`tDo you want to create`tEscape`tsend=Tab`tno dialog: Tab does not send`t-"
            "real-session-claude`treal-session`tclaude`toperator`twindows`toperator`tnone`t-`t-`t-`t-`t-`t-`t-`t-`tthe real session`t-"
        ) -join "`n") + "`n")
$env:KIT_STEPS = $steps
$env:AGENT_SIGNALS_WATCH = '8'
$env:AGENT_SIGNALS_STEP_WAIT = '6'

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

# A stub that the kit does not start: the orchestrator of a test, for
# example. No step may count it or stop it.
$other = Start-Process -FilePath $Exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$bin\claude.ps1`"") -WindowStyle Hidden -PassThru
Start-Sleep -Seconds 2
try {
    foreach ($b in $have) {
        # test_permission_step: ok, three screens, and only the session pids.
        Expect-Kit "${b}: the permission step exits 0" 0 'step' "permission-claude@$b"
        Expect-Line "${b}: the permission step prints ok" "^step: permission-claude@$b ok$" $out
        $f = @(Get-ChildItem -LiteralPath $run -Filter "*-permission-claude@$b.txt" -File | Select-Object -Last 1)
        if ($f.Count -ne 1) { Fail "${b}: the step file" 'no file'; continue }
        $f = $f[0].FullName
        foreach ($s in 'idle', 'dialog', 'after') { Expect-Line "${b}: the step file has the $s screen" "^### screen $s$" $f }
        Expect-Line "${b}: the dialog screen shows the dialog" '^Do you want to create agent-signals-test\.txt\?$' $f
        Expect-Line "${b}: the step file has the guided watch" '^### guided watch$' $f
        Expect-Line "${b}: the watch starts before the prompt" '^kit: watch starts, 8 s$' $f
        Expect-Line "${b}: the watch counts only the session pids" '^processes: claude=1$' $f
        Expect-NoLine "${b}: the watch does not count the other stub" "pid=$($other.Id) " $f
        Expect-Line "${b}: the watch sees the new JSONL lines" 'keys\.jsonl \(lines \d+ -> \d+\)$' $f
        Expect-Line "${b}: the watch has the changed files" '^claude \d+ .*keys\.jsonl$' $f
        Expect-Line "${b}: the step stops the session" '^t=\S+ stop: exit 0$' $f
        $live = @(Get-LivePids)
        if ($live.Count -eq 0) { Pass "${b}: no session pid runs after the step" } else { Fail "${b}: no session pid runs after the step" ($live -join ' ') }
        if (Get-Process -Id $other.Id -ErrorAction SilentlyContinue) { Pass "${b}: the step leaves the other stub" } else { Fail "${b}: the step leaves the other stub" 'it stopped' }
    }

    if ($have.Count -gt 0) {
        # test_no_dialog_is_not_a_failure. The windows column gives Tab as
        # the send key, so the stub gets no Enter and draws no dialog.
        $b = $have[0]
        Expect-Kit "${b}: the no-dialog step exits 0" 0 'step' "nodialog-claude@$b"
        Expect-Line "${b}: the no-dialog step prints ok no-dialog" "^step: nodialog-claude@$b ok no-dialog$" $out
        $f = @(Get-ChildItem -LiteralPath $run -Filter "*-nodialog-claude@$b.txt" -File)[0].FullName
        Expect-Line "${b}: no-dialog keeps the last screen" '^### screen last$' $f
        Expect-Line "${b}: the send key is Tab" '^send key: Tab$' $f
        $last = @((Get-Text $keysLog) -split '\r?\n' | Where-Object { $_ })[-1]
        if ($last -eq 'key Tab') { Pass "${b}: the stub got Tab after the prompt" } else { Fail "${b}: the stub got Tab after the prompt" "last key: $last" }
    }

    # test_real_session_asks_first.
    Expect-Kit 'real-session asks first' 4 'step' 'real-session-claude@operator'
    Expect-Line 'real-session prints operator' '^step: real-session-claude@operator operator ' $out
    $f = @(Get-ChildItem -LiteralPath $run -Filter '*-real-session-claude@operator.txt' -File | Select-Object -Last 1)[0].FullName
    Expect-Line 'real-session has an operator line' '^operator: start claude in a real terminal app' $f
    Expect-Line 'real-session names --ready' '^operator: .*kit step real-session-claude@operator --ready$' $f

    # test_real_session_ready: an orchestrator named claude runs the kit,
    # and starts a stub below it. The watch counts only the other stub.
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
    $f = @(Get-ChildItem -LiteralPath $run -Filter '*-real-session-claude@operator.txt' -File | Sort-Object Name | Select-Object -Last 1)[0].FullName
    Expect-Line 'real-session --ready counts the stub outside the kit' '^processes: claude=1$' $f
    Expect-Line 'real-session --ready counts the other stub' "^claude pid=$($other.Id) " $f

    # With no agent outside the kit, --ready asks the operator again.
    Stop-Process -Id $other.Id -Force -ErrorAction SilentlyContinue
    $other = $null
    Start-Sleep -Seconds 1
    Expect-Kit 'real-session --ready with no session asks again' 4 'step' 'real-session-claude@operator' '--ready'

    # test_stop_ends_only_the_pids: a stop --all after the steps leaves a
    # stub that the kit did not start.
    $other2 = Start-Process -FilePath $Exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$bin\claude.ps1`"") -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds 2
    Expect-Kit 'stop --all after the steps' 0 'session' 'stop' '--all'
    Start-Sleep -Milliseconds 500
    if (Get-Process -Id $other2.Id -ErrorAction SilentlyContinue) { Pass 'stop --all leaves a stub that the kit did not start' } else { Fail 'stop --all leaves a stub that the kit did not start' 'it stopped' }
    Stop-Process -Id $other2.Id -Force -ErrorAction SilentlyContinue

    # kit check passes: no pid of pids\ runs, and the scrub ran.
    Expect-Kit 'check passes after the steps' 0 'check'
} catch {
    Fail 'the step cases' "$_"
    $null = Invoke-Kit 'session' 'stop' '--all'
}
if ($other) { Stop-Process -Id $other.Id -Force -ErrorAction SilentlyContinue }
Complete-Tests
