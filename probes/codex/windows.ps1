# Read-only probe of Codex CLI sessions on Windows.
# It reads process data, the parent chain, the app-server daemon, the
# layout of the state folder, the record types of the newest rollout file,
# the table names of config.toml, and the install folder. It reads no
# conversation text and no config values.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File probes\codex\windows.ps1 > codex-probe.txt
# The output holds real folder and project names. Do not commit it.
# Scrub it before a fact uses it: tools\scrub.ps1, or use probes\run.ps1.

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib.ps1')

$script:Pattern = '(?i)codex'
$script:Procs = @()
$script:State = $null
$candidates = @()
if ($env:CODEX_HOME) { $candidates += $env:CODEX_HOME }
$candidates += Get-StateCandidates @('.codex', 'codex')

Header 'codex/windows' '1' @('codex')

Invoke-Section 'Processes: pid ppid start name command' {
  $script:Procs = @(Get-AgentProcesses $script:Pattern)
  foreach ($p in $script:Procs) { Format-ProcessLine $p }
}

# On Linux and macOS the TUI starts a shared daemon by default:
# "codex app-server --listen unix:// --managed-daemon".
Invoke-Section 'App-server daemon processes' {
  foreach ($p in $script:Procs) {
    if (-not ($p.CommandLine -and $p.CommandLine -match 'app-server')) { continue }
    $listen = 'no'
    if ($p.CommandLine -match '--listen') { $listen = 'yes' }
    $managed = 'no'
    if ($p.CommandLine -match '--managed-daemon') { $managed = 'yes' }
    "daemon pid=$($p.ProcessId) ppid=$($p.ParentProcessId) --listen=$listen --managed-daemon=$managed"
    if ($p.CommandLine -match '--listen[ =]"?([a-z]+://)') { "listen scheme: $($Matches[1])" }
  }
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
    Get-OpenFiles ([int]$p.ProcessId) '(?i)\\\.?codex\\'
  }
}

Invoke-Section 'State folder layout (names, sizes, times)' {
  foreach ($c in $candidates) {
    if (Test-Path -LiteralPath $c -PathType Container) { Get-Layout $c 2 } else { "not found: $c" }
  }
  $script:State = Find-StateDir $candidates
  if ($script:State) {
    Get-Layout (Join-Path $script:State 'thread-writer-locks') 1
  }
}

Invoke-Section 'Newest rollout file: record types of the last 5 lines (no text)' {
  if (-not $script:State) { 'not found: state folder'; return }
  $t = Get-NewestFile (Join-Path $script:State 'sessions') 'rollout-*.jsonl'
  if (-not $t) { return }
  "rollout: $($t.FullName) size=$($t.Length) mtime=$(ConvertTo-UnixTime $t.LastWriteTimeUtc)"
  Get-JsonlTypes $t.FullName 5
}

Invoke-Section 'Config and hooks: table names and keys (no values)' {
  if (-not $script:State) { 'not found: state folder'; return }
  $toml = Join-Path $script:State 'config.toml'
  "file: $toml"
  Get-TomlTables $toml
  $hooks = Join-Path $script:State 'hooks.json'
  "file: $hooks"
  Get-JsonShape $hooks 3
}

# The standalone install puts the version in the path:
# packages\...\releases\<version>-<target>\bin\codex.
Invoke-Section 'Install path and where the version shows' {
  $dirs = @()
  $state = Find-StateDir $candidates
  if ($state) { $dirs += (Join-Path $state 'packages') }
  Show-Install @('codex') @('@openai\codex') $dirs
  if ($state) {
    $bins = @(Get-ChildItem -LiteralPath (Join-Path $state 'packages') -Recurse -Force -File -Filter 'codex*.exe' -ErrorAction SilentlyContinue)
    foreach ($b in $bins) { "packaged binary: $($b.FullName) size=$($b.Length)" }
  }
  Show-PackageFolders '(?i)codex'
}

Invoke-Section 'psmux or tmux: version, sessions and panes' {
  Show-Psmux
}

exit 0
