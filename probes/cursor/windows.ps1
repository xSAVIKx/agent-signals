# Read-only probe of Cursor CLI sessions on Windows.
# It reads process data, the parent chain, the layout of the state folder,
# the keys of meta.json and cli-config.json, the record types of the newest
# transcript, the shape of hooks.json, and the login state. It opens no
# store.db and reads no conversation text.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File probes\cursor\windows.ps1 > cursor-probe.txt
# The output holds real folder and project names. Do not commit it.
# Scrub it before a fact uses it: tools\scrub.ps1, or use probes\run.ps1.

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib.ps1')

$script:Pattern = '(?i)cursor-agent|^agent(\.exe)?$|[\\/]agent(\.exe|\.cmd)?("|\s|$)'
$script:Procs = @()
$script:State = $null
$candidates = Get-StateCandidates @('.cursor', 'cursor')

Header 'cursor/windows' '1' @('agent', 'cursor-agent')

Invoke-Section 'Processes: pid ppid start name command' {
  $script:Procs = @(Get-AgentProcesses $script:Pattern)
  foreach ($p in $script:Procs) { Format-ProcessLine $p }
}

Invoke-Section 'Parent chain and terminal of each process' {
  Get-OwnTerminalHints
  foreach ($p in $script:Procs) {
    "== $($p.ProcessId)"
    Get-ParentChain ([int]$p.ProcessId)
    Get-TerminalHints $p
  }
}

Invoke-Section 'Open files in the state folder' {
  foreach ($p in $script:Procs) {
    "== $($p.ProcessId)"
    Get-OpenFiles ([int]$p.ProcessId) '(?i)\\\.?cursor\\'
  }
}

Invoke-Section 'State folder layout (names, sizes, times)' {
  foreach ($c in $candidates) {
    if (Test-Path -LiteralPath $c -PathType Container) { Get-Layout $c 2 } else { "not found: $c" }
  }
  $script:State = Find-StateDir $candidates
}

# A live store.db cannot be opened, and a copy would hold chat text. This
# section lists file names, sizes and times, and the keys of meta.json.
Invoke-Section 'Newest chat folder: layout and meta.json keys (no content)' {
  if (-not $script:State) { 'not found: state folder'; return }
  $db = Get-NewestFile (Join-Path $script:State 'chats') 'store.db'
  if (-not $db) { return }
  $dir = Split-Path -Parent $db.FullName
  Get-Layout $dir 1
  $meta = Join-Path $dir 'meta.json'
  "file: $meta"
  Get-JsonKeys $meta
}

Invoke-Section 'Newest transcript: record types of the last 5 lines (no text)' {
  if (-not $script:State) { 'not found: state folder'; return }
  $projects = Join-Path $script:State 'projects'
  if (-not (Test-Path -LiteralPath $projects -PathType Container)) { "not found: $projects"; return }
  $t = Get-ChildItem -LiteralPath $projects -Recurse -Force -File -Filter '*.jsonl' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '[\\/]agent-transcripts[\\/]' } |
    Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
  if (-not $t) { return }
  "transcript: $($t.FullName) size=$($t.Length) mtime=$(ConvertTo-UnixTime $t.LastWriteTimeUtc)"
  Get-JsonlTypes $t.FullName 5
}

Invoke-Section 'Config and hooks: keys (no values)' {
  if (-not $script:State) { 'not found: state folder'; return }
  $cfg = Join-Path $script:State 'cli-config.json'
  "file: $cfg"
  Get-JsonKeys $cfg
  $hooks = Join-Path $script:State 'hooks.json'
  "file: $hooks"
  Get-JsonShape $hooks 3
}

# "cursor-agent status" prints "Not logged in" and starts no login. When
# a user is logged in, the first line can hold an e-mail address. The probe
# prints only whether the first line says "Not logged in".
Invoke-Section 'Login state' {
  $file = Get-CommandFile 'cursor-agent'
  if (-not $file) { $file = Get-CommandFile 'agent' }
  if (-not $file) { 'not installed: cursor-agent'; return }
  $r = Invoke-Captured $file 'status' 15000
  if ($r.TimedOut) { 'status: no answer in 15 s'; return }
  $first = Get-FirstLine ($r.Out + "`n" + $r.Err)
  if ($first -match '(?i)not logged in') { 'status first line: Not logged in' }
  else { 'status first line: not "Not logged in" (not shown)' }
}

Invoke-Section 'Install path and where the version shows' {
  $dirs = @()
  if ($env:LOCALAPPDATA) {
    $dirs += (Join-Path $env:LOCALAPPDATA 'cursor-agent')
    $dirs += (Join-Path $env:LOCALAPPDATA 'Programs\cursor-agent')
  }
  if ($env:USERPROFILE) { $dirs += (Join-Path $env:USERPROFILE '.local\bin') }
  Show-Install @('agent', 'cursor-agent') @() $dirs
  Show-PackageFolders '(?i)cursor'
}

Invoke-Section 'psmux or tmux: version, sessions and panes' {
  Show-Psmux
}

exit 0
