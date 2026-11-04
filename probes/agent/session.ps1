# kit session on Windows: a test session of an agent on the backend conpty
# (scenarios/conpty.py in its serve mode) or psmux (a private psmux
# server). It is the twin of probes/agent/session.sh.
#
#   kit session start NAME AGENT --via conpty|psmux [--cmd CMD]
#   kit session send NAME TEXT
#   kit session key NAME KEY          (tmux names: Enter, Escape, C-c, Tab, 1)
#   kit session screen NAME           (the format of tmux capture-pane -p)
#   kit session wait NAME REGEX SECONDS
#   kit session stop NAME
#   kit session stop --all
#
# All state is in files in RUN\sessions\NAME\, so that each command can run
# in a new shell: backend, work (a new folder), pid (the agent), and pipe
# (conpty) or socket (the psmux server name). Each started pid also goes to
# RUN\pids\. A stop ends only these pids, never a process found by its name.
#
# conpty needs a Python with pywinpty and pyte: $env:KIT_PYTHON, else
# python on PATH. psmux needs psmux on PATH. When one is missing, start
# exits 3.
#
# Exit codes: 0 ok, 1 fail (also: wait came to its time limit), 2 bad use,
# 3 a needed tool is missing.
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'lib.ps1')

$Cols = 120
$Rows = 40
$Utf8 = New-Object System.Text.UTF8Encoding $false

function Show-Usage {
    [Console]::Error.WriteLine('usage: kit session start NAME AGENT --via conpty|psmux [--cmd CMD]')
    [Console]::Error.WriteLine('       kit session send NAME TEXT | key NAME KEY | screen NAME')
    [Console]::Error.WriteLine('       kit session wait NAME REGEX SECONDS | stop NAME | stop --all')
    exit 2
}

