# Shared functions of the agent kit on Windows. Dot-source it:
#   . (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'lib.ps1')
# It must run in Windows PowerShell 5.1 and in PowerShell 7.

$script:KitDir = Split-Path -Parent $PSCommandPath
$script:KitRoot = Split-Path -Parent (Split-Path -Parent $script:KitDir)

# Stop-Kit CODE TEXT: write "kit: TEXT" on stderr and exit with CODE.
# The text is not scrubbed: it can hold a path that the agent must use.
function Stop-Kit([int]$Code, [string]$Text) {
    [Console]::Error.WriteLine("kit: $Text")
    exit $Code
}

# Get-KitVersion: the version from the file VERSION of a release kit, else
# from the release manifest, else "dev".
function Get-KitVersion {
    $vf = Join-Path $script:KitRoot 'VERSION'
    if (Test-Path -LiteralPath $vf -PathType Leaf) {
        $v = (Get-Content -LiteralPath $vf -TotalCount 1)
        if ($v) { return ([string]$v).Trim() }
    }
    $m = Join-Path $script:KitRoot '.release-please-manifest.json'
    if (Test-Path -LiteralPath $m) {
        $j = Get-Content -Raw -LiteralPath $m | ConvertFrom-Json
        $v = $j.'.'
        if ($v) { return [string]$v }
    }
    return 'dev'
}

# Get-KitRunDir: the path of the current run folder, from
# $env:AGENT_SIGNALS_RUN or the file .agent-signals-run in the current
# folder. With no run, it exits 2.
function Get-KitRunDir {
    $r = $env:AGENT_SIGNALS_RUN
    if (-not $r -and (Test-Path -LiteralPath '.agent-signals-run')) {
        $r = (Get-Content -LiteralPath '.agent-signals-run' -TotalCount 1)
    }
    if (-not $r) { Stop-Kit 2 "no run: do 'kit start' first" }
    if (-not (Test-Path -LiteralPath $r -PathType Container)) { Stop-Kit 2 "the run folder does not exist: $r" }
    return $r
}

# Add-KitPid RUN PID LABEL: record a pid that the kit started. The kit
# stops only the pids in RUN\pids\, never a process found by its name.
# The file RUN\pids\PID holds "LABEL<tab>START", where START is the start
# time of the process in UTC ticks, so that a reused pid does not count.
function Add-KitPid([string]$Run, [int]$ProcessId, [string]$Label) {
    $d = Join-Path $Run 'pids'
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    $t = Get-KitProcessStart $ProcessId
    Set-Content -LiteralPath (Join-Path $d "$ProcessId") -Value (($Label -replace "[`t`r`n]+", ' ') + "`t" + $t)
}

# Get-KitProcessStart PID: the start time of the process in UTC ticks, or
# '' when it does not run or Windows does not give the time.
function Get-KitProcessStart([int]$ProcessId) {
    try { return [string](Get-Process -Id $ProcessId -ErrorAction Stop).StartTime.ToUniversalTime().Ticks } catch { return '' }
}

# Test-KitPidOurs RUN PID: true when the process of RUN\pids\PID runs and
# has the start time of the file, so that it is the process that the kit
# started and not a new process with a reused pid.
function Test-KitPidOurs([string]$Run, [int]$ProcessId) {
    $f = Join-Path (Join-Path $Run 'pids') "$ProcessId"
    $now = Get-KitProcessStart $ProcessId
    if (-not $now) { return $false }
    if (-not (Test-Path -LiteralPath $f)) { return $true }
    $parts = ([string](Get-Content -LiteralPath $f -TotalCount 1)) -split "`t"
    if ($parts.Count -lt 2 -or -not $parts[1]) { return $true }
    return ($parts[1] -eq $now)
}

# ---- Helpers of the Windows commands (doctor, start, plan, step, check,
# edit). They read no login file, no settings value and no transcript.
# A function that returns a list returns it item by item: call it in @().

