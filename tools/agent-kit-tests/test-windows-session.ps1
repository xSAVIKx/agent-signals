# kit session on Windows: the backends conpty and psmux, with the stub
# agent tools/testdata/agent-kit/stub-agent.ps1 on PATH as "claude".
#
# A backend whose tool is missing prints "skip: <backend>: <reason>". When
# KIT_TEST_SESSIONS is "required", a missing tool is a failure instead.
. (Join-Path $env:ROOT 'tools/agent-kit-tests/lib.ps1')

$run = Join-Path $T 'run'
New-Item -ItemType Directory -Path $run | Out-Null
$env:AGENT_SIGNALS_RUN = $run
$data = Join-Path $env:ROOT 'tools/testdata/agent-kit'
$env:PATH = (Join-Path $data 'windows-bin') + ';' + $env:PATH
$out = Join-Path $T 'out'

function Get-Text([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    return [IO.File]::ReadAllText($Path)
}

# The pids of a session that still run.
function Get-LivePids([string]$Name) {
    $f = Join-Path $run "sessions/$Name/pids"
    $live = @()
    if (Test-Path -LiteralPath $f) {
        foreach ($line in [IO.File]::ReadAllLines($f)) {
            $id = [int](($line -split ' ')[0])
            if (Get-Process -Id $id -ErrorAction SilentlyContinue) { $live += $id }
        }
    }
    return $live
}

function Expect-NoLivePids([string]$Case, [string]$Name) {
    $live = @()
    for ($i = 0; $i -lt 20; $i++) {
        $live = @(Get-LivePids $Name)
        if ($live.Count -eq 0) { break }
        Start-Sleep -Milliseconds 250
    }
    if ($live.Count -eq 0) { Pass $Case } else { Fail $Case "pids still run: $($live -join ' ')" }
}

# Start-KitPiped ARGS: run the kit with its stdout and stderr on pipes, as
# an agent tool does. Returns the seconds until the pipes close, or -1
# when they stay open for 60 s (a process that the kit started holds
# them).
function Start-KitPiped {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $all = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $KitPs1) + $args
    $psi.Arguments = (($all | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' ')
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $p = [System.Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEndAsync()
    $e = $p.StandardError.ReadToEndAsync()
    $closed = $o.Wait(60000) -and $e.Wait(5000)
    [IO.File]::WriteAllText($out, $(if ($closed) { $o.Result + $e.Result } else { '' }))
    if ($closed) { return $sw.Elapsed.TotalSeconds }
    return -1
}

function Test-Conpty {
    $c = @()
    if ($env:KIT_PYTHON) { $c += $env:KIT_PYTHON }
    $g = Get-Command python -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($g -and $g.Source -notmatch '\\WindowsApps\\') { $c += $g.Source }
    foreach ($py in $c) {
        $ErrorActionPreference = 'Continue'
        & $py -c 'import winpty, pyte, wcwidth' 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { return '' }
    }
    return 'needs a Python with pywinpty and pyte'
}

function Test-Psmux {
    if (Get-Command psmux -CommandType Application -ErrorAction SilentlyContinue) { return '' }
    return 'needs psmux on PATH'
}

# Bad use needs no backend.
Expect-Code 'session with no command is bad use' 2 (Invoke-Kit 'session')
Expect-Code 'start with no backend is bad use' 2 (Invoke-Kit 'session' 'start' 'x' 'claude')
Expect-Code 'start with an unknown backend is bad use' 2 (Invoke-Kit 'session' 'start' 'x' 'claude' '--via' 'tmux')
Expect-Code 'a bad session name is bad use' 2 (Invoke-Kit 'session' 'screen' '..\x')
Expect-Code 'screen of no session is bad use' 2 (Invoke-Kit 'session' 'screen' 'none')
$saved = $env:PATH; $savedPy = $env:KIT_PYTHON
$env:PATH = Join-Path $env:SystemRoot 'System32'; $env:KIT_PYTHON = ''
Expect-Code 'conpty with no Python exits 3' 3 (Invoke-Kit 'session' 'start' 'np' 'claude' '--via' 'conpty')
Expect-Code 'psmux not on PATH exits 3' 3 (Invoke-Kit 'session' 'start' 'nm' 'claude' '--via' 'psmux')
$env:PATH = $saved; $env:KIT_PYTHON = $savedPy

foreach ($b in 'conpty', 'psmux') {
    $why = if ($b -eq 'conpty') { Test-Conpty } else { Test-Psmux }
    if ($why) {
        if ($env:KIT_TEST_SESSIONS -eq 'required') { Fail "$b backend" $why } else { Write-Output "skip: ${b}: $why" }
        continue
    }
    $other = $null
    try {
        $s = "drive-$b"
        $log = Join-Path $T "keys-$b.log"
        $env:STUB_LOG = $log

        # test_session_drives_the_stub, each command in a new process.
        Expect-Code "${b}: start" 0 (Invoke-Kit 'session' 'start' $s 'claude' '--via' $b)
        Get-Content -LiteralPath $out | Write-Output
        foreach ($k in 'backend', 'work', 'pid') {
            if (Test-Path -LiteralPath (Join-Path $run "sessions/$s/$k")) { Pass "${b}: state file $k" } else { Fail "${b}: state file $k" 'missing' }
        }
        $sock = if ($b -eq 'conpty') { 'pipe' } else { 'socket' }
        if (Test-Path -LiteralPath (Join-Path $run "sessions/$s/$sock")) { Pass "${b}: state file $sock" } else { Fail "${b}: state file $sock" 'missing' }
        $work = (Get-Text (Join-Path $run "sessions/$s/work")).Trim()
        Expect-Code "${b}: wait for the idle screen" 0 (Invoke-Kit 'session' 'wait' $s 'stub idle' '60')
        Expect-Code "${b}: screen" 0 (Invoke-Kit 'session' 'screen' $s)
        Expect-Line "${b}: the screen shows the stub" '^stub idle$' $out
        Expect-Code "${b}: send" 0 (Invoke-Kit 'session' 'send' $s 'write')
        Expect-Code "${b}: key Enter" 0 (Invoke-Kit 'session' 'key' $s 'Enter')
        Expect-Code "${b}: wait for the dialog" 0 (Invoke-Kit 'session' 'wait' $s 'Do you want to create agent-signals-test\.txt\?' '30')
        Expect-Code "${b}: screen of the dialog" 0 (Invoke-Kit 'session' 'screen' $s)
        Expect-Line "${b}: the dialog has 1. Yes" '^1\. Yes$' $out
        Expect-Code "${b}: key 1" 0 (Invoke-Kit 'session' 'key' $s '1')
        Expect-Code "${b}: wait for the write" 0 (Invoke-Kit 'session' 'wait' $s 'stub wrote' '30')
        if (Test-Path -LiteralPath (Join-Path $work 'agent-signals-test.txt')) { Pass "${b}: the stub wrote the file in work" } else { Fail "${b}: the stub wrote the file in work" "no file in $work" }

        # test_psmux_sends_enter: the stub got a carriage return, not "^M".
        $keys = Get-Text $log
        if ($keys -match '(?m)^key Enter\r?$') { Pass "${b}: the stub got Enter" } else { Fail "${b}: the stub got Enter" "keys: $($keys -replace '\r?\n', ',')" }
        if ($keys -notmatch '(?m)^char 94\r?$') { Pass "${b}: the stub got no ^" } else { Fail "${b}: the stub got no ^" 'the stub got the text ^M' }

        # Escape goes back to idle.
        Expect-Code "${b}: send for the second dialog" 0 (Invoke-Kit 'session' 'send' $s 'write')
        Expect-Code "${b}: key Enter again" 0 (Invoke-Kit 'session' 'key' $s 'Enter')
        Expect-Code "${b}: the second dialog" 0 (Invoke-Kit 'session' 'wait' $s '^2\. No' '30')
        Expect-Code "${b}: key Escape" 0 (Invoke-Kit 'session' 'key' $s 'Escape')
        Expect-Code "${b}: idle after Escape" 0 (Invoke-Kit 'session' 'wait' $s '^stub idle' '30')

        # The time limit of wait.
        Expect-Code "${b}: wait at the time limit exits 1" 1 (Invoke-Kit 'session' 'wait' $s 'no-such-text' '2')
        $last = Join-Path $run "sessions/$s/last.screen"
        if ((Get-Text $last) -match '(?m)^stub idle$') { Pass "${b}: wait saved the last screen" } else { Fail "${b}: wait saved the last screen" "no stub idle in $last" }
        Expect-Code "${b}: an unknown key is bad use" 2 (Invoke-Kit 'session' 'key' $s 'NoSuchKey')

        Expect-Code "${b}: stop" 0 (Invoke-Kit 'session' 'stop' $s)
        Expect-NoLivePids "${b}: no pid of the session runs after stop" $s
        Remove-Item Env:\STUB_LOG

        # The start returns when the caller reads the output through a pipe.
        $s2 = "piped-$b"
        $sec = Start-KitPiped 'session' 'start' $s2 'claude' '--via' $b
        Write-Output ("${b}: start with pipes took {0:N1} s" -f $sec)
        if ($sec -ge 0) { Pass "${b}: start does not hold the pipes of the caller" } else { Fail "${b}: start does not hold the pipes of the caller" 'the pipes stayed open for 60 s' }
        if ($sec -ge 0 -and $sec -lt 5) { Pass "${b}: start returns in under 5 s" } else { Fail "${b}: start returns in under 5 s" "it took $sec s" }
        $bw = Join-Path $run "sessions/$s2/breakaway"
        if (Test-Path -LiteralPath $bw) { Write-Output "${b}: breakaway from the job: $((Get-Text $bw).Trim())" }
        Expect-Code "${b}: wait in the piped session" 0 (Invoke-Kit 'session' 'wait' $s2 'stub idle' '60')

        # test_stop_all_after_a_kill and test_stop_ends_only_the_pids.
        $s3 = "killed-$b"
        Expect-Code "${b}: start a third session" 0 (Invoke-Kit 'session' 'start' $s3 'claude' '--via' $b '--cmd' "& '$data\stub-agent.ps1'")
        $other = Start-Process -FilePath $Exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$data\stub-agent.ps1`"") -WindowStyle Hidden -PassThru
        $waiter = Start-Process -FilePath $Exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$KitPs1`"", 'session', 'wait', $s3, 'no-such-text', '120') -WindowStyle Hidden -PassThru
        Start-Sleep -Seconds 3
        Stop-Process -Id $waiter.Id -Force -ErrorAction SilentlyContinue
        if (@(Get-LivePids $s3).Count -gt 0) { Pass "${b}: the session runs after the kit is killed" } else { Fail "${b}: the session runs after the kit is killed" 'no live pid' }
        Expect-Code "${b}: stop --all" 0 (Invoke-Kit 'session' 'stop' '--all')
        Expect-NoLivePids "${b}: stop --all stops the leftover pids" $s3
        Expect-NoLivePids "${b}: stop --all stops the piped session" $s2
        Start-Sleep -Milliseconds 500
        if (Get-Process -Id $other.Id -ErrorAction SilentlyContinue) { Pass "${b}: stop --all leaves a stub that the kit did not start" } else { Fail "${b}: stop --all leaves a stub that the kit did not start" 'it stopped' }
    } catch {
        Fail "${b}: the cases" "$_"
        $null = Invoke-Kit 'session' 'stop' '--all'
    }
    if ($other) { Stop-Process -Id $other.Id -Force -ErrorAction SilentlyContinue }
}

Complete-Tests
