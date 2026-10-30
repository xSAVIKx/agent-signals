# Shared functions for the Windows probes. Each probe dot-sources this file.
# Needs PowerShell 5.1 or later and no extra modules.
#
# A probe only reads. The functions in this file start no agent, type
# nothing, change no file, and read no conversation text. They print record
# types, field names and folder layouts, not values.
#
# All output goes through Write-Line, so that the order of the lines stays
# correct also when a function prints a line and returns a value.

$ErrorActionPreference = 'Stop'
$script:SectionNumber = 0
$script:SectionLines = 0
$script:ProcTable = $null

try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }

# Words that a process line keeps. They are subcommands of the agents, not
# names or prompt text.
$script:SafeWords = @(
  'app-server', 'exec', 'resume', 'continue', 'mcp', 'mcp-server', 'serve',
  'server', 'status', 'login', 'run', 'acp', 'proto', 'daemon', 'attach',
  'chat', 'agent', 'tui', 'web', 'ls', 'list-panes', 'new-session'
)

function Write-Line([string]$Text) {
  $script:SectionLines++
  [Console]::Out.WriteLine($Text)
}

function Section([string]$Title) {
  $script:SectionNumber++
  $script:SectionLines = 0
  [Console]::Out.WriteLine('')
  [Console]::Out.WriteLine(('### {0}. {1}' -f $script:SectionNumber, $Title))
}

function None { Write-Line 'not found' }

function Need([string]$Tool) {
  if (Get-Command $Tool -ErrorAction SilentlyContinue) { return $true }
  Write-Line "not installed: $Tool"
  return $false
}

# Runs one section. A failure stops this section only. A section with no
# output prints "not found".
function Invoke-Section([string]$Title, [scriptblock]$Body) {
  Section $Title
  try {
    & $Body | ForEach-Object { if ($null -ne $_) { Write-Line ([string]$_) } }
  } catch {
    Write-Line ('error: ' + $_.Exception.GetType().Name)
  }
  if ($script:SectionLines -eq 0) { None }
}

function ConvertTo-UnixTime([datetime]$Utc) {
  $epoch = New-Object DateTime 1970, 1, 1, 0, 0, 0, ([DateTimeKind]::Utc)
  return [int64][math]::Floor(($Utc.ToUniversalTime() - $epoch).TotalSeconds)
}

