# kit session on Windows: a test session of an agent on the backend conpty
# (scenarios/conpty.py in its serve mode) or psmux (a private psmux
# server). It is the twin of probes/agent/session.sh.
#
#   kit session start NAME AGENT --via conpty|psmux [--cmd CMD] [--home real|throwaway|fixture]
#   kit session send NAME TEXT
#   kit session key NAME KEY...       (tmux names: Enter, Escape, C-c, Tab, 1)
#   kit session screen NAME           (the format of tmux capture-pane -p -J)
#   kit session wait NAME REGEX SECONDS
#   kit session stop NAME
#   kit session stop --all
#
# CMD is a PowerShell command. The agent starts in a new work folder with a
# clean environment: the system variables, PATH, and the profile variables
# (USERPROFILE, HOME, APPDATA, LOCALAPPDATA, TEMP, TMP). With --home
# throwaway (the default, or $env:KIT_HOME), the profile is a new empty
# folder RUN\home\NAME. With --home real, it is the real profile. The kit
# copies no login.
#
# All state is in RUN\sessions\NAME\, so that each command can run in a new
# shell. Only the user can read the folder.
#   backend    conpty or psmux
#   agent      the agent name
#   home-mode  real, throwaway or fixture
#   work       the path of the work folder of the agent, RUN\work\NAME
#   pipe       conpty: the name of the pipe of the driver; pipe.key its key
#   socket     psmux: the name of the private server (psmux -L)
#   pid        the pid of the agent
#   pids       the pids of the session: lines "PID LABEL<tab>START"
#   breakaway  yes when the driver left the job object of the caller
#   last.screen  the last screen that "wait" read
#   stopped    the session has stopped
# START is the start time of the process in UTC ticks. Each started pid is
# also in RUN\pids\PID ("LABEL<tab>START"). A stop ends only these pids,
# and only when the start time is the same: never a process found by its
# name, never a reused pid.
#
# conpty needs a Python with pywinpty, pyte, wcwidth and psutil:
# $env:AGENT_SIGNALS_PYTHON, then RUN\.kit\python, then python on PATH.
# psmux needs psmux on PATH. When one is missing, start exits 3.
#
# Exit codes: 0 ok, 1 fail (also: wait came to its time limit), 2 bad use,
# 3 a needed tool is missing.
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'lib.ps1')

$Cols = 120
$Rows = 40
$Utf8 = New-Object System.Text.UTF8Encoding $false

# The variables that the agent gets from the environment of the kit. They
# are the PASS_VARS of scenarios/conpty.py, with no PSModulePath: a
# PowerShell 7 module path breaks Windows PowerShell 5.1.
$PassVars = @(
    'PATH', 'PATHEXT', 'SystemRoot', 'SystemDrive', 'windir', 'ComSpec',
    'OS', 'NUMBER_OF_PROCESSORS', 'PROCESSOR_ARCHITECTURE',
    'PROCESSOR_IDENTIFIER', 'PROCESSOR_LEVEL', 'PROCESSOR_REVISION',
    'ProgramFiles', 'ProgramFiles(x86)', 'ProgramW6432', 'ProgramData',
    'CommonProgramFiles', 'CommonProgramFiles(x86)', 'CommonProgramW6432',
    'ALLUSERSPROFILE', 'PUBLIC', 'DriverData'
)
# With --home real, these come from the real profile too.
$ProfileVars = @(
    'USERPROFILE', 'HOME', 'HOMEDRIVE', 'HOMEPATH', 'APPDATA', 'LOCALAPPDATA',
    'TEMP', 'TMP', 'USERNAME', 'USERDOMAIN'
)

function Show-Usage {
    [Console]::Error.WriteLine('usage: kit session start NAME AGENT --via conpty|psmux [--cmd CMD] [--home real|throwaway|fixture]')
    [Console]::Error.WriteLine('       kit session send NAME TEXT | key NAME KEY... | screen NAME')
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

# Invoke-KitNative FILE ARGS [ENV] [SECONDS]: run a short command and read
# its output as UTF-8. It returns an object with Code, Out and Err. ENV is
# a hashtable: the whole environment of the command. At the time limit
# (15 s), it stops the command, and Code is -1. The output does not go
# through the PowerShell pipeline, so a line on stderr is not an error
# record, and the console code page does not change the text.
function Invoke-KitNative([string]$File, [string[]]$List, [hashtable]$Environment = $null, [int]$Seconds = 15) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $File
    $psi.Arguments = Join-KitArgs $List
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = $Utf8
    $psi.StandardErrorEncoding = $Utf8
    if ($null -ne $Environment) {
        $psi.EnvironmentVariables.Clear()
        foreach ($k in $Environment.Keys) { $psi.EnvironmentVariables[$k] = [string]$Environment[$k] }
    }
    $p = [System.Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEndAsync()
    $e = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($Seconds * 1000)) {
        try { $p.Kill() } catch { }
        return [pscustomobject]@{ Code = -1; Out = ''; Err = "no exit in $Seconds s: $File" }
    }
    $p.WaitForExit()
    return [pscustomobject]@{ Code = $p.ExitCode; Out = $o.Result; Err = $e.Result }
}

