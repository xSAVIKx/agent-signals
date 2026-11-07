# The probe kit for Windows.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File probes\run.ps1 [-All]
#   powershell -NoProfile -ExecutionPolicy Bypass -File probes\run.ps1 -Guided KIND [AGENT] [OPTION ...]
#
# The kit runs each probes\<agent>\windows.ps1 whose agent command it finds.
# With -All, it runs all probes. It sends the output through
# tools\scrub.ps1 and writes one file in the current folder:
# agent-signals-probe-windows-<yyyyMMdd-HHmmss>.txt.
#
# The probes only read. They start no agent, type nothing, and read no
# conversation text. The scrub removes names, but it cannot find all of
# them. Read the file before you send it.
#
# A guided step (-Guided) watches the agent folders while a person or a
# kit step does one action in an agent session. It is the twin of
# "sh probes/run.sh --guided KIND [AGENT] --wait N". It reads no key: the
# watch starts at once. The line "kit: watch starts, N s" tells a caller
# in the background that the first snapshot is done.
#   KIND           permission | new-chat | resume | interrupt
#   AGENT          claude | codex | agy | cursor-agent | opencode (default: all)
#   -Wait N        watch for N seconds (1 to 600). The default is
#                  AGENT_SIGNALS_WATCH, else 30.
#   -PidsFile F    count only the pids in F and the processes below them.
#                  F is a folder of files named by pid (the pids\ of a kit
#                  run), one such file, or a file with a pid at the start
#                  of each line (the pids file of a kit session). A pid
#                  with a start time ("LABEL<tab>START") counts only when
#                  its process has that start time.
#   -ExceptPids F  do not count the pids in F (the same forms) and the
#                  processes below them.
#   -ExceptCaller  do not count the processes above this one. Do not count
#                  an agent above this one (the agent that runs the kit)
#                  and the processes below that agent.
#   -StateHome DIR read the agent folders below DIR, not below the
#                  profile (for example the throwaway home of a session).
#   -Scope LIST    folders that the step can show, separated by "|". Each
#                  folder must exist.
#   -ScopeNew LIST as -Scope, for absolute paths of folders that can
#                  appear after the watch starts.
#   -StopFile FILE end the watch early: when FILE exists, the kit takes the
#                  last snapshot and writes the file.
#   -StartedAfter T  count only the processes that started after T (UTC
#                  ticks).
#   -RealSession   count only the processes of this user that have a
#                  console host or a terminal above them. Stop with exit 2
#                  when more than one session matches.
#   -Out FILE      write the file to FILE.
# The step never walks the home folder. It shows only the files below
# -Scope, the Claude pid file and the transcript of a counted process, and
# the files that a counted process holds open. It does not show the files
# of an excepted process. Paths have the project key, the other folder
# names and the file stem masked.
# The file of a guided step has the sections of the Unix guided file that
# Windows can measure: the processes before and after, 1. the files that
# changed in length or time, 2. the open state files (not measured with no
# Sysinternals handle.exe), 3. the record types of the JSONL lines after
# the length at the start, 4. the status of the Claude pid files every
# 2 s. It holds no conversation text, and it writes no copy of a file.
# The exit code of a guided step: 0 ok, 2 bad use or no session runs.

param(
  [switch]$All,
  [string]$Guided,
  [Parameter(Position = 0)][string]$Agent,
  [int]$Wait = 0,
  [string]$PidsFile,
  [string]$ExceptPids,
  [switch]$ExceptCaller,
  [string]$StateHome,
  [string]$Scope,
  [string]$ScopeNew,
  [string]$StopFile,
  [long]$StartedAfter = 0,
  [switch]$RealSession,
  [string]$Out
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'tools\scrub.ps1')

