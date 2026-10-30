# Read-only probe of agy (Antigravity CLI) sessions on Windows.
# It reads process data, the parent chain, the layout of the state folder,
# the record types of the newest transcript, and the shape of the hooks
# file. It opens no conversation database and reads no conversation text.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File probes\agy\windows.ps1 > agy-probe.txt
# The output holds real folder and project names. Do not commit it.
# Scrub it before a fact uses it: tools\scrub.ps1, or use probes\run.ps1.

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib.ps1')

$script:Pattern = '(?i)(^|[\\/ "])agy(\.exe|\.cmd)?("|\s|$)|antigravity-cli'
$script:Procs = @()
$script:State = $null
$candidates = Get-StateCandidates @('.gemini\antigravity-cli', 'gemini\antigravity-cli', 'antigravity-cli')
$hookCandidates = Get-StateCandidates @('.gemini\config', 'gemini\config')

Header 'agy/windows' '1' @('agy')

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
    Get-OpenFiles ([int]$p.ProcessId) '(?i)\\\.?gemini\\'
  }
}

# The conversations folder holds one .db file for each conversation. The
# probe lists the names only. It does not open a database.
Invoke-Section 'State folder layout (names, sizes, times)' {
  foreach ($c in $candidates) {
    if (Test-Path -LiteralPath $c -PathType Container) { Get-Layout $c 2 } else { "not found: $c" }
  }
  $script:State = Find-StateDir $candidates
  if ($script:State) {
    foreach ($sub in 'presence', 'log', 'crashes') { Get-Layout (Join-Path $script:State $sub) 1 }
  }
}

Invoke-Section 'Newest transcript: record types of the last 5 lines (no text)' {
  if (-not $script:State) { 'not found: state folder'; return }
  $t = Get-NewestFile (Join-Path $script:State 'brain') 'transcript.jsonl'
  if (-not $t) { return }
  "transcript: $($t.FullName) size=$($t.Length) mtime=$(ConvertTo-UnixTime $t.LastWriteTimeUtc)"
  Get-JsonlTypes $t.FullName 5
}

# The hooks file on Linux has this shape:
# {"<group>": {"<event>": [{"type", "command", "timeout"}]}}.
Invoke-Section 'Hooks config: groups, events and item keys (no commands)' {
  foreach ($c in $hookCandidates) {
    $f = Join-Path $c 'hooks.json'
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { "not found: $f"; continue }
    "file: $f"
    Get-JsonShape $f 3
  }
}

Invoke-Section 'Install path and where the version shows' {
  $dirs = @()
  if ($env:LOCALAPPDATA) { $dirs += (Join-Path $env:LOCALAPPDATA 'Programs\agy') }
  if ($env:USERPROFILE) { $dirs += (Join-Path $env:USERPROFILE '.local\bin') }
  Show-Install @('agy') @() $dirs
  Show-PackageFolders '(?i)agy|antigravity'
}

Invoke-Section 'psmux or tmux: version, sessions and panes' {
  Show-Psmux
}

exit 0