# The scrub functions: Invoke-Scrub, Get-ScrubDefaults, Get-WordPattern.
. (Join-Path $script:KitRoot 'tools\scrub.ps1')

# The agents of the doctor, as in doctor.sh, and their commands. The first
# command is the preferred one. Only the agents with a
# probes\<agent>\windows.ps1 have a process pattern.
$script:KitAgentCommands = [ordered]@{
    'claude'   = @('claude')
    'codex'    = @('codex')
    'agy'      = @('agy')
    'cursor'   = @('cursor-agent', 'agent')
    'gemini'   = @('gemini')
    'copilot'  = @('copilot')
    'opencode' = @('opencode')
}
# The npm package of each agent, for the version in package.json (fact 047).
$script:KitAgentPackages = @{
    'claude'   = '@anthropic-ai\claude-code'
    'codex'    = '@openai\codex'
    'gemini'   = '@google\gemini-cli'
    'copilot'  = '@github\copilot'
    'opencode' = 'opencode-ai'
}

# Get-KitTime: the UTC time in the form 20261101T153847Z.
function Get-KitTime {
    return (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
}

# Get-KitSha256 FILE: the SHA-256 of the file, in lower case.
function Get-KitSha256([string]$File) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $File).Hash.ToLowerInvariant()
}

# Find-KitRunDir: the run folder as Get-KitRunDir finds it, or $null when
# there is no run. It does not exit.
function Find-KitRunDir {
    $r = $env:AGENT_SIGNALS_RUN
    if (-not $r -and (Test-Path -LiteralPath '.agent-signals-run')) {
        $r = (Get-Content -LiteralPath '.agent-signals-run' -TotalCount 1)
    }
    if ($r -and (Test-Path -LiteralPath $r -PathType Container)) { return $r }
    return $null
}

# Write-KitText FILE TEXT: write UTF-8 with no byte order mark.
function Write-KitText([string]$File, [string]$Text) {
    [IO.File]::WriteAllText($File, $Text, (New-Object System.Text.UTF8Encoding $false))
}

# Read-KitText FILE: the text of the file, or '' when it does not exist.
function Read-KitText([string]$File) {
    if ($File -and (Test-Path -LiteralPath $File -PathType Leaf)) {
        return [IO.File]::ReadAllText($File, (New-Object System.Text.UTF8Encoding $false))
    }
    return ''
}

# Get-KitHomes: the raw home folders of this account. The kit compares
# them and writes them to no file.
function Get-KitHomes {
    $list = @()
    foreach ($h in @($env:SCRUB_HOME, $HOME, $env:USERPROFILE)) {
        if ($h -and ($list -notcontains $h)) { $list += $h }
    }
    return $list
}

# ConvertTo-KitScrubbed TEXT: the text after tools\scrub.ps1, for each
# home folder of Get-KitHomes.
function ConvertTo-KitScrubbed([string]$Text) {
    $d = Get-ScrubDefaults
    # The longest home folder first, so that a home folder below another
    # home folder changes to ~ as a whole.
    $homes = @(Get-KitHomes | Sort-Object { $_.Length } -Descending)
    if ($homes.Count -eq 0) { $homes = @('') }
    $s = (Invoke-Scrub $Text $homes[0] $d.User $d.HostName).Text
    for ($i = 1; $i -lt $homes.Count; $i++) { $s = (Invoke-Scrub $s $homes[$i] '' '').Text }
    return $s
}

# ConvertTo-KitField TEXT: one field of a manifest line, with no tab and
# no line end.
function ConvertTo-KitField([string]$Text) {
    return ($Text -replace "[`t`r`n]+", ' ')
}

# Add-KitManifest RUN FIELD...: append one line to RUN\manifest.tsv.
function Add-KitManifest([string]$Run, [string[]]$Fields) {
    $line = (@($Fields | ForEach-Object { ConvertTo-KitField $_ }) -join "`t") + "`n"
    [IO.File]::AppendAllText((Join-Path $Run 'manifest.tsv'), $line, (New-Object System.Text.UTF8Encoding $false))
}