# Start-KitDetached: run a program with no handle of this process, with
# no console, in a new process group, with the environment block ENV, and
# out of the job object of the caller when the job lets it. Then wait for
# it (at most SECONDS). Returns Code (-1 at the time limit), Pid and
# Breakaway.
$SpawnCode = @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class KitSpawn {
    public static int BreakawayError;
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct STARTUPINFO {
        public int cb; public string lpReserved; public string lpDesktop; public string lpTitle;
        public int dwX; public int dwY; public int dwXSize; public int dwYSize;
        public int dwXCountChars; public int dwYCountChars; public int dwFillAttribute; public int dwFlags;
        public short wShowWindow; public short cbReserved2; public IntPtr lpReserved2;
        public IntPtr hStdInput; public IntPtr hStdOutput; public IntPtr hStdError;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_INFORMATION { public IntPtr hProcess; public IntPtr hThread; public int dwProcessId; public int dwThreadId; }
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool CreateProcessW(string app, StringBuilder cmd, IntPtr pa, IntPtr ta, bool inherit,
        uint flags, IntPtr env, string cwd, ref STARTUPINFO si, out PROCESS_INFORMATION pi);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr h, uint ms);
    [DllImport("kernel32.dll")] static extern bool GetExitCodeProcess(IntPtr h, out uint code);
    [DllImport("kernel32.dll")] static extern bool TerminateProcess(IntPtr h, uint code);
    public static int Run(string app, string cmdline, string cwd, string env, uint ms, out bool breakaway, out int pid) {
        uint basef = 0x00000008 | 0x00000200 | 0x00000400;
        IntPtr block = Marshal.StringToHGlobalUni(env);
        try {
            STARTUPINFO si = new STARTUPINFO();
            si.cb = Marshal.SizeOf(typeof(STARTUPINFO));
            PROCESS_INFORMATION pi;
            breakaway = true;
            if (!CreateProcessW(app, new StringBuilder(cmdline), IntPtr.Zero, IntPtr.Zero, false, basef | 0x01000000, block, cwd, ref si, out pi)) {
                breakaway = false;
                BreakawayError = Marshal.GetLastWin32Error();
                if (!CreateProcessW(app, new StringBuilder(cmdline), IntPtr.Zero, IntPtr.Zero, false, basef, block, cwd, ref si, out pi)) {
                    throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
                }
            }
            pid = pi.dwProcessId;
            CloseHandle(pi.hThread);
            int rc = -1;
            if (WaitForSingleObject(pi.hProcess, ms) == 0) {
                uint c;
                GetExitCodeProcess(pi.hProcess, out c);
                rc = (int)c;
            } else {
                TerminateProcess(pi.hProcess, 1);
            }
            CloseHandle(pi.hProcess);
            return rc;
        } finally {
            Marshal.FreeHGlobal(block);
        }
    }
}
'@
function Start-KitDetached([string]$File, [string[]]$List, [string]$Dir, [hashtable]$Environment, [int]$Seconds) {
    if (-not ('KitSpawn' -as [type])) { Add-Type -TypeDefinition $SpawnCode }
    $block = (($Environment.Keys | Sort-Object | ForEach-Object { "$_=$($Environment[$_])" }) -join "`0") + "`0"
    $line = Join-KitArgs (@($File) + $List)
    $away = $false
    $id = 0
    $rc = [KitSpawn]::Run($File, $line, $Dir, $block, [uint32]($Seconds * 1000), [ref]$away, [ref]$id)
    return [pscustomobject]@{ Code = $rc; Pid = $id; Breakaway = $away; Error = [KitSpawn]::BreakawayError }
}

# Write-KitText TEXT: write TEXT to stdout as UTF-8 bytes, with no change.
function Write-KitText([string]$Text) {
    $b = $Utf8.GetBytes($Text)
    $s = [Console]::OpenStandardOutput()
    $s.Write($b, 0, $b.Length)
    $s.Flush()
}

# The name rule of session.sh. It also keeps "." and ":" (the target
# syntax of tmux and psmux) out of a name.
function Test-SessionName([string]$Name) {
    if ($Name -cnotmatch '^[A-Za-z0-9_-]+$') { Stop-Kit 2 "bad session name: $Name" }
    if ($Name.Length -gt 40) { Stop-Kit 2 "the session name is too long: $Name" }
}

function Read-State([string]$Dir, [string]$Key) {
    $f = Join-Path $Dir $Key
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { return '' }
    return ([IO.File]::ReadAllText($f)).Trim()
}

function Write-State([string]$Dir, [string]$Key, [string]$Value) {
    [IO.File]::WriteAllText((Join-Path $Dir $Key), "$Value`n", $Utf8)
}