function Format-Utc($Date) {
  if ($null -eq $Date) { return 'unknown' }
  return ([datetime]$Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
}

# Starts a program, waits at most TimeoutMs, and returns its output.
# It writes no file. A .cmd shim runs through cmd.exe, and a .ps1 shim
# runs through a new PowerShell process.
function Invoke-Captured([string]$Exe, [string]$Arguments, [int]$TimeoutMs = 15000) {
  $info = New-Object System.Diagnostics.ProcessStartInfo
  $ext = [IO.Path]::GetExtension($Exe).ToLowerInvariant()
  if ($ext -eq '.cmd' -or $ext -eq '.bat') {
    $comspec = $env:ComSpec
    if (-not $comspec) { $comspec = 'cmd.exe' }
    $info.FileName = $comspec
    $info.Arguments = '/d /c ""' + $Exe + '" ' + $Arguments + '"'
  } elseif ($ext -eq '.ps1') {
    $info.FileName = (Get-Process -Id $PID).Path
    $info.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $Exe + '" ' + $Arguments
  } else {
    $info.FileName = $Exe
    $info.Arguments = $Arguments
  }
  $info.UseShellExecute = $false
  $info.RedirectStandardOutput = $true
  $info.RedirectStandardError = $true
  $info.RedirectStandardInput = $true
  $info.CreateNoWindow = $true
  $p = [System.Diagnostics.Process]::Start($info)
  $p.StandardInput.Close()
  $out = $p.StandardOutput.ReadToEndAsync()
  $err = $p.StandardError.ReadToEndAsync()
  $timedOut = $false
  if (-not $p.WaitForExit($TimeoutMs)) {
    $timedOut = $true
    if (Get-Command taskkill.exe -ErrorAction SilentlyContinue) {
      & taskkill.exe /PID $p.Id /T /F 2>&1 | Out-Null
    } else {
      try { $p.Kill() } catch { }
    }
    [void]$p.WaitForExit(2000)
  }
  $o = ''
  $e = ''
  if ($out.Wait(2000)) { $o = $out.Result }
  if ($err.Wait(2000)) { $e = $err.Result }
  $code = $null
  if (-not $timedOut) { $code = $p.ExitCode }
  return New-Object PSObject -Property @{ Out = $o; Err = $e; Code = $code; TimedOut = $timedOut }
}

function Remove-Ansi([string]$Text) {
  if ($null -eq $Text) { return '' }
  return [regex]::Replace($Text, "\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07]*\x07", '')
}

function Get-FirstLine([string]$Text) {
  foreach ($l in ((Remove-Ansi $Text) -split "`r?`n")) {
    if ($l.Trim()) { return $l.Trim() }
  }
  return ''
}

# Returns the program file of a command: an .exe or a .cmd shim first, a
# .ps1 shim only when there is no other file.
function Get-CommandFile([string]$Name) {
  $app = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($app) { return $app.Source }
  $any = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($any -and $any.Source) { return $any.Source }
  return $null
}

function Get-ResolvedPath([string]$Path) {
  $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  if (-not $item) { return $Path }
  if ($item.LinkType -and $item.Target) { return (@($item.Target)[0]) }
  return $item.FullName
}

function Header([string]$Name, [string]$Version, [string[]]$Commands) {
  Invoke-Section 'Probe' {
    "probe: $Name"
    "probe version: $Version"
    try {
      $os = Get-CimInstance Win32_OperatingSystem
      "os: $($os.Caption) $($os.Version) build $($os.BuildNumber)"
    } catch {
      'os: error: ' + $_.Exception.GetType().Name
    }
    if ($env:PROCESSOR_ARCHITECTURE) { "cpu: $env:PROCESSOR_ARCHITECTURE" } else { 'cpu: not found' }
    "powershell: $($PSVersionTable.PSVersion) $($PSVersionTable.PSEdition)"
    'date: ' + (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    foreach ($c in $Commands) {
      $file = Get-CommandFile $c
      if (-not $file) { "command ${c}: not installed"; continue }
      "command ${c}: $file"
      "resolved ${c}: $(Get-ResolvedPath $file)"
      try {
        $r = Invoke-Captured $file '--version' 15000
        if ($r.TimedOut) { "version ${c}: no answer in 15 s" }
        else {
          $v = Get-FirstLine $r.Out
          if (-not $v) { $v = Get-FirstLine $r.Err }
          if (-not $v) { $v = 'empty output' }
          "version ${c}: $v"
        }
      } catch {
        "version ${c}: error: " + $_.Exception.GetType().Name
      }
    }
  }
}

function Get-ProcessTable {
  if ($null -eq $script:ProcTable) {
    $script:ProcTable = @{}
    foreach ($p in Get-CimInstance Win32_Process) {
      $script:ProcTable[[int]$p.ProcessId] = $p
    }
  }
  return $script:ProcTable
}

# Returns Win32_Process objects whose Name or CommandLine matches Pattern.
# It does not return the probe itself or the kit.
function Get-AgentProcesses([string]$Pattern) {
  $table = Get-ProcessTable
  $self = '(?i)probes[\\/]([^\\/]+[\\/]windows|run)\.ps1'
  $table.Values | Where-Object {
    $_.ProcessId -ne $PID -and
    ($_.Name -match $Pattern -or ($_.CommandLine -and $_.CommandLine -match $Pattern)) -and
    -not ($_.CommandLine -and $_.CommandLine -match $self)
  } | Sort-Object ProcessId
}

# Splits a Windows command line into arguments. Quotes group words.
function Split-CommandLine([string]$Line) {
  $list = New-Object System.Collections.ArrayList
  if (-not $Line) { return ,$list }
  $sb = New-Object System.Text.StringBuilder
  $quoted = $false
  $has = $false
  foreach ($ch in $Line.ToCharArray()) {
    if ($ch -eq '"') { $quoted = -not $quoted; $has = $true; continue }
    if (-not $quoted -and [char]::IsWhiteSpace($ch)) {
      if ($has) { [void]$list.Add($sb.ToString()); [void]$sb.Clear(); $has = $false }
      continue
    }
    [void]$sb.Append($ch)
    $has = $true
  }
  if ($has) { [void]$list.Add($sb.ToString()) }
  return ,$list
}

# Hides an argument that can be a name or prompt text.
function Hide-Arg([string]$Arg) {
  if ($Arg -match '^[-/]') {
    $i = $Arg.IndexOf('=')
    if ($i -gt 0) { return $Arg.Substring(0, $i + 1) + (Hide-Value $Arg.Substring($i + 1)) }
    return $Arg
  }
  return (Hide-Value $Arg)
}

function Hide-Value([string]$Value) {
  if ($Value -match '[\\/]') { return $Value }
  if ($script:SafeWords -contains $Value) { return $Value }
  return '<arg>'
}

function Format-ProcessLine($P) {
  $start = Format-Utc $P.CreationDate
  $head = 'pid={0} ppid={1} start={2} name={3}' -f $P.ProcessId, $P.ParentProcessId, $start, $P.Name
  if (-not $P.CommandLine) { return "$head cmd: not available" }
  $argv = Split-CommandLine $P.CommandLine
  $parts = @()
  for ($i = 0; $i -lt $argv.Count; $i++) {
    if ($i -eq 0) { $a = $argv[$i] } else { $a = Hide-Arg $argv[$i] }
    if ($a -match '\s') { $a = '"' + $a + '"' }
    $parts += $a
  }
  return "$head cmd: " + ($parts -join ' ')
}

# Returns the parent chain as objects. It stops at a process that does not
# exist, and at a parent that started after its child (a reused pid).
function Get-ParentObjects([int]$ProcessId) {
  $table = Get-ProcessTable
  $seen = @{}
  $id = $ProcessId
  $child = $null
  $list = @()
  for ($n = 0; $n -lt 40; $n++) {
    if ($seen.ContainsKey($id)) { break }
    $seen[$id] = $true
    $p = $table[$id]
    if (-not $p) { break }
    if ($child -and $p.CreationDate -and $child.CreationDate -and $p.CreationDate -gt $child.CreationDate) { break }
    $list += $p
    $child = $p
    $id = [int]$p.ParentProcessId
  }
  return $list
}

function Get-ParentChain([int]$ProcessId) {
  foreach ($p in (Get-ParentObjects $ProcessId)) {
    'pid={0} ppid={1} name={2}' -f $p.ProcessId, $p.ParentProcessId, $p.Name
  }
}

function Get-TerminalHints($P) {
  $known = 'WindowsTerminal', 'conhost', 'OpenConsole', 'Code', 'pycharm64', 'idea64',
           'wezterm-gui', 'alacritty', 'psmux', 'tmux'
  $found = @()
  foreach ($q in (Get-ParentObjects ([int]$P.ProcessId))) {
    $base = [IO.Path]::GetFileNameWithoutExtension([string]$q.Name)
    foreach ($k in $known) {
      if ($base -ieq $k -and $found -notcontains $k) { $found += $k }
    }
  }
  # conhost and OpenConsole are often not parents but children of the shell.
  $table = Get-ProcessTable
  foreach ($q in $table.Values) {
    if ([int]$q.ParentProcessId -eq [int]$P.ProcessId) {
      $base = [IO.Path]::GetFileNameWithoutExtension([string]$q.Name)
      if (($base -ieq 'conhost' -or $base -ieq 'OpenConsole') -and $found -notcontains "$base (child)") {
        $found += "$base (child)"
      }
    }
  }
  if ($found.Count -gt 0) { 'terminal from parent chain: ' + ($found -join ', ') }
  else { 'terminal from parent chain: not found' }
  'environment of the agent: not available: Windows cannot read the environment of another process without extra tools'
}

# The environment of the probe itself. It prints only whether a variable is
# set, not its value.
function Get-OwnTerminalHints {
  foreach ($v in 'WT_SESSION', 'WT_PROFILE_ID', 'TERM_PROGRAM', 'TMUX', 'PSMUX', 'ConEmuPID', 'VSCODE_PID') {
    $val = [Environment]::GetEnvironmentVariable($v)
    if ($val) { "probe environment ${v}: set" } else { "probe environment ${v}: not set" }
  }
}

# Caution: the first run of Sysinternals handle.exe can show a licence
# dialog. The probe does not accept the licence for you, because that
# writes a registry value. Accept it once by hand before you run the probe.
# The probe stops handle.exe after 30 s.
function Get-OpenFiles([int]$ProcessId, [string]$FolderPattern) {
  $tool = $null
  foreach ($t in 'handle64.exe', 'handle.exe') {
    $c = Get-Command $t -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { $tool = $c.Source; break }
  }
  if (-not $tool) { 'not available: open files need Sysinternals handle.exe'; return }
  $r = Invoke-Captured $tool "-nobanner -p $ProcessId" 30000
  if ($r.TimedOut) { 'handle: no answer in 30 s'; return }
  $lines = @(((Remove-Ansi $r.Out) -split "`r?`n") | Where-Object { $_ -match $FolderPattern })
  if ($lines.Count -eq 0) { 'open files in the state folder: not found'; return }
  foreach ($l in $lines) { $l.Trim() }
}

# Returns the candidate folders for a state folder name below the home
# folder and below APPDATA and LOCALAPPDATA.
function Get-StateCandidates([string[]]$Names) {
  $bases = @($env:USERPROFILE, $HOME, $env:APPDATA, $env:LOCALAPPDATA) | Where-Object { $_ } | Select-Object -Unique
  $out = @()
  foreach ($b in $bases) {
    foreach ($n in $Names) {
      $p = Join-Path $b $n
      if ($out -notcontains $p) { $out += $p }
    }
  }
  return $out
}

function Find-StateDir([string[]]$Candidates) {
  foreach ($c in $Candidates) {
    if (Test-Path -LiteralPath $c -PathType Container) { return $c }
  }
  return $null
}

$script:LayoutCount = 0

function Show-LayoutLevel([string]$Dir, [string]$Prefix, [int]$Depth, [int]$Max) {
  $items = @(Get-ChildItem -LiteralPath $Dir -Force -ErrorAction SilentlyContinue | Sort-Object Name)
  $shown = 0
  foreach ($i in $items) {
    if ($script:LayoutCount -ge $Max) { return }
    if ($shown -ge 25) {
      $script:LayoutCount++
      "$Prefix... $($items.Count - $shown) more entries"
      return
    }
    $shown++
    $script:LayoutCount++
    $t = ConvertTo-UnixTime $i.LastWriteTimeUtc
    $link = ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
    if ($i.PSIsContainer) {
      $n = @(Get-ChildItem -LiteralPath $i.FullName -Force -ErrorAction SilentlyContinue).Count
      $mark = ''
      if ($link) { $mark = ' link' }
      "$Prefix$($i.Name)/ entries=$n mtime=$t$mark"
      if ($Depth -gt 1 -and -not $link) {
        Show-LayoutLevel $i.FullName ($Prefix + '  ') ($Depth - 1) $Max
      }
    } else {
      "$Prefix$($i.Name) size=$($i.Length) mtime=$t"
    }
  }
}

# Prints names, sizes and times below Dir, at most 200 lines.
function Get-Layout([string]$Dir, [int]$Depth = 2) {
  if (-not $Dir -or -not (Test-Path -LiteralPath $Dir -PathType Container)) { "not found: $Dir"; return }
  "layout: $Dir"
  $script:LayoutCount = 0
  Show-LayoutLevel $Dir '  ' $Depth 200
  if ($script:LayoutCount -ge 200) { '  ... stop at 200 lines' }
}

function Get-JsonType($Value) {
  if ($null -eq $Value) { return 'null' }
  if ($Value -is [string]) { return 'string' }
  if ($Value -is [bool]) { return 'bool' }
  if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) { return 'number' }
  if ($Value -is [array]) { return "array[$($Value.Count)]" }
  if ($Value -is [System.Management.Automation.PSCustomObject]) { return 'object' }
  return $Value.GetType().Name
}

function Read-Json([string]$File) {
  $text = [IO.File]::ReadAllText($File, [Text.Encoding]::UTF8)
  return ($text | ConvertFrom-Json)
}

# Prints the top-level keys of a JSON file and the type of each value.
function Get-JsonKeys([string]$File) {
  if (-not $File -or -not (Test-Path -LiteralPath $File -PathType Leaf)) { "not found: $File"; return }
  $d = Read-Json $File
  if ($d -isnot [System.Management.Automation.PSCustomObject]) { "top level: $(Get-JsonType $d)"; return }
  foreach ($prop in $d.PSObject.Properties) { "$($prop.Name): $(Get-JsonType $prop.Value)" }
}

# Prints the key paths and the value types of a JSON file, to MaxDepth.
# For an array it shows the first item only. It prints no values.
function Get-JsonShape([string]$File, [int]$MaxDepth = 3) {
  if (-not $File -or -not (Test-Path -LiteralPath $File -PathType Leaf)) { "not found: $File"; return }
  $d = Read-Json $File
  Show-JsonShape $d '' $MaxDepth
}

function Show-JsonShape($Value, [string]$Path, [int]$Depth) {
  $name = $Path
  if (-not $name) { $name = '(top)' }
  "${name}: $(Get-JsonType $Value)"
  if ($Depth -le 0) { return }
  if ($Value -is [System.Management.Automation.PSCustomObject]) {
    foreach ($prop in $Value.PSObject.Properties) {
      $p = $prop.Name
      if ($Path) { $p = "$Path.$($prop.Name)" }
      Show-JsonShape $prop.Value $p ($Depth - 1)
    }
  } elseif ($Value -is [array] -and $Value.Count -gt 0) {
    Show-JsonShape $Value[0] "$Path[0]" ($Depth - 1)
  }
}

# Prints a type value only when it looks like a type name, not text.
function Get-SafeType($Value) {
  if ($null -eq $Value) { return '-' }
  $s = [string]$Value
  if ($s -match '^[A-Za-z0-9_.:/-]{1,48}$') { return $s }
  return '<other>'
}

# For the last N lines of a JSONL file: "type", "payload.type", and the
# "type" of each item of message.content. It prints no text.
function Get-JsonlTypes([string]$File, [int]$Count = 5) {
  if (-not $File -or -not (Test-Path -LiteralPath $File -PathType Leaf)) { "not found: $File"; return }
  $lines = @(Get-Content -LiteralPath $File -Tail $Count -Encoding UTF8)
  foreach ($l in $lines) {
    if (-not $l.Trim()) { 'empty line'; continue }
    try { $d = $l | ConvertFrom-Json } catch { 'bad line'; continue }
    if ($d -isnot [System.Management.Automation.PSCustomObject]) { "line: $(Get-JsonType $d)"; continue }
    $type = Get-SafeType $d.type
    $ptype = '-'
    if ($d.payload -is [System.Management.Automation.PSCustomObject]) { $ptype = Get-SafeType $d.payload.type }
    $ctypes = '-'
    if ($d.message -is [System.Management.Automation.PSCustomObject]) {
      $c = $d.message.content
      if ($c -is [array]) {
        $ctypes = '[' + ((@($c | ForEach-Object {
          if ($_ -is [System.Management.Automation.PSCustomObject]) { Get-SafeType $_.type } else { Get-JsonType $_ }
        })) -join ',') + ']'
      } elseif ($null -ne $c) {
        $ctypes = Get-JsonType $c
      }
    }
    "type=$type payload.type=$ptype message.content=$ctypes"
  }
}

# Prints the table names of a TOML file, not the keys or values.
function Get-TomlTables([string]$File) {
  if (-not $File -or -not (Test-Path -LiteralPath $File -PathType Leaf)) { "not found: $File"; return }
  $n = 0
  foreach ($l in [IO.File]::ReadAllLines($File, [Text.Encoding]::UTF8)) {
    if ($l -match '^\s*(\[\[?[^\]]+\]\]?)') { "table: $($Matches[1])"; $n++ }
  }
  if ($n -eq 0) { 'tables: none' }
}

# Prints the newest file that matches Filter below Dir.
function Get-NewestFile([string]$Dir, [string]$Filter) {
  if (-not $Dir -or -not (Test-Path -LiteralPath $Dir -PathType Container)) { return $null }
  return Get-ChildItem -LiteralPath $Dir -Recurse -Force -File -Filter $Filter -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
}

# Prints the install path of a command and where the version shows: in a
# folder name, in a package.json, or in the output of --version.
function Show-Install([string[]]$Commands, [string[]]$NpmPackages, [string[]]$Dirs) {
  foreach ($c in $Commands) {
    $all = @(Get-Command $c -All -ErrorAction SilentlyContinue)
    if ($all.Count -eq 0) { "command ${c}: not installed"; continue }
    foreach ($a in $all) {
      if (-not $a.Source) { continue }
      $r = Get-ResolvedPath $a.Source
      "command ${c}: $($a.Source) -> $r"
      $m = [regex]::Matches($r, '\d+\.\d+\.\d+[A-Za-z0-9._+-]*')
      foreach ($x in $m) { "version in path: $($x.Value)" }
      $dir = Split-Path -Parent $r
      Get-Layout $dir 2
      # The version file of an npm package is near the binary.
      $up = $dir
      for ($k = 0; $k -lt 4 -and $up; $k++) {
        $pj = Join-Path $up 'package.json'
        if (Test-Path -LiteralPath $pj -PathType Leaf) {
          try {
            $j = Read-Json $pj
            "package.json: $pj name=$($j.name) version=$($j.version)"
          } catch { "package.json: $pj error: " + $_.Exception.GetType().Name }
          break
        }
        $up = Split-Path -Parent $up
      }
    }
  }
  $npmRoot = $null
  if ($env:APPDATA) { $npmRoot = Join-Path $env:APPDATA 'npm\node_modules' }
  foreach ($pkg in $NpmPackages) {
    if (-not $npmRoot) { break }
    $pj = Join-Path (Join-Path $npmRoot $pkg) 'package.json'
    if (Test-Path -LiteralPath $pj -PathType Leaf) {
      try { $j = Read-Json $pj; "npm package ${pkg}: version=$($j.version)" }
      catch { "npm package ${pkg}: error: " + $_.Exception.GetType().Name }
    } else { "npm package ${pkg}: not found" }
  }
  foreach ($d in $Dirs) {
    if (-not $d) { continue }
    Get-Layout $d 2
  }
}

# Lists the WinGet and Scoop package folders whose names match Pattern.
function Show-PackageFolders([string]$Pattern) {
  $roots = @()
  if ($env:LOCALAPPDATA) { $roots += (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages') }
  if ($env:USERPROFILE) { $roots += (Join-Path $env:USERPROFILE 'scoop\apps') }
  foreach ($r in $roots) {
    if (-not (Test-Path -LiteralPath $r -PathType Container)) { "not found: $r"; continue }
    $hits = @(Get-ChildItem -LiteralPath $r -Force -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $Pattern })
    if ($hits.Count -eq 0) { "no match in: $r"; continue }
    foreach ($h in $hits) { Get-Layout $h.FullName 2 }
  }
}

# psmux is a tmux for Windows. This function reads its version, its
# session list and its pane counts. Session names become <arg>.
# Note: under PowerShell, psmux "send-keys ... C-m" sends a literal ^M.
# Use Enter instead. The aw project measured this with psmux 3.4.0.
# The probe sends no keys.
function Show-Psmux {
  foreach ($t in 'psmux', 'tmux') {
    $file = Get-CommandFile $t
    if (-not $file) { "not installed: $t"; continue }
    "command ${t}: $file -> $(Get-ResolvedPath $file)"
    $v = Invoke-Captured $file '-V' 15000
    $vl = Get-FirstLine ($v.Out + "`n" + $v.Err)
    if ($v.TimedOut) { $vl = 'no answer in 15 s' }
    "version ${t}: $vl"
    $ls = Invoke-Captured $file 'ls' 15000
    if ($ls.TimedOut) { "${t} ls: no answer in 15 s"; continue }
    $names = @{}
    $n = 0
    foreach ($l in ((Remove-Ansi ($ls.Out + "`n" + $ls.Err)) -split "`r?`n")) {
      if (-not $l.Trim()) { continue }
      if ($l -match '^([^:]+):(.*)$') {
        $n++
        $names[$Matches[1]] = "<arg$n>"
        "${t} ls: <arg$n>:" + ($Matches[2] -replace '\(created [^)]*\)', '(created <time>)')
      } elseif ($l -match '(?i)no server running|error connecting|no sessions|failed to connect') {
        "${t} ls: no server or no sessions"
      } else {
        "${t} ls: a line of other text (not shown)"
      }
    }
    if ($n -eq 0) { "${t} sessions: not found"; continue }
    $panes = Invoke-Captured $file 'list-panes -a' 15000
    if ($panes.TimedOut) { "${t} list-panes: no answer in 15 s"; continue }
    $count = @{}
    foreach ($l in ((Remove-Ansi $panes.Out) -split "`r?`n")) {
      if ($l -match '^([^:]+):') {
        $k = $Matches[1]
        if ($names.ContainsKey($k)) { $k = $names[$k] } else { $k = '<other>' }
        $count[$k] = 1 + [int]$count[$k]
      }
    }
    if ($count.Count -eq 0) { "${t} panes: not found" }
    foreach ($k in ($count.Keys | Sort-Object)) { "${t} session ${k}: panes=$($count[$k])" }
  }
}