# Read-KitManifest RUN: the lines of RUN\manifest.tsv, each as an array of
# fields.
function Read-KitManifest([string]$Run) {
    foreach ($l in ((Read-KitText (Join-Path $Run 'manifest.tsv')) -split "`r?`n")) {
        if ($l) { , ($l -split "`t") }
    }
}

# Get-KitMeta RUN KEY: the value of the line "meta KEY VALUE", or ''.
function Get-KitMeta([string]$Run, [string]$Key) {
    $v = ''
    foreach ($f in @(Read-KitManifest $Run)) {
        if ($f.Count -ge 3 -and $f[0] -eq 'meta' -and $f[1] -eq $Key) { $v = $f[2] }
    }
    return $v
}

# Read-KitSteps: the lines of the step list as objects. The properties
# are the names of the header line, so a new column changes nothing.
# KIT_STEPS names another step list (the tests use it).
function Read-KitSteps {
    $file = $env:KIT_STEPS
    if (-not $file) { $file = Join-Path $script:KitDir 'steps.tsv' }
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { Stop-Kit 1 "no step list: $file" }
    $head = $null
    foreach ($l in ((Read-KitText $file) -split "`r?`n")) {
        if (-not $l -or $l.StartsWith('#')) { continue }
        $f = $l -split "`t"
        if (-not $head) { $head = $f; continue }
        $h = [ordered]@{}
        for ($i = 0; $i -lt $head.Count; $i++) {
            $v = ''
            if ($i -lt $f.Count) { $v = $f[$i] }
            $h[$head[$i]] = $v
        }
        New-Object PSObject -Property $h
    }
}

# Get-KitOsInfo: os, cpu and the OS version, as the summary prints them.
function Get-KitOsInfo {
    $a = $env:PROCESSOR_ARCHITEW6432
    if (-not $a) { $a = $env:PROCESSOR_ARCHITECTURE }
    switch ($a) {
        'AMD64' { $cpu = 'x86_64' }
        'ARM64' { $cpu = 'arm64' }
        'x86' { $cpu = 'i686' }
        default { if ($a) { $cpu = $a.ToLowerInvariant() } else { $cpu = 'unknown' } }
    }
    $ver = 'unknown'
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $ver = ('{0} {1}' -f ([string]$os.Caption).Trim(), $os.Version)
    } catch { $ver = [Environment]::OSVersion.VersionString }
    return New-Object PSObject -Property @{ Os = 'windows'; Cpu = $cpu; Version = $ver }
}

# Format-KitArg TEXT: one argument for a Windows command line.
function Format-KitArg([string]$Text) {
    if ($Text -and $Text -notmatch '[\s"]') { return $Text }
    $t = $Text -replace '(\\*)"', '$1$1\"'
    $t = $t -replace '(\\+)$', '$1$1'
    return '"' + $t + '"'
}

# Invoke-KitNative EXE ARG...: run a native program and return its exit
# code and output. In Windows PowerShell 5.1, a line on stderr is an error
# record, and "Stop" ends the script. So the function uses "Continue".
function Invoke-KitNative([string]$Exe, [string[]]$ArgList) {
    $ErrorActionPreference = 'Continue'
    $out = @(& $Exe @ArgList 2>&1 | ForEach-Object { "$_" })
    return New-Object PSObject -Property @{ Code = $LASTEXITCODE; Out = ($out -join "`n") }
}