# Protect-KitDir DIR: only the current user can read DIR and the files in
# it (the twin of chmod 700).
function Protect-KitDir([string]$Dir) {
    $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl = New-Object System.Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($me, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
    Set-Acl -LiteralPath $Dir -AclObject $acl
}

# Add-SessionPid: record a pid in RUN\pids\PID ("LABEL<tab>START", with
# Add-KitPid of lib.ps1) and in the pids file of the session
# ("PID LABEL<tab>START"). A process that has no start time (it has
# ended) is not recorded.
function Add-SessionPid([string]$Run, [string]$Dir, [int]$ProcessId, [string]$Label) {
    if ($ProcessId -le 0) { return }
    $ticks = Get-KitProcessStart $ProcessId
    if (-not $ticks) { return }
    Add-KitPid $Run $ProcessId $Label $ticks
    [IO.File]::AppendAllText((Join-Path $Dir 'pids'), "$ProcessId $Label`t$ticks`n", $Utf8)
}

# Get-LineTicks LINE: the START at the end of "... LABEL<tab>START", or ''.
function Get-LineTicks([string]$Line) {
    $t = $Line.Trim() -split "`t"
    if ($t.Count -gt 1 -and $t[-1] -match '^\d+$') { return $t[-1] }
    return ''
}

# Test-SessionPid RUN PID START: $true when RUN\pids\PID is ours
# (Test-KitPidOurs of lib.ps1) and the process has the start time START
# of the pids file of the session. With no START, the answer is $false:
# the kit stops no process that it cannot identify. So a pid that Windows
# gave again to a later process of the kit does not count for an old
# session.
function Test-SessionPid([string]$Run, [int]$ProcessId, [string]$Ticks) {
    if (-not $Ticks) { return $false }
    if (-not (Test-KitPidOurs $Run $ProcessId)) { return $false }
    return ((Get-KitProcessStart $ProcessId) -eq $Ticks)
}

# Get-RecordedTicks DIR PID: the START of PID in the pids file of the
# session, or ''.
function Get-RecordedTicks([string]$Dir, [string]$ProcessId) {
    $pf = Join-Path $Dir 'pids'
    if (-not (Test-Path -LiteralPath $pf)) { return '' }
    foreach ($line in [IO.File]::ReadAllLines($pf)) {
        if (($line -split ' ')[0] -eq $ProcessId) { return (Get-LineTicks $line) }
    }
    return ''
}

# Update-SessionPids RUN DIR: record each process below the agent that is
# not recorded yet. The agent must still be the recorded process. Each
# process of the walk must start after its parent and after the agent,
# because Windows reuses pids and keeps the parent pid of a process after
# the parent ends.
function Update-SessionPids([string]$Run, [string]$Dir) {
    $root = Read-State $Dir 'pid'
    if ($root -notmatch '^\d+$') { return }
    if (-not (Test-SessionPid $Run ([int]$root) (Get-RecordedTicks $Dir $root))) { return }
    try {
        $all = @(Get-CimInstance -ClassName Win32_Process -Property ProcessId, ParentProcessId, CreationDate -ErrorAction Stop)
    } catch { return }
    $kids = @{}
    $made = @{}
    foreach ($p in $all) {
        $id = [string]$p.ProcessId
        $pp = [string]$p.ParentProcessId
        if (-not $kids.ContainsKey($pp)) { $kids[$pp] = @() }
        $kids[$pp] += $id
        if ($p.CreationDate) { $made[$id] = [long]$p.CreationDate.ToUniversalTime().Ticks }
    }
    if (-not $made.ContainsKey($root)) { return }
    $rootMade = $made[$root]
    $known = @{}
    $pf = Join-Path $Dir 'pids'
    if (Test-Path -LiteralPath $pf) {
        foreach ($line in [IO.File]::ReadAllLines($pf)) { $known[($line -split ' ')[0]] = $true }
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
            if ($seen.ContainsKey($c) -or -not $made.ContainsKey($c)) { continue }
            if ($made[$c] -lt $rootMade -or $made[$c] -lt $made[$cur]) { continue }
            $seen[$c] = $true
            $todo.Enqueue($c)
            if (-not $known.ContainsKey($c)) { Add-SessionPid $Run $Dir ([int]$c) "session $name child" }
        }
    }
}

# Find-KitPython RUN: a Python that imports what the conpty driver needs.
function Find-KitPython([string]$Run) {
    $c = @()
    if ($env:AGENT_SIGNALS_PYTHON) { $c += $env:AGENT_SIGNALS_PYTHON }
    $f = Join-Path $Run '.kit\python'
    if (Test-Path -LiteralPath $f -PathType Leaf) { $c += ([IO.File]::ReadAllLines($f) | Select-Object -First 1) }
    foreach ($n in 'python', 'python3') {
        $g = Get-Command $n -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        # The python.exe in WindowsApps only opens the Store.
        if ($g -and $g.Source -notmatch '\\WindowsApps\\') { $c += $g.Source }
    }
    foreach ($py in $c) {
        if (-not $py -or -not (Test-Path -LiteralPath $py -PathType Leaf)) { continue }
        $r = Invoke-KitNative $py @('-I', '-c', 'import winpty, pyte, wcwidth, psutil')
        if ($r.Code -eq 0) { return $py }
    }
    return ''
}

