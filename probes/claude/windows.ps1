# Read-only probe of Claude Code sessions on Windows.
# It reads process data, the parent chain, the pid files of the sessions,
# the layout of the state folder, the record types of the newest
# transcript, and the names of the hook events. It reads no conversation
# text.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File probes\claude\windows.ps1 > claude-probe.txt
# The output holds real folder and project names. Do not commit it.
# Scrub it before a fact uses it: tools\scrub.ps1, or use probes\run.ps1.

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib.ps1')

$script:Pattern = '(?i)(^|[\\/ "])claude(\.exe|\.cmd)?("|\s|$)|@anthropic-ai[\\/]claude-code'
$script:Procs = @()
$script:State = $null
$candidates = @()
if ($env:CLAUDE_CONFIG_DIR) { $candidates += $env:CLAUDE_CONFIG_DIR }
$candidates += Get-StateCandidates @('.claude', 'claude')

Header 'claude/windows' '1' @('claude')

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
    Get-OpenFiles ([int]$p.ProcessId) '(?i)\\\.?claude\\'
  }
}

Invoke-Section 'State folder layout (names, sizes, times)' {
  foreach ($c in $candidates) {
    if (Test-Path -LiteralPath $c -PathType Container) { Get-Layout $c 2 } else { "not found: $c" }
  }
  $script:State = Find-StateDir $candidates
}

Invoke-Section 'Session pid files: keys and status of each live process' {
  if (-not $script:State) { 'not found: state folder'; return }
  $dir = Join-Path $script:State 'sessions'
  Get-Layout $dir 1
  if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return }
  $keys = @(Get-ChildItem -LiteralPath $dir -Force -File -Filter '*.key' -ErrorAction SilentlyContinue)
  "key files: $($keys.Count)"
  foreach ($p in $script:Procs) {
    $f = Join-Path $dir "$($p.ProcessId).json"
    "== $($p.ProcessId)"
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { "pid file: not found"; continue }
    Get-JsonKeys $f
    $d = Read-Json $f
    # The status value is a state name, not text. It is safe to print.
    "status: $(Get-SafeType $d.status)"
    "kind: $(Get-SafeType $d.kind)"
  }
}

Invoke-Section 'Newest transcript: record types of the last 5 lines (no text)' {
  if (-not $script:State) { 'not found: state folder'; return }
  $t = Get-NewestFile (Join-Path $script:State 'projects') '*.jsonl'
  if (-not $t) { return }
  "transcript: $($t.FullName) size=$($t.Length) mtime=$(ConvertTo-UnixTime $t.LastWriteTimeUtc)"
  Get-JsonlTypes $t.FullName 5
}

Invoke-Section 'Hooks config: events and hook types (no commands)' {
  if (-not $script:State) { 'not found: state folder'; return }
  foreach ($name in 'settings.json', 'settings.local.json') {
    $f = Join-Path $script:State $name
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { "not found: $f"; continue }
    "file: $f"
    $d = Read-Json $f
    'top-level keys: ' + ((@($d.PSObject.Properties | ForEach-Object { $_.Name })) -join ', ')
    if ($null -eq $d.hooks) { 'hooks: not found'; continue }
    foreach ($ev in $d.hooks.PSObject.Properties) {
      $types = @()
      foreach ($m in @($ev.Value)) {
        foreach ($h in @($m.hooks)) { if ($h) { $types += (Get-SafeType $h.type) } }
      }
      "hook event $($ev.Name): matchers=$(@($ev.Value).Count) hook types=[$($types -join ',')]"
    }
  }
}

Invoke-Section 'Install path and where the version shows' {
  $dirs = @()
  if ($env:USERPROFILE) {
    $dirs += (Join-Path $env:USERPROFILE '.local\bin')
    $dirs += (Join-Path $env:USERPROFILE '.local\share\claude')
  }
  Show-Install @('claude') @('@anthropic-ai\claude-code') $dirs
  Show-PackageFolders '(?i)claude'
}

Invoke-Section 'psmux or tmux: version, sessions and panes' {
  Show-Psmux
}

exit 0