# ConvertTo-KitArg TEXT: quote one argument with the rules of the C
# runtime, so that the program gets TEXT back as one argument.
function ConvertTo-KitArg([string]$Text) {
    if ($Text -ne '' -and $Text -notmatch '[\s"]') { return $Text }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    $bs = 0
    foreach ($ch in $Text.ToCharArray()) {
        if ($ch -eq '\') { $bs++; continue }
        if ($ch -eq '"') {
            [void]$sb.Append('\' * ($bs * 2 + 1)); [void]$sb.Append('"'); $bs = 0; continue
        }
        if ($bs -gt 0) { [void]$sb.Append('\' * $bs); $bs = 0 }
        [void]$sb.Append($ch)
    }
    [void]$sb.Append('\' * ($bs * 2))
    [void]$sb.Append('"')
    return $sb.ToString()
}

function Join-KitArgs([string[]]$List) {
    return (($List | ForEach-Object { ConvertTo-KitArg $_ }) -join ' ')
}

# Invoke-KitNative FILE ARGS: run a short command and read its output as
# UTF-8. It returns an object with Code, Out and Err. The output does not
# go through the PowerShell pipeline, so a line on stderr is not an error
# record, and the console code page does not change the text. Use it only
# for a command that starts no process that stays.
function Invoke-KitNative([string]$File, [string[]]$List) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $File
    $psi.Arguments = Join-KitArgs $List
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = $Utf8
    $psi.StandardErrorEncoding = $Utf8
    $p = [System.Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEndAsync()
    $e = $p.StandardError.ReadToEndAsync()
    $p.WaitForExit()
    return [pscustomobject]@{ Code = $p.ExitCode; Out = $o.Result; Err = $e.Result }
}

# Start-KitDetached FILE ARGS: start a process with no handle of this
# process (Start-Process uses ShellExecute when it has no redirection).
# So a caller that reads the output of the kit through a pipe does not
# wait for the new process. Returns the process.
function Start-KitDetached([string]$File, [string[]]$List, [string]$Dir) {
    $p = Start-Process -FilePath $File -ArgumentList (Join-KitArgs $List) -WorkingDirectory $Dir -WindowStyle Hidden -PassThru
    $null = $p.Handle
    return $p
}

# Write-KitText TEXT: write TEXT to stdout as UTF-8 bytes, with no change.
function Write-KitText([string]$Text) {
    $b = $Utf8.GetBytes($Text)
    $s = [Console]::OpenStandardOutput()
    $s.Write($b, 0, $b.Length)
    $s.Flush()
}

function Get-SessionDir([string]$Run, [string]$Name) {
    if ($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { Stop-Kit 2 "bad session name: $Name" }
    return (Join-Path (Join-Path $Run 'sessions') $Name)
}

function Read-State([string]$Dir, [string]$Key) {
    $f = Join-Path $Dir $Key
    if (-not (Test-Path -LiteralPath $f)) { return '' }
    return ([IO.File]::ReadAllText($f)).Trim()
}

function Write-State([string]$Dir, [string]$Key, [string]$Value) {
    [IO.File]::WriteAllText((Join-Path $Dir $Key), "$Value`n", $Utf8)
}

# Get-StartTicks PID: the start time of a process in UTC ticks, or 0.
function Get-StartTicks([int]$ProcessId) {
    $p = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $p) { return [long]0 }
    try { return [long]$p.StartTime.ToUniversalTime().Ticks } catch { return [long]0 }
}

# Add-SessionPid: record a pid in RUN\pids\ (the file PID holds
# "LABEL<TAB>TICKS") and in the pids file of the session (one line
# "PID LABEL<TAB>TICKS"). TICKS is the start time of the process in UTC
# ticks, so that a stop does not stop a reused pid. This is a private copy
# of Add-KitPid of lib.ps1, with the start time.
function Add-SessionPid([string]$Run, [string]$Dir, [int]$ProcessId, [string]$Label) {
    if ($ProcessId -le 0) { return }
    $ticks = Get-StartTicks $ProcessId
    $d = Join-Path $Run 'pids'
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    [IO.File]::WriteAllText((Join-Path $d "$ProcessId"), "$Label`t$ticks`n", $Utf8)
    [IO.File]::AppendAllText((Join-Path $Dir 'pids'), "$ProcessId $Label`t$ticks`n", $Utf8)
}

# Get-LineTicks LINE: the TICKS at the end of "... LABEL<TAB>TICKS", or 0.
function Get-LineTicks([string]$Line) {
    $t = $Line.Trim() -split "`t"
    if ($t.Count -gt 1 -and $t[-1] -match '^\d+$') { return [long]$t[-1] }
    return [long]0
}

# Update-SessionPids RUN DIR: record each process below the agent that is
# not recorded yet. A child must start after its parent, because Windows
# reuses pids and keeps the parent pid of a process after the parent ends.
function Update-SessionPids([string]$Run, [string]$Dir) {
    $root = Read-State $Dir 'pid'
    if ($root -notmatch '^\d+$') { return }
    $known = @{}
    $pf = Join-Path $Dir 'pids'
    if (Test-Path -LiteralPath $pf) {
        foreach ($line in [IO.File]::ReadAllLines($pf)) { $known[($line -split ' ')[0]] = $true }
    }
    try {
        $all = @(Get-CimInstance -ClassName Win32_Process -Property ProcessId, ParentProcessId, CreationDate -ErrorAction Stop)
    } catch { return }
    $kids = @{}
    $made = @{}
    foreach ($p in $all) {
        $pp = [string]$p.ParentProcessId
        if (-not $kids.ContainsKey($pp)) { $kids[$pp] = @() }
        $kids[$pp] += [string]$p.ProcessId
        $made[[string]$p.ProcessId] = $p.CreationDate
    }
    $name = Split-Path -Leaf $Dir
    $todo = New-Object System.Collections.Queue
    $todo.Enqueue($root)
    $seen = @{}
    $seen[$root] = $true
    while ($todo.Count -gt 0) {
        $cur = $todo.Dequeue()
        if (-not $kids.ContainsKey($cur)) { continue }
        foreach ($c in $kids[$cur]) {
            if ($seen.ContainsKey($c)) { continue }
            if ($made[$cur] -and $made[$c] -and $made[$c] -lt $made[$cur]) { continue }
            $seen[$c] = $true
            $todo.Enqueue($c)
            if (-not $known.ContainsKey($c)) { Add-SessionPid $Run $Dir ([int]$c) "session $name agent-child" }
        }
    }
}

function Find-KitPython {
    $c = @()
    if ($env:KIT_PYTHON) { $c += $env:KIT_PYTHON }
    foreach ($n in 'python', 'python3') {
        $g = Get-Command $n -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        # The python.exe in WindowsApps only opens the Store.
        if ($g -and $g.Source -notmatch '\\WindowsApps\\') { $c += $g.Source }
    }
    foreach ($py in $c) {
        if (-not (Test-Path -LiteralPath $py)) { continue }
        $r = Invoke-KitNative $py @('-c', 'import winpty, pyte, wcwidth')
        if ($r.Code -eq 0) { return $py }
    }
    return ''
}

function Find-Psmux {
    foreach ($n in 'psmux', 'pmux') {
        $g = Get-Command $n -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($g) { return $g.Source }
    }
    return ''
}

# Get-AgentArgv AGENT CMD: the command line of the session as a list. A
# .cmd or .bat runs through cmd.exe, a .ps1 through this PowerShell.
function Get-AgentArgv([string]$Agent, [string]$Cmd) {
    $ps = (Get-Process -Id $PID).Path
    if ($Cmd) { return @($ps, '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $Cmd) }
    $g = Get-Command $Agent -ErrorAction SilentlyContinue | Where-Object { $_.CommandType -in 'Application', 'ExternalScript' } | Select-Object -First 1
    if (-not $g) { Stop-Kit 3 "needs ${Agent}: not on PATH" }
    $path = $g.Source
    $ext = [IO.Path]::GetExtension($path).ToLowerInvariant()
    if ($ext -in '.cmd', '.bat') {
        $comspec = if ($env:ComSpec) { $env:ComSpec } else { Join-Path $env:SystemRoot 'System32\cmd.exe' }
        return @($comspec, '/d', '/c', $path)
    }
    if ($ext -eq '.ps1') { return @($ps, '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $path) }
    return @($path)
}

function Set-PsmuxEnv([string]$Dir) {
    $env:PSMUX_DATA_DIR = (Join-Path $Dir 'psmux')
    $env:PSMUX_NO_WARM = '1'
}

function Invoke-Psmux([string]$Dir, [string[]]$List) {
    Set-PsmuxEnv $Dir
    $exe = Read-State $Dir 'psmux-exe'
    $sock = Read-State $Dir 'socket'
    return (Invoke-KitNative $exe (@('-L', $sock) + $List))
}

function Invoke-Conpty([string]$Dir, [string[]]$List) {
    $py = Read-State $Dir 'python'
    $drv = Join-Path $script:KitRoot 'scenarios\conpty.py'
    return (Invoke-KitNative $py (@('-I', $drv, (Read-State $Dir 'pipe')) + $List))
}

function Start-Session([string[]]$A) {
    if ($A.Count -lt 2) { Show-Usage }
    $name = $A[0]; $agent = $A[1]
    $via = ''; $cmd = ''
    $i = 2
    while ($i -lt $A.Count) {
        # Accept --via, -Via and -Via:VALUE.
        $o = ([string]$A[$i]).TrimStart('-')
        $v = $null
        if ($o -match '^([A-Za-z]+):(.*)$') { $o = $Matches[1]; $v = $Matches[2] }
        $o = $o.ToLowerInvariant()
        if ($o -notin 'via', 'cmd') { Show-Usage }
        if ($null -eq $v) {
            if ($i + 1 -ge $A.Count) { Show-Usage }
            $v = $A[$i + 1]; $i += 2
        } else { $i += 1 }
        if ($o -eq 'via') { $via = $v } else { $cmd = $v }
    }
    if ($via -notin 'conpty', 'psmux') { Stop-Kit 2 "bad backend: '$via' (use conpty or psmux)" }
    $run = Get-KitRunDir
    $dir = Get-SessionDir $run $name
    if (Test-Path -LiteralPath $dir) { Stop-Kit 2 "the session exists: $name" }

    $py = ''; $psmux = ''
    if ($via -eq 'conpty') {
        $py = Find-KitPython
        if (-not $py) { Stop-Kit 3 'needs a Python with pywinpty and pyte (set KIT_PYTHON)' }
    } else {
        $psmux = Find-Psmux
        if (-not $psmux) { Stop-Kit 3 'needs psmux on PATH' }
    }
    $argv = Get-AgentArgv $agent $cmd

    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $work = Join-Path $dir 'work'
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    Write-State $dir 'backend' $via
    Write-State $dir 'work' $work
    Write-State $dir 'agent' $agent
    $tag = 'kit-' + $name + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)

    if ($via -eq 'conpty') {
        $pipe = '\\.\pipe\' + $tag
        Write-State $dir 'python' $py
        Write-State $dir 'pipe' $pipe
        $ready = Join-Path $dir 'ready.json'
        $drv = Join-Path $script:KitRoot 'scenarios\conpty.py'
        # "detach" starts the driver with no handle of this process, in a
        # new process group, and out of the job of the caller when the job
        # lets it. Then it exits.
        $list = @('-I', $drv, 'detach', $pipe, "$Cols", "$Rows", '--cwd', $work, '--ready', $ready, '--') + $argv
        $d = Invoke-KitNative $py $list
        if ($d.Code -ne 0) { Stop-SessionDir $run $dir; Stop-Kit 1 "the ConPTY driver did not start: $($d.Err.Trim())" }
        $lp = 0
        foreach ($line in ($d.Out -split "`r?`n")) {
            if ($line -match '^pid (\d+)$') { $lp = [int]$Matches[1]; Add-SessionPid $run $dir $lp "session $name conpty-launcher" }
            if ($line -match '^breakaway (yes|no)$') { Write-State $dir 'breakaway' $Matches[1] }
        }
        $end = (Get-Date).AddSeconds(30)
        while (-not (Test-Path -LiteralPath $ready)) {
            if ((Get-Date) -gt $end) { break }
            Start-Sleep -Milliseconds 50
        }
        if (-not (Test-Path -LiteralPath $ready)) {
            Stop-SessionDir $run $dir
            Stop-Kit 1 'the ConPTY driver did not start in 30 s'
        }
        $r = [IO.File]::ReadAllText($ready) | ConvertFrom-Json
        if ($r.error) { Stop-SessionDir $run $dir; Stop-Kit 1 "the ConPTY driver failed: $($r.error)" }
        if ([int]$r.server -ne $lp) { Add-SessionPid $run $dir ([int]$r.server) "session $name conpty-server" }
        Add-SessionPid $run $dir ([int]$r.agent) "session $name agent"
        Write-State $dir 'pid' ([string]$r.agent)
    } else {
        Write-State $dir 'psmux-exe' $psmux
        Write-State $dir 'socket' $tag
        Set-PsmuxEnv $dir
        New-Item -ItemType Directory -Force -Path $env:PSMUX_DATA_DIR | Out-Null
        # psmux runs a command of two or more words with no shell, and one
        # word through the shell of the pane. So one program runs through
        # cmd.exe.
        $tail = $argv
        if ($argv.Count -eq 1) { $tail = @('cmd.exe', '/d', '/c', $argv[0]) }
        $list = @('-L', $tag, 'new-session', '-d', '-s', $name, '-x', "$Cols", '-y', "$Rows", '-c', $work, '--') + $tail
        $p = Start-KitDetached $psmux $list $work
        if (-not $p.WaitForExit(30000)) {
            Add-SessionPid $run $dir $p.Id "session $name psmux-client"
            Stop-SessionDir $run $dir
            Stop-Kit 1 'psmux new-session did not return in 30 s'
        }
        if ($p.ExitCode -ne 0) { Stop-SessionDir $run $dir; Stop-Kit 1 "psmux new-session failed (exit $($p.ExitCode))" }
        foreach ($f in Get-ChildItem -LiteralPath $env:PSMUX_DATA_DIR -Filter '*.pid' -ErrorAction SilentlyContinue) {
            $v = ([IO.File]::ReadAllText($f.FullName)).Trim() -split ':'
            if ($v[0] -match '^\d+$') { Add-SessionPid $run $dir ([int]$v[0]) "session $name psmux-server" }
        }
        $r = $null
        for ($k = 0; $k -lt 50; $k++) {
            $r = Invoke-Psmux $dir @('display-message', '-p', '-t', $name, '#{pane_pid}')
            if ($r.Code -eq 0 -and $r.Out.Trim() -match '^\d+$') { break }
            Start-Sleep -Milliseconds 100
        }
        if ($r.Out.Trim() -notmatch '^\d+$') { Stop-SessionDir $run $dir; Stop-Kit 1 "psmux gave no pane pid: $($r.Err.Trim())" }
        Add-SessionPid $run $dir ([int]$r.Out.Trim()) "session $name agent"
        Write-State $dir 'pid' $r.Out.Trim()
    }
    Update-SessionPids $run $dir
    Write-Output "session: $name $via $work"
}

function Get-Screen([string]$Dir) {
    $b = Read-State $Dir 'backend'
    if ($b -eq 'conpty') { $r = Invoke-Conpty $Dir @('screen') }
    else { $r = Invoke-Psmux $Dir @('capture-pane', '-p', '-t', (Split-Path -Leaf $Dir)) }
    if ($r.Code -ne 0) { Stop-Kit 1 "no screen: $($r.Err.Trim())" }
    return $r.Out
}

function Send-ToSession([string]$Dir, [string]$Mode, [string]$Value) {
    $b = Read-State $Dir 'backend'
    $name = Split-Path -Leaf $Dir
    if ($b -eq 'conpty') {
        $r = Invoke-Conpty $Dir @($Mode, $Value)
    } elseif ($Mode -eq 'send') {
        $r = Invoke-Psmux $Dir @('send-keys', '-t', $name, '-l', '--', $Value)
    } else {
        # The tmux key name goes as it is: Enter, not C-m (psmux in
        # PowerShell types C-m as the text ^M).
        $r = Invoke-Psmux $Dir @('send-keys', '-t', $name, '--', $Value)
    }
    if ($r.Code -ne 0) { Stop-Kit 1 "${Mode}: $($r.Err.Trim())" }
}

# Test-SessionPid PID TICKS SINCE: $true when PID runs and is the process
# that the kit recorded. Windows reuses pids. With TICKS (the recorded
# start time), the start time must be the same. With no TICKS (a pid file
# in the old format), the process must not start after SINCE, the time
# when the pid was recorded.
function Test-SessionPid([int]$ProcessId, [long]$Ticks, [datetime]$Since) {
    $p = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $p) { return $false }
    try { $st = $p.StartTime } catch { return $false }
    if ($Ticks -gt 0) { return ([long]$st.ToUniversalTime().Ticks -eq $Ticks) }
    return ($st -le $Since.AddSeconds(2))
}

function Stop-SessionPid([int]$ProcessId, [long]$Ticks, [datetime]$Since) {
    if (Test-SessionPid $ProcessId $Ticks $Since) {
        Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
    }
}

function Stop-SessionDir([string]$Run, [string]$Dir) {
    Update-SessionPids $Run $Dir
    $b = Read-State $Dir 'backend'
    if ($b -eq 'conpty' -and (Read-State $Dir 'pipe')) {
        $null = Invoke-Conpty $Dir @('stop')
    } elseif ($b -eq 'psmux' -and (Read-State $Dir 'socket')) {
        $null = Invoke-Psmux $Dir @('kill-server')
    }
    $pf = Join-Path $Dir 'pids'
    if (Test-Path -LiteralPath $pf) {
        $since = (Get-Item -LiteralPath $pf).LastWriteTime
        foreach ($line in [IO.File]::ReadAllLines($pf)) {
            $id = ($line -split ' ')[0]
            if ($id -match '^\d+$') { Stop-SessionPid ([int]$id) (Get-LineTicks $line) $since }
        }
    }
    Write-State $Dir 'stopped' (Get-Date).ToString('o')
}

function Get-Session([string[]]$A, [int]$Need) {
    if ($A.Count -lt $Need) { Show-Usage }
    $run = Get-KitRunDir
    $dir = Get-SessionDir $run $A[0]
    if (-not (Test-Path -LiteralPath (Join-Path $dir 'backend'))) { Stop-Kit 2 "no session: $($A[0])" }
    # Each command records the new processes below the agent.
    Update-SessionPids $run $dir
    return $dir
}

$sub = if ($args.Count -gt 0) { [string]$args[0] } else { '' }
$rest = @()
if ($args.Count -gt 1) { $rest = @($args[1..($args.Count - 1)] | ForEach-Object { [string]$_ }) }

switch ($sub) {
    'start' { Start-Session $rest; exit 0 }
    'send' {
        $d = Get-Session $rest 2
        Send-ToSession $d 'send' $rest[1]
        exit 0
    }
    'key' {
        $d = Get-Session $rest 2
        $k = $rest[1]
        if ($k -notmatch '^(Enter|Escape|Tab|BSpace|Up|Down|Left|Right|C-c|C-d|.)$') { Stop-Kit 2 "unknown key: $k" }
        Send-ToSession $d 'key' $k
        exit 0
    }
    'screen' {
        $d = Get-Session $rest 1
        Write-KitText (Get-Screen $d)
        exit 0
    }
    'wait' {
        $d = Get-Session $rest 3
        $re = $rest[1]
        $sec = 0
        if (-not [int]::TryParse($rest[2], [ref]$sec)) { Stop-Kit 2 "bad seconds: $($rest[2])" }
        $end = (Get-Date).AddSeconds($sec)
        $last = ''
        while ($true) {
            $last = Get-Screen $d
            if ([regex]::IsMatch($last, $re, 'Multiline')) { Update-SessionPids (Get-KitRunDir) $d; exit 0 }
            if ((Get-Date) -ge $end) { break }
            Start-Sleep -Milliseconds 300
        }
        $f = Join-Path $d 'last.screen'
        [IO.File]::WriteAllText($f, $last, $Utf8)
        Stop-Kit 1 "wait: no match for '$re' in $sec s; the last screen is in $f"
    }
    'stop' {
        if ($rest.Count -lt 1) { Show-Usage }
        $run = Get-KitRunDir
        if ($rest[0] -eq '--all' -or $rest[0] -eq '-all') {
            $sd = Join-Path $run 'sessions'
            if (Test-Path -LiteralPath $sd) {
                foreach ($s in Get-ChildItem -LiteralPath $sd -Directory) { Stop-SessionDir $run $s.FullName }
            }
            # Also the pids that a killed kit left: only the pids in RUN\pids\.
            $pd = Join-Path $run 'pids'
            if (Test-Path -LiteralPath $pd) {
                foreach ($f in Get-ChildItem -LiteralPath $pd -File) {
                    if ($f.Name -match '^\d+$') {
                        $ticks = Get-LineTicks ([IO.File]::ReadAllText($f.FullName))
                        Stop-SessionPid ([int]$f.Name) $ticks $f.LastWriteTime
                    }
                }
            }
            exit 0
        }
        $d = Get-Session $rest 1
        Stop-SessionDir $run $d
        exit 0
    }
    default { Show-Usage }
}