# Find-Psmux: the real psmux.exe. A Chocolatey shim starts the real
# program as its child, so the kit uses the program that the shim names.
function Find-Psmux {
    foreach ($n in 'psmux', 'pmux') {
        $g = Get-Command $n -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $g) { continue }
        $path = $g.Source
        if ($path -match '\\chocolatey\\bin\\[^\\]+$') {
            $real = Join-Path (Split-Path -Parent (Split-Path -Parent $path)) "lib\psmux\tools\$n.exe"
            if (Test-Path -LiteralPath $real -PathType Leaf) { $path = $real }
        }
        return $path
    }
    return ''
}

# Get-AgentArgv AGENT CMD: the command line of the session as a list. A
# .cmd or .bat runs through cmd.exe, a .ps1 through this PowerShell.
function Get-AgentArgv([string]$Agent, [string]$Cmd) {
    $ps = (Get-Process -Id $PID).Path
    if ($Cmd) { return @($ps, '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $Cmd) }
    # The command names of the agent come from lib.ps1: the Cursor CLI is
    # cursor-agent or agent.
    $names = if ($script:KitAgentCommands.Contains($Agent)) { @($script:KitAgentCommands[$Agent]) } else { @($Agent) }
    $g = $null
    foreach ($n in $names) {
        $g = Get-Command $n -ErrorAction SilentlyContinue | Where-Object { $_.CommandType -in 'Application', 'ExternalScript' } | Select-Object -First 1
        # "agent" is the Cursor CLI only in a cursor-agent folder.
        if ($g -and $n -eq 'agent' -and $g.Source -notmatch '(?i)cursor-agent') { $g = $null }
        if ($g) { break }
    }
    if (-not $g) { Stop-Kit 3 "not installed: $Agent" }
    $path = $g.Source
    $ext = [IO.Path]::GetExtension($path).ToLowerInvariant()
    if ($ext -in '.cmd', '.bat') {
        $comspec = if ($env:ComSpec) { $env:ComSpec } else { Join-Path $env:SystemRoot 'System32\cmd.exe' }
        return @($comspec, '/d', '/c', $path)
    }
    if ($ext -eq '.ps1') { return @($ps, '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $path) }
    return @($path)
}

# Get-SessionEnv MODE HOME: the clean environment of the agent. No
# AGENT_SIGNALS_*, KIT_*, CLAUDECODE or TERM_PROGRAM of the caller goes in.
function Get-SessionEnv([string]$Mode, [string]$HomeDir) {
    $e = @{}
    foreach ($v in $PassVars) {
        $x = [Environment]::GetEnvironmentVariable($v)
        if ($x) { $e[$v] = $x }
    }
    if ($Mode -eq 'real') {
        foreach ($v in $ProfileVars) {
            $x = [Environment]::GetEnvironmentVariable($v)
            if ($x) { $e[$v] = $x }
        }
    } else {
        $drive = [IO.Path]::GetPathRoot($HomeDir).TrimEnd('\')
        $e['USERPROFILE'] = $HomeDir
        $e['HOME'] = $HomeDir
        $e['HOMEDRIVE'] = $drive
        $e['HOMEPATH'] = $HomeDir.Substring($drive.Length)
        $e['APPDATA'] = Join-Path $HomeDir 'AppData\Roaming'
        $e['LOCALAPPDATA'] = Join-Path $HomeDir 'AppData\Local'
        $e['TEMP'] = Join-Path $HomeDir 'AppData\Local\Temp'
        $e['TMP'] = $e['TEMP']
        $e['USERNAME'] = 'dev'
        # Codex on Windows does not find its home from USERPROFILE: with no
        # CODEX_HOME, a fixture run read no config in this folder.
        $e['CODEX_HOME'] = Join-Path $HomeDir '.codex'
        foreach ($d in $e['APPDATA'], $e['TEMP'], $e['CODEX_HOME']) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
    }
    return $e
}

function Get-PsmuxEnv([string]$Dir) {
    $e = @{}
    $f = Join-Path $Dir 'env.json'
    $j = [IO.File]::ReadAllText($f) | ConvertFrom-Json
    foreach ($p in $j.PSObject.Properties) { $e[$p.Name] = [string]$p.Value }
    $e['PSMUX_DATA_DIR'] = Join-Path $Dir 'psmux'
    $e['PSMUX_NO_WARM'] = '1'
    return $e
}

function Invoke-Psmux([string]$Dir, [string[]]$List) {
    $exe = Read-State $Dir 'psmux-exe'
    $sock = Read-State $Dir 'socket'
    return (Invoke-KitNative $exe (@('-L', $sock) + $List) (Get-PsmuxEnv $Dir))
}

function Invoke-Conpty([string]$Dir, [string[]]$List) {
    $py = Read-State $Dir 'python'
    $drv = Join-Path $script:KitRoot 'scenarios\conpty.py'
    return (Invoke-KitNative $py (@('-I', $drv, '--key', (Join-Path $Dir 'pipe.key'), (Read-State $Dir 'pipe')) + $List))
}

function Start-Session([string[]]$A) {
    if ($A.Count -lt 2) { Show-Usage }
    $name = $A[0]; $agent = $A[1]
    Test-SessionName $name
    if ($agent -cnotmatch '^[A-Za-z0-9._-]+$') { Stop-Kit 2 "bad agent name: $agent" }
    $via = ''; $cmd = ''
    $mode = if ($env:KIT_HOME) { $env:KIT_HOME } else { 'throwaway' }
    $i = 2
    while ($i -lt $A.Count) {
        # Accept --via, -Via and -Via:VALUE.
        $o = ([string]$A[$i]).TrimStart('-')
        $v = $null
        if ($o -match '^([A-Za-z]+):(.*)$') { $o = $Matches[1]; $v = $Matches[2] }
        $o = $o.ToLowerInvariant()
        if ($o -notin 'via', 'cmd', 'home') { Show-Usage }
        if ($null -eq $v) {
            if ($i + 1 -ge $A.Count) { Show-Usage }
            $v = $A[$i + 1]; $i += 2
        } else { $i += 1 }
        switch ($o) { 'via' { $via = $v } 'cmd' { $cmd = $v } 'home' { $mode = $v } }
    }
    if (-not $via) { Stop-Kit 2 'give --via conpty or --via psmux' }
    if ($via -notin 'conpty', 'psmux') { Stop-Kit 2 "unknown backend: $via" }
    if ($mode -notin 'real', 'throwaway', 'fixture') { Stop-Kit 2 "--home is real, throwaway or fixture: $mode" }
    $run = Get-KitRunDir
    $dir = Join-Path (Join-Path $run 'sessions') $name

    $py = ''; $psmux = ''
    if ($via -eq 'conpty') {
        $py = Find-KitPython $run
        if (-not $py) { Stop-Kit 3 'needs a Python with pywinpty, pyte, wcwidth and psutil (set AGENT_SIGNALS_PYTHON)' }
    } else {
        $psmux = Find-Psmux
        if (-not $psmux) { Stop-Kit 3 'needs psmux on PATH' }
    }
    $argv = Get-AgentArgv $agent $cmd

    if (Test-Path -LiteralPath $dir) {
        if (-not (Test-Path -LiteralPath (Join-Path $dir 'stopped'))) { Stop-Kit 2 "the session exists: $name" }
        Remove-Item -Recurse -Force -LiteralPath $dir
    }
    $work = Join-Path (Join-Path $run 'work') $name
    if (Test-Path -LiteralPath $work) { Remove-Item -Recurse -Force -LiteralPath $work }
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Protect-KitDir $dir
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    $homeDir = Join-Path (Join-Path $run 'home') $name
    if ($mode -ne 'real') {
        if (Test-Path -LiteralPath $homeDir) { Remove-Item -Recurse -Force -LiteralPath $homeDir }
        New-Item -ItemType Directory -Force -Path $homeDir | Out-Null
    }
    Write-State $dir 'backend' $via
    Write-State $dir 'agent' $agent
    Write-State $dir 'home-mode' $mode
    Write-State $dir 'work' $work
    [IO.File]::WriteAllText((Join-Path $dir 'pids'), '', $Utf8)
    $envAgent = Get-SessionEnv $mode $homeDir
    if ($mode -eq 'fixture' -and -not (Get-KitLoginSkip 'fixture' 'login' $agent)) {
        # fake-model.py needs only the standard library of Python.
        $fakePy = if ($py) { $py } else { Find-KitPython $run }
        if (-not $fakePy) { $fakePy = (Get-Command python -ErrorAction SilentlyContinue).Source }
        if (-not $fakePy) { Stop-Kit 3 'needs python' }
        $fakePid = Join-Path $dir 'fake-model.pid'
        $fakeEnv = Join-Path $dir 'fake-model.env'
        $fakeArgs = '"{0}" --agent {1} --home "{2}" --env-file "{3}" --log "{4}" --pid-file "{5}"' -f (Join-Path $PSScriptRoot 'fake-model.py'), $agent, $homeDir, $fakeEnv, (Join-Path $dir 'fake-model.log'), $fakePid
        $fake = Start-Process -FilePath $fakePy -ArgumentList $fakeArgs -PassThru -WindowStyle Hidden
        Add-SessionPid $run $dir $fake.Id "session $name fake model"
        $fakeEnd = (Get-Date).AddSeconds(30)
        # fake-model.py writes the file of variables after the settings files.
        while (-not (Test-Path -LiteralPath $fakeEnv -PathType Leaf)) {
            if ((Get-Date) -gt $fakeEnd) { Stop-Kit 1 'the fake model did not start' }
            Start-Sleep -Milliseconds 100
        }
        # The Python of a venv is a launcher: the server is its child.
        $serverPid = [int](Get-Content -LiteralPath $fakePid -TotalCount 1)
        if ($serverPid -ne $fake.Id) { Add-SessionPid $run $dir $serverPid "session $name fake model" }
        foreach ($line in [IO.File]::ReadAllLines($fakeEnv)) {
            $i = $line.IndexOf('=')
            if ($i -gt 0) { $envAgent[$line.Substring(0, $i)] = $line.Substring($i + 1) }
        }
    }
    $tag = 'kit-' + $name + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)

    if ($via -eq 'conpty') {
        $pipe = '\\.\pipe\' + $tag
        Write-State $dir 'python' $py
        Write-State $dir 'pipe' $pipe
        $keyBytes = New-Object byte[] 32
        [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($keyBytes)
        $keyFile = Join-Path $dir 'pipe.key'
        [IO.File]::WriteAllText($keyFile, (($keyBytes | ForEach-Object { $_.ToString('x2') }) -join ''), $Utf8)
        $ready = Join-Path $dir 'ready.json'
        $drv = Join-Path $script:KitRoot 'scenarios\conpty.py'
        # "detach" starts the driver with no handle of this process, in a
        # new process group, and out of the job of the caller when the job
        # lets it. It waits for the driver, then exits. The driver and the
        # agent get the clean environment.
        $list = @('-I', $drv, 'detach', $pipe, "$Cols", "$Rows", '--cwd', $work, '--ready', $ready, '--key', $keyFile, '--') + $argv
        $d = Invoke-KitNative $py $list $envAgent 45
        $server = 0; $agentPid = 0
        foreach ($line in ($d.Out -split "`r?`n")) {
            if ($line -match '^pid (\d+)$') { Add-SessionPid $run $dir ([int]$Matches[1]) "session $name driver" }
            if ($line -match '^breakaway (yes|no)$') { Write-State $dir 'breakaway' $Matches[1] }
            if ($line -match '^server (\d+)$') { $server = [int]$Matches[1] }
            if ($line -match '^agent (\d+)$') { $agentPid = [int]$Matches[1] }
        }
        if ($server -gt 0) { Add-SessionPid $run $dir $server "session $name server" }
        if ($agentPid -gt 0) { Add-SessionPid $run $dir $agentPid "session $name agent" }
        if ($d.Code -ne 0 -or $agentPid -le 0) {
            Stop-SessionDir $run $dir
            Stop-Kit 1 "the ConPTY driver did not start: $($d.Err.Trim())"
        }
        Write-State $dir 'pid' "$agentPid"
    } else {
        Write-State $dir 'psmux-exe' $psmux
        Write-State $dir 'socket' $tag
        [IO.File]::WriteAllText((Join-Path $dir 'env.json'), ($envAgent | ConvertTo-Json -Compress), $Utf8)
        $envPsmux = Get-PsmuxEnv $dir
        New-Item -ItemType Directory -Force -Path $envPsmux['PSMUX_DATA_DIR'] | Out-Null
        # psmux runs a command of two or more words with no shell, and one
        # word through the shell of the pane. So one program runs through
        # cmd.exe. The session inside the private server is "kit", as in
        # session.sh.
        $tail = $argv
        if ($argv.Count -eq 1) { $tail = @('cmd.exe', '/d', '/c', $argv[0]) }
        $list = @('-L', $tag, 'new-session', '-d', '-s', 'kit', '-x', "$Cols", '-y', "$Rows", '-c', $work, '--') + $tail
        $s = Start-KitDetached $psmux $list $work $envPsmux 30
        Write-State $dir 'breakaway' $(if ($s.Breakaway) { 'yes' } else { 'no' })
        if (-not $s.Breakaway) { Write-State $dir 'breakaway-error' "$($s.Error)" }
        foreach ($f in Get-ChildItem -LiteralPath $envPsmux['PSMUX_DATA_DIR'] -Filter '*.pid' -ErrorAction SilentlyContinue) {
            $v = ([IO.File]::ReadAllText($f.FullName)).Trim() -split ':'
            if ($v[0] -match '^\d+$') { Add-SessionPid $run $dir ([int]$v[0]) "session $name server" }
        }
        if ($s.Code -ne 0) {
            Stop-SessionDir $run $dir
            Stop-Kit 1 "psmux new-session failed (exit $($s.Code))"
        }
        if (-not ([IO.File]::ReadAllText((Join-Path $dir 'pids')) -match " session $name server`t")) {
            Stop-SessionDir $run $dir
            Stop-Kit 1 'psmux started no server that the kit can see'
        }
        $r = $null
        for ($k = 0; $k -lt 50; $k++) {
            $r = Invoke-Psmux $dir @('display-message', '-p', '-t', 'kit', '#{pane_pid}')
            if ($r.Code -eq 0 -and $r.Out.Trim() -match '^\d+$') { break }
            Start-Sleep -Milliseconds 100
        }
        if ($r.Out.Trim() -notmatch '^\d+$') { Stop-SessionDir $run $dir; Stop-Kit 1 "psmux gave no pane pid: $($r.Err.Trim())" }
        Add-SessionPid $run $dir ([int]$r.Out.Trim()) "session $name agent"
        Write-State $dir 'pid' $r.Out.Trim()
    }
    if ((Read-State $dir 'breakaway') -eq 'no') {
        [Console]::Error.WriteLine('kit: the session may end with this tool call (the job of the caller keeps its processes)')
    }
    Update-SessionPids $run $dir
    Write-Output "session: $name $via $work"
}

function Get-Screen([string]$Dir) {
    $b = Read-State $Dir 'backend'
    if ($b -eq 'conpty') {
        $r = Invoke-Conpty $Dir @('screen')
        if ($r.Code -ne 0) { Stop-Kit 1 "no screen: $($r.Err.Trim())" }
        return $r.Out
    }
    $r = Invoke-Psmux $Dir @('capture-pane', '-p', '-J', '-t', 'kit')
    if ($r.Code -ne 0) { Stop-Kit 1 "no screen: $($r.Err.Trim())" }
    # The format of session.sh: no trailing spaces, and "\n" line ends.
    $lines = $r.Out -split "`r?`n"
    if ($lines.Count -gt 0 -and $lines[-1] -eq '') { $lines = $lines[0..($lines.Count - 2)] }
    return ((($lines | ForEach-Object { $_.TrimEnd(' ') }) -join "`n") + "`n")
}

function Send-ToSession([string]$Dir, [string]$Mode, [string]$Value) {
    $b = Read-State $Dir 'backend'
    if ($b -eq 'conpty') {
        $r = Invoke-Conpty $Dir @($Mode, $Value)
    } elseif ($Mode -eq 'send') {
        $r = Invoke-Psmux $Dir @('send-keys', '-t', 'kit', '-l', '--', $Value)
    } else {
        # The tmux key name goes as it is: Enter, not C-m (psmux in
        # PowerShell types C-m as the text ^M).
        $r = Invoke-Psmux $Dir @('send-keys', '-t', 'kit', '--', $Value)
    }
    if ($r.Code -ne 0) { Stop-Kit 1 "${Mode}: $($r.Err.Trim())" }
}

# Stop-SessionDir RUN DIR: stop the session in DIR. It stops only the pids
# of the session with their start time, removes their pid files, the work
# folder and the throwaway home, and writes "stopped".
function Stop-SessionDir([string]$Run, [string]$Dir) {
    if (Test-Path -LiteralPath (Join-Path $Dir 'stopped')) { return }
    $name = Split-Path -Leaf $Dir
    Update-SessionPids $Run $Dir
    $b = Read-State $Dir 'backend'
    if ($b -eq 'conpty' -and (Read-State $Dir 'pipe')) {
        $null = Invoke-Conpty $Dir @('stop')
    } elseif ($b -eq 'psmux' -and (Read-State $Dir 'socket') -and (Test-Path -LiteralPath (Join-Path $Dir 'env.json'))) {
        $null = Invoke-Psmux $Dir @('kill-server')
    }
    $pf = Join-Path $Dir 'pids'
    if (Test-Path -LiteralPath $pf) {
        foreach ($line in [IO.File]::ReadAllLines($pf)) {
            $id = ($line -split ' ')[0]
            if ($id -notmatch '^\d+$') { continue }
            $ticks = Get-LineTicks $line
            for ($n = 0; $n -lt 20 -and (Test-SessionPid $Run ([int]$id) $ticks); $n++) { Start-Sleep -Milliseconds 100 }
            if (Test-SessionPid $Run ([int]$id) $ticks) {
                Write-Output "stop: $id $((($line -split ' ', 2)[1] -split "`t")[0])"
                Stop-Process -Id ([int]$id) -Force -ErrorAction SilentlyContinue
            }
            # Remove the pid file only when it is the file of this process,
            # not the file of a later process with the same pid.
            $pidFile = Join-Path (Join-Path $Run 'pids') $id
            $fileTicks = ''
            if (Test-Path -LiteralPath $pidFile -PathType Leaf) { $fileTicks = Get-LineTicks ([IO.File]::ReadAllText($pidFile)) }
            if (-not $fileTicks -or $fileTicks -eq $ticks) { Remove-Item -Force -LiteralPath $pidFile -ErrorAction SilentlyContinue }
        }
    }
    $work = Read-State $Dir 'work'
    # The agent can hold a file in the folder for a short time after it ends.
    foreach ($d in $work, (Join-Path (Join-Path $Run 'home') $name)) {
        if (-not $d -or -not (Test-Path -LiteralPath $d)) { continue }
        for ($n = 0; $n -lt 10; $n++) {
            try { Remove-Item -Recurse -Force -LiteralPath $d -ErrorAction Stop; break } catch { Start-Sleep -Milliseconds 300 }
        }
        # "kit check" fails on each file that stays.
        if (Test-Path -LiteralPath $d) { Write-Output "session: $name left files in a folder" }
    }
    Write-State $Dir 'stopped' (Get-Date).ToUniversalTime().ToString('o')
    Write-Output "session: $name stopped"
}

function Get-Session([string[]]$A, [int]$Need, [switch]$Running) {
    if ($A.Count -lt $Need) { Show-Usage }
    Test-SessionName $A[0]
    $run = Get-KitRunDir
    $dir = Join-Path (Join-Path $run 'sessions') $A[0]
    if (-not (Test-Path -LiteralPath (Join-Path $dir 'backend'))) { Stop-Kit 2 "no session: $($A[0])" }
    if ($Running -and (Test-Path -LiteralPath (Join-Path $dir 'stopped'))) { Stop-Kit 1 "the session has stopped: $($A[0])" }
    # Each command records the new processes below the agent.
    if ($Running) { Update-SessionPids $run $dir }
    return $dir
}

$sub = if ($args.Count -gt 0) { [string]$args[0] } else { '' }
$rest = @($args | Select-Object -Skip 1 | ForEach-Object { [string]$_ })

switch ($sub) {
    'start' { Start-Session $rest; exit 0 }
    'send' {
        if ($rest.Count -ne 2) { Show-Usage }
        $d = Get-Session $rest 2 -Running
        Send-ToSession $d 'send' $rest[1]
        exit 0
    }
    'key' {
        if ($rest.Count -lt 2) { Show-Usage }
        $keys = @($rest | Select-Object -Skip 1)
        foreach ($k in $keys) {
            if ($k -cnotmatch '^(Enter|Escape|Tab|BSpace|Up|Down|Left|Right|C-c|C-d|C-u|.)$') { Stop-Kit 2 "unknown key: $k" }
        }
        $d = Get-Session $rest 2 -Running
        foreach ($k in $keys) { Send-ToSession $d 'key' $k }
        exit 0
    }
    'screen' {
        if ($rest.Count -ne 1) { Show-Usage }
        $d = Get-Session $rest 1 -Running
        Write-KitText (Get-Screen $d)
        exit 0
    }
    'wait' {
        if ($rest.Count -ne 3) { Show-Usage }
        $re = $rest[1]
        $sec = 0
        if ($rest[2] -notmatch '^\d+$' -or -not [int]::TryParse($rest[2], [ref]$sec)) { Stop-Kit 2 "SECONDS is a number: $($rest[2])" }
        if ($sec -lt 1 -or $sec -gt 3600) { Stop-Kit 2 "SECONDS is 1 to 3600: $sec" }
        try { $null = [regex]::new($re) } catch { Stop-Kit 2 "bad REGEX: $re" }
        $d = Get-Session $rest 3 -Running
        $f = Join-Path $d 'last.screen'
        $end = (Get-Date).AddSeconds($sec)
        $last = ''
        while ($true) {
            $last = Get-Screen $d
            if ([regex]::IsMatch($last, $re, 'Multiline')) {
                [IO.File]::WriteAllText($f, $last, $Utf8)
                Update-SessionPids (Get-KitRunDir) $d
                exit 0
            }
            if ((Get-Date) -ge $end) { break }
            Start-Sleep -Milliseconds 300
        }
        [IO.File]::WriteAllText($f, $last, $Utf8)
        [Console]::Error.WriteLine("kit: no match in $sec s: $re")
        Write-Output $f
        exit 1
    }
    'stop' {
        if ($rest.Count -ne 1) { Show-Usage }
        $run = Get-KitRunDir
        if ($rest[0] -eq '--all') {
            $sd = Join-Path $run 'sessions'
            if (Test-Path -LiteralPath $sd) {
                foreach ($s in Get-ChildItem -LiteralPath $sd -Directory) {
                    if (-not (Test-Path -LiteralPath (Join-Path $s.FullName 'backend'))) { continue }
                    if (Test-Path -LiteralPath (Join-Path $s.FullName 'stopped')) { continue }
                    Stop-SessionDir $run $s.FullName
                }
            }
            # Also the pids that a killed kit left: only the pids in
            # RUN\pids\, and only with the same start time.
            $pd = Join-Path $run 'pids'
            if (Test-Path -LiteralPath $pd) {
                foreach ($f in Get-ChildItem -LiteralPath $pd -File) {
                    if ($f.Name -notmatch '^\d+$') { continue }
                    $text = [IO.File]::ReadAllText($f.FullName)
                    if (Test-KitPidOurs $run ([int]$f.Name)) {
                        Write-Output "stop: $($f.Name) $(($text -split "`t")[0])"
                        Stop-Process -Id ([int]$f.Name) -Force -ErrorAction SilentlyContinue
                    }
                    Remove-Item -Force -LiteralPath $f.FullName -ErrorAction SilentlyContinue
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