# Start-KitProcess RUN LABEL EXE ARGUMENTS OUT ERR [CWD]: start a program
# with its output in files, and record its pid in RUN\pids\.
function Start-KitProcess([string]$Run, [string]$Label, [string]$Exe, [string]$Arguments, [string]$Out, [string]$Err, [string]$Cwd) {
    if (-not $Cwd) { $Cwd = (Get-Location).ProviderPath }
    $sp = @{
        FilePath = $Exe; NoNewWindow = $true; PassThru = $true; WorkingDirectory = $Cwd
        RedirectStandardOutput = $Out; RedirectStandardError = $Err
    }
    if ($Arguments) { $sp['ArgumentList'] = $Arguments }
    $p = Start-Process @sp
    # The handle keeps the exit code readable after the process stops.
    $null = $p.Handle
    Add-KitPid $Run $p.Id $Label
    return $p
}

# Wait-KitProcess RUN PROCESS SECONDS: wait for the process. At the time
# limit, stop it and its children (taskkill /T on its own pid), and return
# -1. Else return its exit code. Then delete its pid file.
function Wait-KitProcess([string]$Run, $Process, [int]$Seconds) {
    $code = -1
    if ($Process.WaitForExit($Seconds * 1000)) {
        $Process.WaitForExit()
        $code = $Process.ExitCode
    } else {
        $null = Invoke-KitNative 'taskkill.exe' @('/T', '/F', '/PID', "$($Process.Id)")
        $null = $Process.WaitForExit(10000)
    }
    if ($Process.HasExited) {
        Remove-Item -LiteralPath (Join-Path (Join-Path $Run 'pids') "$($Process.Id)") -Force -ErrorAction SilentlyContinue
    }
    return $code
}

# Get-KitCommandFile NAME: the program file of a command on PATH: an .exe
# or a .cmd shim first, a .ps1 shim only when there is no other file.
function Get-KitCommandFile([string]$Name) {
    $app = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($app) { return $app.Source }
    $any = Get-Command $Name -CommandType ExternalScript -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($any) { return $any.Source }
    return $null
}

# Get-KitVersionKey TEXT: a key that sorts version names such as 2.1.316
# and 2026.10.22-27dcf5f in number order.
function Get-KitVersionKey([string]$Text) {
    $parts = @(([regex]::Matches($Text, '[0-9]+')) | Select-Object -First 4 | ForEach-Object { $_.Value.PadLeft(10, '0') })
    return ($parts -join '.')
}

# Get-KitNewest NAME...: the highest version name of the list, or $null.
function Get-KitNewest([string[]]$Names) {
    $n = @($Names | Where-Object { $_ -match '^[0-9]' } | Sort-Object { Get-KitVersionKey $_ } -Descending)
    if ($n.Count -gt 0) { return $n[0] }
    return $null
}

# Get-KitPackageVersion FILE PACKAGE: the version in the package.json of
# an npm package, from a shim in the npm prefix or a file in the package.
function Get-KitPackageVersion([string]$File, [string]$Package) {
    if (-not $Package) { return $null }
    $dirs = @()
    $dirs += (Join-Path (Join-Path (Split-Path -Parent $File) 'node_modules') $Package)
    $m = [regex]::Match($File, '(?i)^(.*[\\/]node_modules[\\/]' + [regex]::Escape($Package).Replace('\\', '[\\/]') + ')([\\/]|$)')
    if ($m.Success) { $dirs += $m.Groups[1].Value }
    foreach ($p in $dirs) {
        $j = Join-Path $p 'package.json'
        if (Test-Path -LiteralPath $j -PathType Leaf) {
            try {
                $v = (Read-KitText $j | ConvertFrom-Json).version
                if ($v) { return [string]$v }
            } catch { }
        }
    }
    return $null
}

