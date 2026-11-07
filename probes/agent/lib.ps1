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

# Get-KitRunDir: the full path of the current run folder. It reads, in
# this order: $env:AGENT_SIGNALS_RUN, then the newer of the two files
# .agent-signals-run in the current folder and in the kit root, as
# kit_run_dir of lib.sh does. kit start writes both files. With no run, it
# exits 2.
function Get-KitRunDir {
    $r = Get-KitRunPointer
    if (-not $r) { Stop-Kit 2 "no run: do 'kit start' first" }
    if (-not (Test-Path -LiteralPath $r -PathType Container)) { Stop-Kit 2 "the run folder does not exist: $r" }
    return (Resolve-Path -LiteralPath $r).ProviderPath
}

# Get-KitRunPointer: the run path that the environment or a
# .agent-signals-run file names, or ''. The file is UTF-8, so that a path
# with letters outside ASCII works also in Windows PowerShell 5.1.
function Get-KitRunPointer {
    if ($env:AGENT_SIGNALS_RUN) { return $env:AGENT_SIGNALS_RUN }
    $files = @('.agent-signals-run', (Join-Path $script:KitRoot '.agent-signals-run'))
    # A file can stay from an earlier run, so the newer file comes first.
    if ((Test-Path -LiteralPath $files[0] -PathType Leaf) -and (Test-Path -LiteralPath $files[1] -PathType Leaf) -and
        ((Get-Item -LiteralPath $files[1]).LastWriteTimeUtc -gt (Get-Item -LiteralPath $files[0]).LastWriteTimeUtc)) {
        [array]::Reverse($files)
    }
    foreach ($f in $files) {
        if (Test-Path -LiteralPath $f -PathType Leaf) {
            $l = ([IO.File]::ReadAllText((Resolve-Path -LiteralPath $f).ProviderPath, (New-Object System.Text.UTF8Encoding $false)) -split "`r?`n")[0].Trim()
            if ($l) { return $l }
        }
    }
    return ''
}

# Add-KitPid RUN PID LABEL [START]: record a pid that the kit started. The
# kit stops only the pids in RUN\pids\, never a process found by its name.
# The file RUN\pids\PID holds "LABEL<tab>START", where START is the start
# time of the process in UTC ticks, so that a reused pid does not count.
# With no START, the function reads the start time of the process.
function Add-KitPid([string]$Run, [int]$ProcessId, [string]$Label, [string]$Start) {
    $d = Join-Path $Run 'pids'
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    if (-not $Start) { $Start = Get-KitProcessStart $ProcessId }
    Set-Content -LiteralPath (Join-Path $d "$ProcessId") -Value (($Label -replace "[`t`r`n]+", ' ') + "`t" + $Start)
}

# Get-KitProcessStart PID: the start time of the process in UTC ticks, or
# '' when it does not run or Windows does not give the time.
function Get-KitProcessStart([int]$ProcessId) {
    try { return [string](Get-Process -Id $ProcessId -ErrorAction Stop).StartTime.ToUniversalTime().Ticks } catch { return '' }
}

