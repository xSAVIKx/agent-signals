# Read-only probe of opencode sessions on Windows.
# It reads process data, the parent chain, the layout of the data and
# config folders, and the keys of the config file. It reads no
# conversation text.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File probes\opencode\windows.ps1 > opencode-probe.txt
# The output holds real folder and project names. Do not commit it.
# Scrub it before a fact uses it: tools\scrub.ps1, or use probes\run.ps1.

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib.ps1')

$script:Pattern = '(?i)opencode'
$script:Procs = @()
$candidates = @()
if ($env:USERPROFILE) {
  $candidates += (Join-Path $env:USERPROFILE '.local\share\opencode')
  $candidates += (Join-Path $env:USERPROFILE '.config\opencode')
}
if ($env:APPDATA) { $candidates += (Join-Path $env:APPDATA 'opencode') }
if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA 'opencode') }

Header 'opencode/windows' '1' @('opencode')

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
    Get-OpenFiles ([int]$p.ProcessId) '(?i)\\opencode\\'
  }
}

Invoke-Section 'State folder layout (names, sizes, times)' {
  foreach ($c in $candidates) {
    if (Test-Path -LiteralPath $c -PathType Container) { Get-Layout $c 3 } else { "not found: $c" }
  }
}

# opencode keeps its sessions as many small JSON files. The probe prints
# the layout only, not the content.
Invoke-Section 'Newest session file: name, size and time (no content)' {
  foreach ($c in $candidates) {
    $f = Get-NewestFile $c '*.json'
    if ($f) { "newest json below ${c}: $($f.FullName) size=$($f.Length) mtime=$(ConvertTo-UnixTime $f.LastWriteTimeUtc)" }
  }
}

Invoke-Section 'Config and plugins: keys (no values)' {
  foreach ($c in $candidates) {
    foreach ($name in 'opencode.json', 'opencode.jsonc', 'config.json') {
      $f = Join-Path $c $name
      if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { continue }
      "file: $f"
      try { Get-JsonKeys $f } catch { 'keys: error: ' + $_.Exception.GetType().Name }
    }
    foreach ($sub in 'plugin', 'plugins') {
      $d = Join-Path $c $sub
      if (Test-Path -LiteralPath $d -PathType Container) { Get-Layout $d 1 }
    }
  }
}

Invoke-Section 'Install path and where the version shows' {
  $dirs = @()
  if ($env:USERPROFILE) { $dirs += (Join-Path $env:USERPROFILE '.opencode\bin') }
  Show-Install @('opencode') @('opencode-ai') $dirs
  Show-PackageFolders '(?i)opencode'
}

Invoke-Section 'psmux or tmux: version, sessions and panes' {
  Show-Psmux
}

exit 0