if ($Guided) {
  . (Join-Path $PSScriptRoot 'lib.ps1')
  $utf8 = New-Object System.Text.UTF8Encoding $false
  function Say([string]$Text) { [Console]::Out.WriteLine($Text); [Console]::Out.Flush() }
  function Stop-Guided([string]$Text) { Say "kit: $Text"; exit 2 }

  $actions = @{
    'permission' = 'In one agent session, ask for a file write, for example: Create a file named note.txt that holds the word hello. Wait until the permission dialog shows. Do not answer it yet.'
    'new-chat'   = 'In one session, start a new chat: /new-chat in Cursor, /clear in Claude, /new in Codex.'
    'resume'     = 'Exit one session. Then start it again with its resume command: cursor-agent --resume, claude --continue, codex resume --last, agy --continue.'
    'interrupt'  = 'In one session, send a prompt that takes some time, then push Esc while the agent works. Then push Ctrl+C one time.'
  }
  if (-not $actions.ContainsKey($Guided)) { Stop-Guided "unknown step: $Guided. Use one of: permission, new-chat, resume, interrupt" }
  if ($All) { Stop-Guided '-All and -Guided do not go together' }

  # The agents with a process pattern: the $script:Pattern line of
  # probes\<agent>\windows.ps1, so that the probe and the step agree.
  $patterns = [ordered]@{}
  foreach ($f in @(Get-ChildItem -Path (Join-Path $PSScriptRoot '*\windows.ps1') -File | Sort-Object FullName)) {
    $m = [regex]::Match([IO.File]::ReadAllText($f.FullName), "(?m)^\`$script:Pattern = '((?:[^']|'')*)'")
    if ($m.Success) { $patterns[(Split-Path -Leaf $f.DirectoryName)] = $m.Groups[1].Value.Replace("''", "'") }
  }
  $pick = $Agent
  if ($pick -in 'agent', 'cursor') { $pick = 'cursor-agent' }
  if ($pick -and -not $patterns.Contains($pick)) { Stop-Guided "unknown agent: $Agent. Use one of: $(@($patterns.Keys) -join ', ')" }
  $which = @(if ($pick) { $pick } else { $patterns.Keys })

  $watchS = 30
  if ($env:AGENT_SIGNALS_WATCH) {
    if ($env:AGENT_SIGNALS_WATCH -notmatch '^[1-9][0-9]*$') { Stop-Guided "AGENT_SIGNALS_WATCH takes a number from 1 to 600: $env:AGENT_SIGNALS_WATCH" }
    $watchS = [int]$env:AGENT_SIGNALS_WATCH
  }
  if ($PSBoundParameters.ContainsKey('Wait')) { $watchS = $Wait }
  if ($watchS -lt 1 -or $watchS -gt 600) { Stop-Guided "-Wait takes a number from 1 to 600: $watchS" }
  foreach ($x in @($PidsFile, $ExceptPids) | Where-Object { $_ }) {
    if (-not (Test-Path -LiteralPath $x)) { Stop-Guided "cannot read $x" }
  }
  if (-not $StateHome) { $StateHome = $env:USERPROFILE }
  if (-not (Test-Path -LiteralPath $StateHome -PathType Container)) { Stop-Guided "-StateHome: no folder $StateHome" }
  $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
  if (-not $Out) { $Out = Join-Path (Get-Location).ProviderPath ('agent-signals-probe-windows-' + (Get-Date).ToString('yyyyMMdd-HHmmss') + '.txt') }
  $outDir = Split-Path -Parent ([IO.Path]::GetFullPath($Out))
  if (-not (Test-Path -LiteralPath $outDir -PathType Container)) { Stop-Guided "-Out: no folder $outDir" }

  # The folders that hold the session state of each agent.
  function Get-StateDirs([string]$A) {
    $h = $StateHome
    switch ($A) {
      'claude' { @((Join-Path $h '.claude\sessions'), (Join-Path $h '.claude\projects')) }
      'codex' {
        $c = Join-Path $h '.codex'
        if ($env:CODEX_HOME -and $StateHome -eq $env:USERPROFILE) { $c = $env:CODEX_HOME }
        @((Join-Path $c 'sessions'), (Join-Path $c 'thread-writer-locks'))
      }
      'agy' { @((Join-Path $h '.gemini\antigravity-cli')) }
      'cursor-agent' { @((Join-Path $h '.cursor\chats'), (Join-Path $h '.cursor\projects')) }
      'opencode' { @((Join-Path $h '.local\share\opencode')) }
    }
  }

  # The start time of a process in UTC ticks, as Add-KitPid of
  # probes\agent\lib.ps1 writes it, or ''.
  function Get-StartTicks([int]$ProcessId) {
    try { return [string](Get-Process -Id $ProcessId -ErrorAction Stop).StartTime.ToUniversalTime().Ticks } catch { return '' }
  }
  # Test-Listed PID TICKS: true when PID runs, and has the start time TICKS
  # when TICKS is given.
  function Test-Listed([int]$ProcessId, [string]$Ticks) {
    $now = Get-StartTicks $ProcessId
    if (-not $now) { return $false }
    return (-not $Ticks -or $Ticks -eq $now)
  }
  # Get-ListedPids FILE|DIR: the pids of a -PidsFile or -ExceptPids value
  # that run now.
  function Get-ListedPids([string]$From) {
    if (Test-Path -LiteralPath $From -PathType Container) {
      foreach ($f in @(Get-ChildItem -LiteralPath $From -File -ErrorAction SilentlyContinue)) {
        if ($f.Name -notmatch '^\d+$') { continue }
        $t = ([IO.File]::ReadAllText($f.FullName) -split "`r?`n")[0] -split "`t"
        # A pids\ file must hold the start time.
        if ($t.Count -lt 2 -or -not $t[1].Trim()) { continue }
        if (Test-Listed ([int]$f.Name) $t[1].Trim()) { [int]$f.Name }
      }
      return
    }
    $text = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $From).ProviderPath)
    $leaf = Split-Path -Leaf $From
    $first = ($text -split "`r?`n")[0]
    if ($leaf -match '^\d+$' -and $first -match "`t") {
      $t = $first -split "`t"
      if ($t[1].Trim() -and (Test-Listed ([int]$leaf) $t[1].Trim())) { [int]$leaf }
      return
    }
    foreach ($l in ($text -split "`r?`n")) {
      $m = [regex]::Match($l, '^\s*(\d+)(?:\s.*)?$')
      if (-not $m.Success) { continue }
      $ticks = ''
      $t = $l.Trim() -split "`t"
      if ($t.Count -gt 1 -and $t[-1].Trim() -match '^\d+$') { $ticks = $t[-1].Trim() }
      if (Test-Listed ([int]$m.Groups[1].Value) $ticks) { [int]$m.Groups[1].Value }
    }
  }

  # Get-Table: a new table of all processes, by pid.
  function Get-Table {
    $t = @{}
    foreach ($p in @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)) { $t[[int]$p.ProcessId] = $p }
    return $t
  }
  # Get-Below TABLE PIDS: the pids and the processes below them. A child
  # must start after its parent, because Windows reuses pids and keeps the
  # parent pid of a process after the parent ends.
  function Get-Below($Table, [int[]]$Roots) {
    $kids = @{}
    foreach ($p in $Table.Values) {
      $pp = [int]$p.ParentProcessId
      if (-not $kids.ContainsKey($pp)) { $kids[$pp] = New-Object System.Collections.ArrayList }
      [void]$kids[$pp].Add($p)
    }
    $seen = @{}
    $queue = New-Object System.Collections.Queue
    foreach ($r in $Roots) { if ($Table.ContainsKey($r) -and -not $seen.ContainsKey($r)) { $seen[$r] = $true; $queue.Enqueue($r) } }
    while ($queue.Count -gt 0) {
      $cur = $queue.Dequeue()
      if (-not $kids.ContainsKey($cur)) { continue }
      $made = $Table[$cur].CreationDate
      foreach ($c in $kids[$cur]) {
        $id = [int]$c.ProcessId
        if ($seen.ContainsKey($id) -or $id -eq $cur) { continue }
        if ($made -and $c.CreationDate -and $c.CreationDate -lt $made) { continue }
        $seen[$id] = $true
        $queue.Enqueue($id)
      }
    }
    return $seen
  }

  # Test-GuidedAgent PROCESS PATTERN: the rule of Test-AgentProcess in
  # probes\lib.ps1, and one more: a PowerShell that runs a script file
  # (-File X.ps1) whose name matches. On Unix, "sh /path/claude" counts
  # in the same way. A shell that runs command text does not count.
  function Test-GuidedAgent($P, [string]$Pattern) {
    if (Test-AgentProcess $P $Pattern) { return $true }
    $base = [IO.Path]::GetFileNameWithoutExtension([string]$P.Name).ToLowerInvariant()
    if (@('powershell', 'pwsh') -notcontains $base -or -not $P.CommandLine) { return $false }
    $argv = Split-CommandLine ([string]$P.CommandLine)
    for ($i = 1; $i -lt $argv.Count - 1; $i++) {
      if ($argv[$i] -match '^(?i)-f(ile)?$') {
        return ([IO.Path]::GetFileNameWithoutExtension([string]$argv[$i + 1]) -match $Pattern)
      }
    }
    return $false
  }

  # The caller: the processes above this one. An agent among them runs the
  # kit (the orchestrator): it and the processes below it do not count.
  function Get-CallerSet($Table) {
    $up = @()
    $id = $PID
    $child = $null
    for ($n = 0; $n -lt 40; $n++) {
      $p = $Table[$id]
      if (-not $p) { break }
      if ($child -and $p.CreationDate -and $child.CreationDate -and $p.CreationDate -gt $child.CreationDate) { break }
      $up += $p
      $child = $p
      $id = [int]$p.ParentProcessId
      if ($id -le 0) { break }
    }
    $set = @{}
    foreach ($p in $up) { $set[[int]$p.ProcessId] = $true }
    $orch = @()
    foreach ($p in $up) {
      foreach ($pat in $patterns.Values) { if (Test-GuidedAgent $p $pat) { $orch += [int]$p.ProcessId; break } }
    }
    if ($orch.Count -gt 0) { foreach ($k in (Get-Below $Table $orch).Keys) { $set[$k] = $true } }
    return $set
  }

  # Test-AnyAgent PROCESS: true when PROCESS matches an agent pattern.
  function Test-AnyAgent($P) {
    foreach ($pat in $patterns.Values) { if (Test-GuidedAgent $P $pat) { return $true } }
    return $false
  }

  # Test-OwnProcess PROCESS: true when this user owns PROCESS.
  $script:MySid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  function Test-OwnProcess($P) {
    try {
      $r = Invoke-CimMethod -InputObject $P -MethodName GetOwnerSid -ErrorAction Stop
      return ([string]$r.Sid -eq $script:MySid)
    } catch { return $false }
  }

  # Test-HasTerminal PROCESS: true when PROCESS or a process above it has a
  # console host as a child, or is a terminal program. A service or a
  # background agent has neither.
  function Test-HasTerminal($P) {
    $hosts = @{}
    foreach ($q in $script:Table.Values) {
      $b = [IO.Path]::GetFileNameWithoutExtension([string]$q.Name)
      if ($b -ieq 'conhost' -or $b -ieq 'OpenConsole') { $hosts[[int]$q.ParentProcessId] = $true }
    }
    $known = 'WindowsTerminal', 'Code', 'pycharm64', 'idea64', 'wezterm-gui', 'alacritty', 'mintty', 'ConEmu64'
    $q = $P
    for ($n = 0; $n -lt 40 -and $q; $n++) {
      if ($hosts.ContainsKey([int]$q.ProcessId)) { return $true }
      $b = [IO.Path]::GetFileNameWithoutExtension([string]$q.Name)
      foreach ($k in $known) { if ($b -ieq $k) { return $true } }
      $next = $script:Table[[int]$q.ParentProcessId]
      if ($next -and $next.CreationDate -and $q.CreationDate -and $next.CreationDate -gt $q.CreationDate) { break }
      $q = $next
    }
    return $false
  }

  # Get-Tops LIST: the processes of LIST with no process of LIST above
  # them. One session can have a launcher and a program that both match.
  function Get-Tops($List) {
    $ids = @{}
    foreach ($p in $List) { $ids[[int]$p.ProcessId] = $true }
    foreach ($p in $List) {
      $top = $true
      $q = $p
      for ($n = 0; $n -lt 40 -and $q; $n++) {
        $pp = [int]$q.ParentProcessId
        if ($ids.ContainsKey($pp)) { $top = $false; break }
        $q = $script:Table[$pp]
      }
      if ($top) { $p }
    }
  }

  # Get-Counted: for each agent, the process objects that the step counts.
  # It also sets $script:Excepted: the agent processes that the step must
  # not show.
  $script:Table = $null
  $script:Excepted = @()
  function Get-Counted {
    $script:Table = Get-Table
    $in = $null
    if ($PidsFile) { $in = Get-Below $script:Table @(Get-ListedPids $PidsFile) }
    $outSet = @{}
    if ($ExceptPids) { $outSet = Get-Below $script:Table @(Get-ListedPids $ExceptPids) }
    if ($ExceptCaller) { foreach ($k in (Get-CallerSet $script:Table).Keys) { $outSet[$k] = $true } }
    $script:Excepted = @($script:Table.Values | Where-Object { $outSet.ContainsKey([int]$_.ProcessId) -and (Test-AnyAgent $_) })
    $self = '(?i)probes[\\/]([^\\/]+[\\/]windows|run)\.ps1'
    $r = [ordered]@{}
    foreach ($a in $which) {
      $list = @($script:Table.Values | Where-Object {
          $id = [int]$_.ProcessId
          $id -ne $PID -and -not $outSet.ContainsKey($id) -and ($null -eq $in -or $in.ContainsKey($id)) -and
          -not ($_.CommandLine -and $_.CommandLine -match $self) -and (Test-GuidedAgent $_ $patterns[$a])
        } | Sort-Object ProcessId)
      if ($StartedAfter -gt 0) {
        $list = @($list | Where-Object { $_.CreationDate -and $_.CreationDate.ToUniversalTime().Ticks -gt $StartedAfter })
      }
      if ($RealSession) { $list = @($list | Where-Object { (Test-OwnProcess $_) -and (Test-HasTerminal $_) }) }
      $r[$a] = $list
    }
    return $r
  }
  function Get-AllCounted($Set) { foreach ($a in $which) { $Set[$a] } }

  # The folders of -Scope and -ScopeNew: lists separated by "|". A folder of
  # -ScopeNew can appear after the first prompt, so it can be missing now.
  $scopes = @(([string]$Scope -split '\|') | Where-Object { $_ })
  foreach ($s in $scopes) {
    if (-not (Test-Path -LiteralPath $s -PathType Container)) { Stop-Guided "-Scope: no folder $s" }
  }
  foreach ($s in @(([string]$ScopeNew -split '\|') | Where-Object { $_ })) {
    if (-not [IO.Path]::IsPathRooted($s)) { Stop-Guided "-ScopeNew needs an absolute path: $s" }
    $scopes += $s
  }
  $script:HandleTool = $null
  foreach ($t in 'handle64.exe', 'handle.exe') {
    $c = Get-Command $t -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { $script:HandleTool = $c.Source; break }
  }

  # Get-OpenOf PROCESSES: the state files that the processes hold open. It
  # needs Sysinternals handle.exe.
  function Get-OpenOf($Procs) {
    if (-not $script:HandleTool) { return }
    foreach ($p in $Procs) {
      $r = Invoke-Captured $script:HandleTool "-nobanner -p $($p.ProcessId)" 8000
      if ($r.TimedOut) { continue }
      foreach ($l in ((Remove-Ansi $r.Out) -split "`r?`n")) {
        $m = [regex]::Match($l, '\bFile\b.*?([A-Za-z]:\\.+?)\s*$')
        if ($m.Success -and $m.Groups[1].Value -match '(?i)\\\.?(claude|codex|gemini|cursor|opencode|copilot)\\') { $m.Groups[1].Value }
      }
    }
  }

  # Get-SessionFiles PROCESSES: the Claude pid file of each process and the
  # transcript that the pid file names. The name of a project folder does
  # not show, and the kit reads no other project.
  function Get-SessionFiles($Procs) {
    foreach ($p in $Procs) {
      $f = Join-Path $StateHome ".claude\sessions\$($p.ProcessId).json"
      if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { continue }
      $f
      $sid = ''
      try { $sid = [regex]::Match((Read-Shared $f), '"sessionId"\s*:\s*"([0-9A-Za-z-]{8,64})"').Groups[1].Value } catch { }
      if (-not $sid) { continue }
      $pd = Join-Path $StateHome '.claude\projects'
      foreach ($d in @(Get-ChildItem -LiteralPath $pd -Directory -Force -ErrorAction SilentlyContinue)) {
        $t = Join-Path $d.FullName "$sid.jsonl"
        if (Test-Path -LiteralPath $t -PathType Leaf) { $t }
      }
    }
  }

  # Read-Shared FILE: the text of a file that an agent can write or delete
  # now.
  function Read-Shared([string]$File) {
    $fs = New-Object System.IO.FileStream($File, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try { return (New-Object System.IO.StreamReader($fs, $utf8)).ReadToEnd() } finally { $fs.Dispose() }
  }

  # Get-InScope PROCESSES OPEN: the files that the step can show: the files
  # below the -Scope folders, the session files of PROCESSES, and the files
  # OPEN. The files of an excepted process do not show. The step reads no
  # other file of the home folder.
  function Get-InScope($Procs, $Open) {
    $set = @{}
    foreach ($d in $scopes) {
      if (-not (Test-Path -LiteralPath $d -PathType Container)) { continue }
      foreach ($f in @(Get-ChildItem -LiteralPath $d -Recurse -File -Force -ErrorAction SilentlyContinue)) { $set[$f.FullName] = $true }
    }
    foreach ($f in @(Get-SessionFiles $Procs)) { $set[$f] = $true }
    foreach ($f in @($Open)) { if ($f) { $set[$f] = $true } }
    if ($script:Excepted.Count -gt 0) {
      foreach ($f in @(Get-SessionFiles $script:Excepted) + @(Get-OpenOf $script:Excepted)) { if ($f) { $set.Remove($f) } }
    }
    return $set
  }

  # The roots that Format-Masked knows: each state folder below the home.
  $maskRoots = New-Object System.Collections.ArrayList
  $homeBase = $StateHome.TrimEnd('\', '/')
  foreach ($a in $which) {
    foreach ($d in @(Get-StateDirs $a)) {
      $label = '<state>'
      if ($d.StartsWith($homeBase + '\', [StringComparison]::OrdinalIgnoreCase)) { $label = '~' + $d.Substring($homeBase.Length) }
      [void]$maskRoots.Add(@($d, $label))
    }
  }
  # Format-Masked FILE: FILE with the project key, the other folder names
  # and the file stem masked. Folders of digits (a date) stay.
  function Format-Masked([string]$File) {
    $label = ''
    $rest = ''
    foreach ($r in $maskRoots) {
      if ($File.StartsWith($r[0] + '\', [StringComparison]::OrdinalIgnoreCase)) { $label = $r[1]; $rest = $File.Substring($r[0].Length + 1); break }
    }
    if (-not $label) {
      foreach ($s in $scopes) {
        $b = $s.TrimEnd('\', '/')
        if ($File.StartsWith($b + '\', [StringComparison]::OrdinalIgnoreCase)) { $label = '<scope>'; $rest = $File.Substring($b.Length + 1); break }
      }
    }
    if (-not $label) { $label = '<other>'; $rest = Split-Path -Leaf $File }
    $parts = @($rest -split '[\\/]+')
    $o = $label
    for ($i = 0; $i -lt $parts.Count - 1; $i++) {
      if ($parts[$i] -match '^\d+$') { $o += '\' + $parts[$i] } elseif ($i -eq 0) { $o += '\<key>' } else { $o += '\<dir>' }
    }
    $ext = [IO.Path]::GetExtension($parts[-1])
    if ($ext -notmatch '^\.[A-Za-z0-9]{1,8}$') { $ext = '' }
    return "$o\<file>$ext"
  }

  # Read-NewLines FILE OFFSET: the whole lines of FILE after the byte
  # OFFSET, at most 8 MiB, in memory. The file stays open for the agent.
  function Read-NewLines([string]$File, [long]$Offset) {
    $fs = New-Object System.IO.FileStream($File, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try {
      $len = $fs.Length
      if ($len -lt $Offset) { return [pscustomobject]@{ Length = $len; Short = $true; Lines = @() } }
      [void]$fs.Seek($Offset, [IO.SeekOrigin]::Begin)
      $n = [int][math]::Min($len - $Offset, 8MB)
      $buf = New-Object byte[] $n
      $got = 0
      while ($got -lt $n) {
        $k = $fs.Read($buf, $got, $n - $got)
        if ($k -le 0) { break }
        $got += $k
      }
    } finally { $fs.Dispose() }
    # The text after the last line end is not a whole record yet.
    $parts = @($utf8.GetString($buf, 0, $got) -split "`n")
    $lines = @()
    if ($parts.Count -gt 1) { $lines = @($parts[0..($parts.Count - 2)]) }
    return [pscustomobject]@{ Length = $len; Short = $false; Lines = $lines }
  }

  # Get-ClaudeStatus PROCESSES: "PID STATUS" of the Claude pid file of each
  # process (fact 23).
  function Get-ClaudeStatus($Procs) {
    $parts = @()
    foreach ($p in $Procs) {
      $f = Join-Path $StateHome ".claude\sessions\$($p.ProcessId).json"
      if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { continue }
      $s = 'none'
      try {
        $m = [regex]::Match((Read-Shared $f), '"status"\s*:\s*"([a-z]*)"')
        if ($m.Success) { $s = $m.Groups[1].Value }
      } catch { $s = 'unreadable' }
      $parts += "$($p.ProcessId) $s"
    }
    return ($parts -join ' ')
  }

  $counted = Get-Counted
  $running = @()
  foreach ($a in $which) {
    $n = @(Get-Tops $counted[$a]).Count
    if ($RealSession -and $n -gt 1) { Stop-Guided "more than one session of $a runs: $n" }
    if ($counted[$a].Count -gt 0) { $running += "$a=$($counted[$a].Count)" }
  }
  if ($running.Count -eq 0) { Stop-Guided "no session of $($which -join ' ') runs. Start a session, then run the step again." }

  $sb = New-Object System.Text.StringBuilder
  function Add-Line([string]$Text) { [void]$sb.Append($Text + "`n") }
  Add-Line "agent-signals guided step: $Guided, $stamp"
  Add-Line "agents: $($which -join ' ')"
  Add-Line "watch: $watchS s"
  Add-Line "processes: $($running -join ' ')"
  foreach ($a in $which) { foreach ($p in $counted[$a]) { Add-Line "$a $(Format-ProcessLine $p)" } }

  # The baseline: the length and the time of each file in the scope.
  $firstProcs = @(Get-AllCounted $counted)
  $openBefore = @(Get-OpenOf $firstProcs)
  $mark = (Get-Date).ToUniversalTime()
  $base = @{}
  foreach ($f in @((Get-InScope $firstProcs $openBefore).Keys)) {
    try {
      $fi = New-Object IO.FileInfo $f
      if ($fi.Exists) { $base[$f] = @($fi.Length, $fi.LastWriteTimeUtc) }
    } catch { }
  }
  $status = New-Object System.Collections.ArrayList
  [void]$status.Add((Get-ClaudeStatus $firstProcs))
  Add-Line ''
  Add-Line "kit: do this now. The kit watches the agent folders for $watchS s:"
  Add-Line "  $($actions[$Guided])"
  Add-Line "kit: watch starts, $watchS s"
  Say "kit: do this now. The kit watches the agent folders for $watchS s:"
  Say "  $($actions[$Guided])"
  Say "kit: watch starts, $watchS s"

  # A sample every 2 s. A -StopFile ends the watch early.
  $t0 = Get-Date
  $endAt = $t0.AddSeconds($watchS)
  $next = 2
  while ((Get-Date) -lt $endAt) {
    if ($StopFile -and (Test-Path -LiteralPath $StopFile)) { break }
    Start-Sleep -Milliseconds 200
    if (((Get-Date) - $t0).TotalSeconds -ge $next) {
      [void]$status.Add((Get-ClaudeStatus $firstProcs))
      $next += 2
    }
  }

  $counted = Get-Counted
  Add-Line 'processes after the step:'
  foreach ($a in $which) { foreach ($p in $counted[$a]) { Add-Line "$a $(Format-ProcessLine $p)" } }
  $lastProcs = @(Get-AllCounted $counted)
  $openAfter = @(Get-OpenOf $lastProcs)

  # The files of the scope now, for the processes of the start and of the
  # end. A process can end in the watch.
  $byId = @{}
  foreach ($p in $firstProcs + $lastProcs) { $byId[[int]$p.ProcessId] = $p }
  $now = Get-InScope @($byId.Values) $openAfter
  $who = $which[0]
  Add-Line ''
  Add-Line '### 1. Files that changed during the step (size, path)'
  if (-not $script:HandleTool) { Add-Line 'not measured: the files that the processes hold open (no Sysinternals handle.exe)' }
  $changed = New-Object System.Collections.ArrayList
  foreach ($f in @(@($now.Keys) + @($base.Keys) | Sort-Object -Unique)) {
    $mask = Format-Masked $f
    try {
      $fi = New-Object IO.FileInfo $f
      $fi.Refresh()
      if (-not $fi.Exists) {
        if ($base.ContainsKey($f)) { Add-Line "$who deleted $mask" }
        continue
      }
      $offset = -1L
      if ($base.ContainsKey($f)) {
        if ($fi.Length -eq $base[$f][0] -and $fi.LastWriteTimeUtc -eq $base[$f][1]) { continue }
        $offset = [long]$base[$f][0]
      } elseif ($fi.CreationTimeUtc -ge $mark) {
        $offset = 0L
      } elseif ($fi.LastWriteTimeUtc -lt $mark) {
        continue
      }
      Add-Line "$who $($fi.Length) $mask"
      [void]$changed.Add(@($f, $mask, $offset))
    } catch { Add-Line "$who unreadable $mask" }
  }
  Add-Line ''
  Add-Line '### 2. Open state files: before (<) and after (>)'
  if ($script:HandleTool) {
    foreach ($f in @($openBefore | Where-Object { $openAfter -notcontains $_ } | Sort-Object -Unique)) { Add-Line "< $(Format-Masked $f)" }
    foreach ($f in @($openAfter | Where-Object { $openBefore -notcontains $_ } | Sort-Object -Unique)) { Add-Line "> $(Format-Masked $f)" }
  } else {
    Add-Line 'not measured on Windows: the open files need Sysinternals handle.exe'
  }
  Add-Line ''
  Add-Line '### 3. New records in JSONL files (types only)'
  foreach ($c in $changed) {
    $f = $c[0]; $mask = $c[1]; $o = [long]$c[2]
    if ($f -notmatch '(?i)\.jsonl$') { continue }
    if ($o -lt 0) { Add-Line "== $mask (no length at the start of the watch)"; continue }
    try {
      $r = Read-NewLines $f $o
      if ($r.Short) { Add-Line "== $mask (bytes $o -> $($r.Length), shorter)"; continue }
      Add-Line "== $mask (bytes $o -> $($r.Length), $($r.Lines.Count) new lines)"
      foreach ($l in @($r.Lines | Select-Object -First 40)) { Add-Line "  $(Format-JsonlLine $l)" }
    } catch { Add-Line "== $mask unreadable" }
  }
  if ($which -contains 'claude') {
    Add-Line ''
    Add-Line '### 4. Status of the Claude pid files, every 2 s (fact 23)'
    Add-Line 'only the pid files of the counted pids'
    for ($j = 0; $j -lt $status.Count; $j++) { Add-Line ("t={0}s: {1}" -f ($j * 2), $status[$j]) }
  }

  $d = Get-ScrubDefaults
  $r = Invoke-Scrub $sb.ToString() $d.HomeDir $d.User $d.HostName $d.Extra $d.Domain
  $text = $r.Text + "`n### scrub`n"
  foreach ($k in $script:ScrubKinds) {
    $line = 'scrub: {0} {1}' -f $r.Counts[$k], $k
    $text += $line + "`n"
    [Console]::Error.WriteLine($line)
  }
  [IO.File]::WriteAllText([IO.Path]::GetFullPath($Out), $text, $utf8)
  Say "kit: wrote $Out"
  Say 'kit: read the file before you send it.'
  exit 0
}

# The commands that show that an agent is installed.
$commands = @{
  'claude'   = @('claude')
  'codex'    = @('codex')
  'agy'      = @('agy')
  'cursor-agent' = @('agent', 'cursor-agent')
  'opencode' = @('opencode')
}

$exe = (Get-Process -Id $PID).Path
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('# agent-signals probe kit for Windows')
[void]$sb.AppendLine('kit date: ' + (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))

$probes = @(Get-ChildItem -Path (Join-Path $PSScriptRoot '*\windows.ps1') -File | Sort-Object FullName)
foreach ($probe in $probes) {
  $agent = Split-Path -Leaf (Split-Path -Parent $probe.FullName)
  $run = $All
  if (-not $run) {
    if ($commands.ContainsKey($agent)) {
      foreach ($c in $commands[$agent]) {
        if (Get-Command $c -ErrorAction SilentlyContinue) { $run = $true }
      }
    } else {
      $run = $true
    }
  }
  if (-not $run) {
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("==== probe $agent/windows.ps1: skipped, not installed: $($commands[$agent] -join ', ')")
    Write-Host "skip: $agent (not installed)"
    continue
  }
  Write-Host "run: $agent"
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine("==== probe $agent/windows.ps1")
  $info = New-Object System.Diagnostics.ProcessStartInfo
  $info.FileName = $exe
  $info.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $probe.FullName + '"'
  $info.UseShellExecute = $false
  $info.RedirectStandardOutput = $true
  $info.RedirectStandardError = $true
  $info.StandardOutputEncoding = New-Object System.Text.UTF8Encoding $false
  $info.StandardErrorEncoding = New-Object System.Text.UTF8Encoding $false
  $info.CreateNoWindow = $true
  $p = [System.Diagnostics.Process]::Start($info)
  $outTask = $p.StandardOutput.ReadToEndAsync()
  $err = $p.StandardError.ReadToEndAsync()
  if (-not $p.WaitForExit(600000)) {
    try { $p.Kill() } catch { }
    [void]$sb.AppendLine('kit: the probe did not stop in 600 s')
  }
  [void]$outTask.Wait(5000)
  [void]$err.Wait(5000)
  [void]$sb.Append($outTask.Result)
  if ($err.Result) {
    [void]$sb.AppendLine('---- stderr')
    [void]$sb.Append($err.Result)
  }
  if ($p.HasExited) { [void]$sb.AppendLine("==== exit status: $($p.ExitCode)") }
}

$d = Get-ScrubDefaults
$r = Invoke-Scrub $sb.ToString() $d.HomeDir $d.User $d.HostName
$text = $r.Text + "`n### scrub`n"
foreach ($k in $script:ScrubKinds) {
  $line = 'scrub: {0} {1}' -f $r.Counts[$k], $k
  $text += $line + "`n"
  [Console]::Error.WriteLine($line)
}

$name = 'agent-signals-probe-windows-' + (Get-Date).ToString('yyyyMMdd-HHmmss') + '.txt'
$file = Join-Path (Get-Location).ProviderPath $name
[IO.File]::WriteAllText($file, $text, (New-Object System.Text.UTF8Encoding $false))
Write-Output $file
Write-Output 'Read the file before you send it.'
exit 0
