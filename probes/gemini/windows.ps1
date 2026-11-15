# Read-only probe of Gemini CLI sessions on Windows.
# It reads process data, the parent chain, open file names, and the layout
# of %USERPROFILE%\.gemini without the folders of agy (antigravity-cli,
# config). It reads no conversation text.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File probes\gemini\windows.ps1 > gemini-probe.txt
# The output holds real folder and project names. Do not commit it.
# Scrub it before a fact uses it: tools\scrub.ps1, or use probes\run.ps1.

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib.ps1')

# The npm package runs as node with a script below @google\gemini-cli.
# The name "gemini" alone must not match the agy folder .gemini\antigravity-cli.
$script:Pattern = '(?i)(^|[\\/ "])gemini(\.exe|\.cmd)?("|\s|$)|@google[\\/]gemini-cli'
$script:Procs = @()
# Gemini CLI keeps .gemini below GEMINI_CLI_HOME when it is set.
$gh = if ($env:GEMINI_CLI_HOME) { $env:GEMINI_CLI_HOME } else { $env:USERPROFILE }
$g = if ($gh) { Join-Path $gh '.gemini' } else { '' }
# Hide-Project: the folder below .gemini\tmp is named after the project, so
# it becomes <project>, as in gemini/unix.sh.
function Hide-Project([string]$Line) { return ($Line -replace '(?i)(\\\.gemini\\tmp\\)[^\\]+', '$1<project>') }

Header 'gemini/windows' '1' @('gemini')

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

Invoke-Section 'Open Gemini files of each process' {
  foreach ($p in $script:Procs) {
    "== $($p.ProcessId)"
    Get-OpenFiles ([int]$p.ProcessId) '(?i)\\\.gemini\\(?!antigravity-cli\\)' | ForEach-Object { Hide-Project ([string]$_) }
  }
}

Invoke-Section 'Layout of .gemini (one level, agy folders left out)' {
  if ($g -and (Test-Path -LiteralPath $g -PathType Container)) {
    Get-Layout $g 1 | Where-Object { $_ -notmatch '^\s*(antigravity-cli|config)/ ' }
    $t = Join-Path $g 'tmp'
    $n = @(Get-ChildItem -LiteralPath $t -Directory -Force -ErrorAction SilentlyContinue).Count
    "tmp folders: $n"
  } else {
    "not found: $g"
  }
}

Invoke-Section 'Newest session file below .gemini\tmp: name, size and time (no content)' {
  if ($g) {
    $f = Get-NewestFile (Join-Path $g 'tmp') '*.json*'
    if ($f) { "newest file: $(Hide-Project $f.FullName) size=$($f.Length) mtime=$(ConvertTo-UnixTime $f.LastWriteTimeUtc)" } else { 'none' }
  }
}

Invoke-Section 'Settings: keys (no values)' {
  $f = if ($g) { Join-Path $g 'settings.json' } else { '' }
  if ($f -and (Test-Path -LiteralPath $f -PathType Leaf)) {
    "file: $f"
    try { Get-JsonKeys $f } catch { 'keys: error: ' + $_.Exception.GetType().Name }
  } else {
    "not found: $f"
  }
}

Invoke-Section 'Install path and where the version shows' {
  Show-Install @('gemini') @('@google/gemini-cli') @()
  Show-PackageFolders '(?i)gemini-cli'
}

Invoke-Section 'psmux or tmux: version, sessions and panes' {
  Show-Psmux
}

exit 0