# Get-KitAgentVersion AGENT FILE: the version from the install path or a
# version file. It never runs the agent. $null when it is not known.
function Get-KitAgentVersion([string]$Agent, [string]$File) {
    $item = Get-Item -LiteralPath $File -Force -ErrorAction SilentlyContinue
    $res = $File
    if ($item -and $item.LinkType -and $item.Target) { $res = [string](@($item.Target)[0]) }
    $up = $env:USERPROFILE
    if (-not $up) { $up = $HOME }
    switch ($Agent) {
        'claude' {
            $m = [regex]::Match($res, '(?i)[\\/]claude[\\/]versions[\\/]([0-9][^\\/]*)')
            if ($m.Success) { return $m.Groups[1].Value }
            # The native install: ~\.local\bin\claude.exe is a copy of one
            # file of ~\.local\share\claude\versions\ (fact 071). The size
            # names the file.
            if ($item -and $item.Name -ieq 'claude.exe') {
                $vd = Join-Path $up '.local\share\claude\versions'
                $same = @(Get-ChildItem -LiteralPath $vd -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Length -eq $item.Length } | ForEach-Object { $_.Name })
                $v = Get-KitNewest $same
                if ($v) { return $v }
            }
        }
        'codex' {
            $m = [regex]::Match($res, '(?i)[\\/]packages[\\/][^\\/]+[\\/]releases[\\/]([0-9][^\\/-]*)')
            if ($m.Success) { return $m.Groups[1].Value }
        }
        'cursor' {
            $m = [regex]::Match($res, '(?i)[\\/]cursor-agent[\\/]versions[\\/]([0-9][^\\/]*)')
            if ($m.Success) { return $m.Groups[1].Value }
            $vd = Join-Path (Split-Path -Parent $res) 'versions'
            $names = @(Get-ChildItem -LiteralPath $vd -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
            $v = Get-KitNewest $names
            if ($v) { return $v }
        }
    }
    return (Get-KitPackageVersion $res $script:KitAgentPackages[$Agent])
}