# Test-KitPidOurs RUN PID: true when the process of RUN\pids\PID runs and
# has the start time of the file, so that it is the process that the kit
# started and not a new process with a reused pid. A pid file with no
# start time is not ours, as in kit_pid_ours of lib.sh.
function Test-KitPidOurs([string]$Run, [int]$ProcessId) {
    $f = Join-Path (Join-Path $Run 'pids') "$ProcessId"
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { return $false }
    $parts = ([string](Get-Content -LiteralPath $f -TotalCount 1)) -split "`t"
    if ($parts.Count -lt 2 -or -not $parts[1].Trim()) { return $false }
    $now = Get-KitProcessStart $ProcessId
    if (-not $now) { return $false }
    return ($parts[1].Trim() -eq $now)
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

# Find-KitRunDir: the full path of the run folder as Get-KitRunDir finds
# it, or $null when there is no run. It does not exit.
function Find-KitRunDir {
    $r = Get-KitRunPointer
    if ($r -and (Test-Path -LiteralPath $r -PathType Container)) { return (Resolve-Path -LiteralPath $r).ProviderPath }
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

# Get-KitPathPattern PATH: a pattern for PATH in any case, with one or more
# slashes or backslashes between its parts.
function Get-KitPathPattern([string]$Path) {
    $parts = @($Path.TrimEnd('/', '\') -split '[\\/]+' | ForEach-Object { [regex]::Escape($_) })
    return '(?i)(?<![A-Za-z0-9_.-])' + ($parts -join '[\\/]+') + '(?![A-Za-z0-9._-])'
}

# Get-KitLiteralPaths: the raw folders that the scrub cannot find by
# itself, with the text that replaces each one, longest first: the run
# folder (<run>), the kit root (<kit>), and the OneDrive folders
# (<onedrive>). tools\scrub.ps1 ends a path at a space, so a folder such as
# "OneDrive - Contoso" needs this. The kit writes these values nowhere.
function Get-KitLiteralPaths {
    $list = @()
    $run = $env:KIT_RUN
    if (-not $run) { $run = Find-KitRunDir }
    if ($run) { $list += New-Object PSObject -Property @{ Kind = 'the run folder'; Path = [string]$run; New = '<run>' } }
    $list += New-Object PSObject -Property @{ Kind = 'the kit folder'; Path = [string]$script:KitRoot; New = '<kit>' }
    foreach ($v in 'OneDrive', 'OneDriveCommercial', 'OneDriveConsumer') {
        $x = [Environment]::GetEnvironmentVariable($v)
        if ($x) { $list += New-Object PSObject -Property @{ Kind = "the $v folder"; Path = $x; New = '<onedrive>' } }
    }
    $list | Where-Object { $_.Path.TrimEnd('/', '\').Length -ge 4 } | Sort-Object { $_.Path.Length } -Descending
}

# ConvertTo-KitScrubbed TEXT: the text after the literal folders of
# Get-KitLiteralPaths and after tools\scrub.ps1, for each home folder of
# Get-KitHomes.
function ConvertTo-KitScrubbed([string]$Text) {
    $d = Get-ScrubDefaults
    $s = $Text
    foreach ($p in @(Get-KitLiteralPaths)) {
        $s = [regex]::Replace($s, (Get-KitPathPattern $p.Path), $p.New.Replace('$', '$$'))
    }
    # The longest home folder first, so that a home folder below another
    # home folder changes to ~ as a whole.
    $homes = @(Get-KitHomes | Sort-Object { $_.Length } -Descending)
    if ($homes.Count -eq 0) { $homes = @('') }
    $s = (Invoke-Scrub $s $homes[0] $d.User $d.HostName).Text
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
    $start = ''
    try { $start = [string]$p.StartTime.ToUniversalTime().Ticks } catch { }
    Add-KitPid $Run $p.Id $Label $start
    return $p
}

# Get-KitDescendants PROCESS: the pids of the processes below PROCESS that
# started after it, deepest first. A process that started before the root
# is not below it, even when its parent pid is the pid of the root: Windows
# gave that pid again.
function Get-KitDescendants($Process) {
    $rootStart = $null
    try { $rootStart = $Process.StartTime } catch { return }
    $all = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
    $found = New-Object System.Collections.ArrayList
    $queue = New-Object System.Collections.Queue
    $queue.Enqueue([int]$Process.Id)
    while ($queue.Count -gt 0) {
        $parent = $queue.Dequeue()
        foreach ($c in $all) {
            if ([int]$c.ParentProcessId -ne $parent -or [int]$c.ProcessId -eq $parent) { continue }
            if (-not $c.CreationDate -or $c.CreationDate -lt $rootStart) { continue }
            if ($found -contains [int]$c.ProcessId) { continue }
            [void]$found.Add([int]$c.ProcessId)
            $queue.Enqueue([int]$c.ProcessId)
        }
    }
    $found.Reverse()
    $found
}

# Stop-KitTree PROCESS: stop PROCESS and the processes below it that
# started after it. It stops no other process.
function Stop-KitTree($Process) {
    $kids = @(Get-KitDescendants $Process)
    try { $Process.Kill() } catch { }
    foreach ($k in $kids) { Stop-Process -Id $k -Force -ErrorAction SilentlyContinue }
}

# Wait-KitProcess RUN PROCESS SECONDS: wait for the process. At the time
# limit, stop it and the processes below it (Stop-KitTree). It returns an
# object with Code (the exit code, or 1 at the time limit) and TimedOut.
# Then it deletes the pid file of the process.
function Wait-KitProcess([string]$Run, $Process, [int]$Seconds) {
    $timedOut = $false
    $code = 1
    if ($Process.WaitForExit($Seconds * 1000)) {
        $Process.WaitForExit()
        $code = $Process.ExitCode
    } else {
        $timedOut = $true
        Stop-KitTree $Process
        $null = $Process.WaitForExit(10000)
    }
    if ($Process.HasExited) {
        Remove-Item -LiteralPath (Join-Path (Join-Path $Run 'pids') "$($Process.Id)") -Force -ErrorAction SilentlyContinue
    }
    return New-Object PSObject -Property @{ Code = $code; TimedOut = $timedOut }
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

# The accounts that may write to the folder of a run, as SIDs: SYSTEM,
# Administrators, CREATOR OWNER and TrustedInstaller. The current account
# comes on top. Any other account with a write right fails.
$script:KitTrustedSids = @(
    'S-1-5-18', 'S-1-5-32-544', 'S-1-3-0',
    'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'
)

# The wide groups that a folder can hold as explicit entries: Everyone,
# Anonymous, Interactive, Authenticated Users, Users and Guests. On
# windows-11-arm, a new folder in RUNNER_TEMP has such entries, and
# "icacls /inheritance:r" does not remove them. So the kit removes them
# with /remove:g.
$script:KitWideSids = @('S-1-1-0', 'S-1-5-7', 'S-1-5-4', 'S-1-5-11', 'S-1-5-32-545', 'S-1-5-32-546')

# Get-KitPrivateCommand DIR: the icacls command that gives only this
# account and SYSTEM access to DIR. An explicit entry of Administrators
# stays. It holds the text <sid>, not the SID of the account: the hint can
# go to a public log. "whoami /user" prints the SID.
function Get-KitPrivateCommand([string]$Dir) {
    $wide = (@($script:KitWideSids | ForEach-Object { "*$_" }) -join ' ')
    return ('icacls "{0}" /inheritance:r /remove:g {1} /grant:r "*<sid>:(OI)(CI)F" "*S-1-5-18:(OI)(CI)F"' -f $Dir.TrimEnd('\'), $wide)
}

# Test-KitPlace DIR: the reasons why DIR must not hold a run folder: in a
# git work tree, in an agent folder, an owner that is not this account, or
# a write right for an account that is not in the allow list. No reason
# means that the place is good.
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
    # A folder that does not exist yet has no access list to check.
    if (-not (Test-Path -LiteralPath $full -PathType Container)) { return ($why | Select-Object -Unique) }
    try {
        $acl = Get-Acl -LiteralPath $full
        $sidType = [System.Security.Principal.SecurityIdentifier]
        $me = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $ok = @($script:KitTrustedSids) + @([string]$me.User.Value)
        # WriteData, AppendData, WriteExtendedAttributes,
        # DeleteSubdirectoriesAndFiles, WriteAttributes, Delete,
        # ChangePermissions, TakeOwnership, GENERIC_ALL, GENERIC_WRITE.
        $mask = 0x2 -bor 0x4 -bor 0x10 -bor 0x40 -bor 0x100 -bor 0x10000 -bor 0x40000 -bor 0x80000 -bor 0x10000000 -bor 0x40000000
        $dacl = $true
        foreach ($r in $acl.GetAccessRules($true, $true, $sidType)) {
            $sid = [string]$r.IdentityReference.Value
            if ([string]$r.AccessControlType -ne 'Allow' -or $ok -contains $sid) { continue }
            if (([int64]$r.FileSystemRights -band $mask) -eq 0) { continue }
            $name = $sid
            try { $name = $r.IdentityReference.Translate([System.Security.Principal.NTAccount]).Value } catch { }
            $why += "$name can write to the folder"
            $dacl = $false
        }
        # The owner: this account, the default owner of its token, or the
        # Administrators group (an elevated administrator makes files that
        # the group owns) when the access list is good.
        $owner = [string]$acl.GetOwner($sidType).Value
        $admins = 'S-1-5-32-544'
        $ownOk = ($owner -eq [string]$me.User.Value) -or ($me.Owner -and $owner -eq [string]$me.Owner.Value)
        if (-not $ownOk -and $owner -eq $admins -and $dacl) {
            $ownOk = @($me.Groups | Where-Object { $_.Value -eq $admins }).Count -gt 0
        }
        if (-not $ownOk) { $why += 'the folder belongs to another account' }
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

# The backends of the Windows kit. A step line lists its backends in the
# column "backends"; "-" or an empty value means "none" (the probe).
$script:KitWindowsBackends = @('none', 'conpty', 'psmux', 'operator')
# The kinds and backends that this kit runs on Windows now. The kinds
# permission, new-chat and interrupt run steps\session-step.ps1 in a test
# session. "resume" does not run on Windows yet: a stop of a test session
# deletes its work folder and its home, so a new start cannot resume it.
$script:KitWindowsRuns = @{
    'probe'        = @('none')
    'first-run'    = @('conpty')
    'permission'   = @('conpty', 'psmux')
    'new-chat'     = @('conpty', 'psmux')
    'interrupt'    = @('conpty', 'psmux')
    'real-session' = @('operator')
}

# Get-KitStepBackends STEP: the backends of the step line that are Windows
# backends, in the order of the line. The column "windows" (when the step
# list has it) hides a line with "no", "false" or "0".
function Get-KitStepBackends($Step) {
    if ($Step.PSObject.Properties['windows'] -and ([string]$Step.windows) -in 'no', 'false', '0') { return }
    $col = ([string]$Step.backends).Trim()
    if (-not $col -or $col -eq '-') { $col = 'none' }
    foreach ($b in ($col -split ',')) {
        $b = $b.Trim()
        if ($script:KitWindowsBackends -contains $b) { $b }
    }
}

# Test-KitStepRuns STEP BACKEND: true when this kit runs the step on the
# backend on Windows now.
function Test-KitStepRuns($Step, [string]$Backend) {
    $k = [string]$Step.kind
    return ($script:KitWindowsRuns.ContainsKey($k) -and ($script:KitWindowsRuns[$k] -contains $Backend))
}


# Clear-KitWelcomeBox TEXT [VALUES]: TEXT with each line that can show a
# display name or an organisation changed to <blanked by the kit>, as
# blank() of session-step.sh does: "Welcome back", "Organisation", each
# line that holds one of VALUES, and the end of a line after
# " . Claude Max . " (the dots are U+00B7). Not measured on a real screen.
function Clear-KitWelcomeBox([string]$Text, [string[]]$Values = @()) {
    $x = '<blanked by the kit>'
    $dot = [string][char]0x00B7
    $plan = " $dot Claude [A-Z][A-Za-z]*( [A-Za-z]+)? $dot "
    $lines = @($Text -split "`n")
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $l = $lines[$i]
        $hit = $l -match 'Welcome back|Organi[sz]ation'
        foreach ($v in $Values) { if ($v.Length -gt 2 -and $l.Contains($v)) { $hit = $true } }
        if ($hit) { $lines[$i] = $x; continue }
        $m = [regex]::Match($l, $plan)
        if ($m.Success) { $lines[$i] = $l.Substring(0, $m.Index + $m.Length) + $x }
    }
    return ($lines -join "`n")
}

# Test-KitScenario: true when the kit has the files of the conpty first
# run. A release kit can lack them.
function Test-KitScenario {
    foreach ($f in 'scenarios\first-run-windows.py', 'scenarios\conpty.py') {
        if (-not (Test-Path -LiteralPath (Join-Path $script:KitRoot $f) -PathType Leaf)) { return $false }
    }
    return $true
}

# Set-KitPrivate DIR: give only this account and SYSTEM access to DIR, as
# mode 0700 does on Unix. It returns the exit code of icacls.
function Set-KitPrivate([string]$Dir) {
    $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $wide = @($script:KitWideSids | ForEach-Object { "*$_" })
    $r = Invoke-KitNative 'icacls.exe' (@($Dir, '/inheritance:r', '/remove:g') + $wide + @('/grant:r', "*${me}:(OI)(CI)F", '*S-1-5-18:(OI)(CI)F'))
    return $r.Code
}