# Get-KitInstallFiles AGENT: the program files in the install folders of
# the agent. A renamed program, for example claude.exe.old.<ms>.<pid> or
# agy.exe.<hex>.old (fact 071), is not an install.
function Get-KitInstallFiles([string]$Agent) {
    $up = $env:USERPROFILE
    if (-not $up) { $up = $HOME }
    $la = $env:LOCALAPPDATA
    $list = @()
    switch ($Agent) {
        'claude' { $list += (Join-Path $up '.local\bin\claude.exe') }
        'agy' { if ($la) { $list += (Join-Path $la 'agy\bin\agy.exe') } }
        'cursor' {
            if ($la) {
                $list += (Join-Path $la 'cursor-agent\cursor-agent.cmd')
                $list += (Join-Path $la 'cursor-agent\agent.cmd')
            }
        }
        'codex' {
            $ch = $env:CODEX_HOME
            if (-not $ch) { $ch = Join-Path $up '.codex' }
            $rd = Join-Path $ch 'packages\standalone\releases'
            $rel = Get-KitNewest @(Get-ChildItem -LiteralPath $rd -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
            if ($rel) {
                $exe = @(Get-ChildItem -LiteralPath (Join-Path $rd $rel) -Recurse -File -Force -Filter 'codex.exe' -ErrorAction SilentlyContinue | Select-Object -First 1)
                if ($exe.Count -gt 0) { $list += $exe[0].FullName }
            }
        }
    }
    $list | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
}

# Find-KitAgents: the installed agents, as objects with Name, Command (the
# command name, or the file when it is not on PATH), File and Version. It
# finds them on PATH and in the install folders. It never runs an agent.
function Find-KitAgents {
    foreach ($a in $script:KitAgentCommands.Keys) {
        $file = $null
        $cmd = $null
        foreach ($c in $script:KitAgentCommands[$a]) {
            $f = Get-KitCommandFile $c
            # "agent" is Cursor CLI only in a cursor-agent folder.
            if ($f -and $c -eq 'agent' -and $f -notmatch '(?i)cursor-agent') { continue }
            if ($f) { $file = $f; $cmd = $c; break }
        }
        if (-not $file) {
            $i = @(Get-KitInstallFiles $a)
            if ($i.Count -gt 0) { $file = $i[0]; $cmd = $i[0] }
        }
        if (-not $file) { continue }
        $v = Get-KitAgentVersion $a $file
        if (-not $v) { $v = 'unknown' }
        New-Object PSObject -Property @{ Name = $a; Command = $cmd; File = $file; Version = $v }
    }
}

# Get-KitAgentPattern AGENT: the process pattern of probes\AGENT\windows.ps1.
function Get-KitAgentPattern([string]$Agent) {
    $f = Join-Path $script:KitRoot "probes\$Agent\windows.ps1"
    $m = [regex]::Match((Read-KitText $f), "(?m)^\`$script:Pattern = '((?:[^']|'')*)'")
    if ($m.Success) { return $m.Groups[1].Value.Replace("''", "'") }
    return $null
}

# Test-KitPlace DIR: the reasons why DIR must not hold a run folder: in a
# git work tree, in an agent folder, not owned by this account, or
# writable by Everyone, Users, Authenticated Users, Guests or Anonymous.
# No reason means that the place is good.
function Test-KitPlace([string]$Dir) {
    $why = @()
    $full = [IO.Path]::GetFullPath($Dir).TrimEnd('\', '/')
    $d = $full
    while ($d) {
        if (Test-Path -LiteralPath (Join-Path $d '.git')) { $why += 'the folder is in a git work tree'; break }
        $p = Split-Path -Parent $d
        if (-not $p -or $p -eq $d) { break }
        $d = $p
    }
    foreach ($h in @(Get-KitHomes)) {
        foreach ($a in '.claude', '.codex', '.gemini', '.cursor') {
            $ad = [IO.Path]::GetFullPath((Join-Path $h $a)).TrimEnd('\', '/')
            if ($full -ieq $ad -or $full.StartsWith($ad + '\', [StringComparison]::OrdinalIgnoreCase)) {
                $why += "the folder is in ~\$a"
            }
        }
    }
    try {
        $acl = Get-Acl -LiteralPath $full
        $sidType = [System.Security.Principal.SecurityIdentifier]
        $me = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $owner = $acl.GetOwner($sidType)
        $admins = New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-32-544'
        # An elevated administrator makes files that the Administrators
        # group owns.
        $ownOk = ($owner -eq $me.User) -or (($owner -eq $admins) -and ($me.Groups -contains $admins))
        if (-not $ownOk) { $why += 'the folder belongs to another account' }
        $open = @{ 'S-1-1-0' = 'Everyone'; 'S-1-5-32-545' = 'Users'; 'S-1-5-11' = 'Authenticated Users'; 'S-1-5-32-546' = 'Guests'; 'S-1-5-7' = 'Anonymous' }
        # WriteData, AppendData, DeleteSubdirectoriesAndFiles, Delete,
        # ChangePermissions, TakeOwnership, GENERIC_ALL, GENERIC_WRITE.
        $mask = 0x2 -bor 0x4 -bor 0x40 -bor 0x10000 -bor 0x40000 -bor 0x80000 -bor 0x10000000 -bor 0x40000000
        foreach ($r in $acl.GetAccessRules($true, $true, $sidType)) {
            $sid = $r.IdentityReference.Value
            if ([string]$r.AccessControlType -ne 'Allow' -or -not $open.ContainsKey($sid)) { continue }
            if (([int64]$r.FileSystemRights -band $mask) -ne 0) { $why += "$($open[$sid]) can write to the folder" }
        }
    } catch {
        [Console]::Error.WriteLine('kit: the access list was not read: ' + $_.Exception.GetType().Name)
    }
    $why | Select-Object -Unique
}

# The driver packages of the conpty backend, at the versions of the
# scenarios workflow.
$script:KitConptyPackages = @('pywinpty==3.1.2', 'pyte==0.8.2', 'wcwidth==0.9.4', 'psutil==7.2.2')

# Get-KitConptyTool [PYTHON] [RUN]: the program that runs
# scenarios\conpty.py, as an object with Kind ("python" or "uv") and Path.
# The order: PYTHON (from --python), AGENT_SIGNALS_PYTHON, the Python of
# the run (kit start --python), then uv (uv run --with the pinned
# packages), then python on PATH. A Python that the caller names must have
# pywinpty, pyte and psutil. The WindowsApps alias of python is not a
# Python. $null when there is none.
function Get-KitConptyTool([string]$Python, [string]$Run) {
    if (-not $Python) { $Python = $env:AGENT_SIGNALS_PYTHON }
    if (-not $Python -and $Run) {
        $Python = ((Read-KitText (Join-Path $Run '.kit\python')) -split "`r?`n")[0]
    }
    if ($Python) {
        if (Test-Path -LiteralPath $Python -PathType Leaf) {
            return New-Object PSObject -Property @{ Kind = 'python'; Path = (Resolve-Path -LiteralPath $Python).ProviderPath }
        }
        return $null
    }
    $uv = Get-KitCommandFile 'uv'
    if ($uv) { return New-Object PSObject -Property @{ Kind = 'uv'; Path = $uv } }
    foreach ($c in 'python', 'py') {
        $f = Get-KitCommandFile $c
        if ($f -and $f -notmatch '(?i)[\\/]WindowsApps[\\/]') { return New-Object PSObject -Property @{ Kind = 'python'; Path = $f } }
    }
    return $null
}

# Get-KitConptyCommand TOOL: the program and the first arguments that run
# a Python script with the driver packages.
function Get-KitConptyCommand($Tool) {
    if ($Tool.Kind -eq 'uv') {
        $a = 'run --no-project --python 3.12'
        foreach ($p in $script:KitConptyPackages) { $a += " --with $p" }
        return New-Object PSObject -Property @{ Exe = $Tool.Path; Args = "$a python" }
    }
    return New-Object PSObject -Property @{ Exe = $Tool.Path; Args = '' }
}

# Get-KitArgs ARGS: the arguments of a command as strings. kit.ps1 splats
# a single argument as a string, and PowerShell can then pass one $null or
# the characters of the string. This function undoes both. Call it as
#   [string[]]$argv = @(Get-KitArgs $args)
function Get-KitArgs([object[]]$ArgList) {
    $a = @($ArgList | Where-Object { $null -ne $_ })
    if ($a.Count -gt 1 -and @($a | Where-Object { $_ -isnot [char] }).Count -eq 0) { return [string](-join $a) }
    foreach ($x in $a) { [string]$x }
}

# Get-KitOption ARGS NAME: the value after the option NAME (for example
# --python) in ARGS, or ''. The commands read their options by hand, so
# that the spelling is the same as in kit.sh.
function Get-KitOption([object[]]$ArgList, [string]$Name) {
    for ($i = 0; $i -lt $ArgList.Count - 1; $i++) {
        if ([string]$ArgList[$i] -ceq $Name) { return [string]$ArgList[$i + 1] }
    }
    return ''
}

# Get-KitWindowsBackend STEP: the backend of a step on Windows, or $null
# when the step does not run on Windows yet. The probe runs on "none". The
# first run runs on "conpty", the Windows twin of the tmux first run. The
# session steps come with Task 10 of the plan.
function Get-KitWindowsBackend($Step) {
    $w = ''
    if ($Step.PSObject.Properties['windows']) { $w = [string]$Step.windows }
    if ($w -in 'no', 'false', '0') { return $null }
    switch ([string]$Step.kind) {
        'probe' { return 'none' }
        'first-run' { return 'conpty' }
    }
    return $null
}

# Set-KitPrivate DIR: give only this account and SYSTEM access to DIR, as
# mode 0700 does on Unix. It returns the exit code of icacls.
function Set-KitPrivate([string]$Dir) {
    $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $r = Invoke-KitNative 'icacls.exe' @($Dir, '/inheritance:r', '/grant:r', "*${me}:(OI)(CI)F", '*S-1-5-18:(OI)(CI)F')
    return $r.Code
}
