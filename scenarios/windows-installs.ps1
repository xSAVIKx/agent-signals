# Scenario: the install layout of each agent on Windows, with no login.
#
# For each agent command it records: where Get-Command finds it, what
# "<cmd> --version" prints, the version in the package files, and the
# folders and binaries of the install. It also lists the folders that the
# "--version" calls made in the home folder. It starts no agent
# interactively: there is no terminal driver for Windows yet.
# It answers: where does each Windows install keep its version, and what
# does the install folder look like?
#
# Needs: the agents, installed by the caller (the scenarios workflow).
# No login, no model turn, no cost.
# Run: pwsh -NoProfile -File scenarios\windows-installs.ps1 NAME=CMD[=NPMPKG] ...
#   NAME is a label, CMD the command, NPMPKG the npm package (optional).
#
# The output goes through tools\scrub.ps1 before it is printed.

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'tools\scrub.ps1')

$sb = New-Object System.Text.StringBuilder
function Out-Line([string]$Text) { [void]$sb.AppendLine($Text) }

# Run-Capped FILE ARGS: run a program with a time limit of 60 s and return
# its first 5 lines of output. A command that waits for input gets no
# input and stops at the limit.
function Run-Capped([string]$File, [string]$Arguments) {
  $info = New-Object System.Diagnostics.ProcessStartInfo
  $info.FileName = $File
  $info.Arguments = $Arguments
  $info.UseShellExecute = $false
  $info.RedirectStandardOutput = $true
  $info.RedirectStandardError = $true
  $info.RedirectStandardInput = $true
  $info.CreateNoWindow = $true
  try { $p = [System.Diagnostics.Process]::Start($info) } catch { return "start failed: $($_.Exception.Message)" }
  $p.StandardInput.Close()
  $out = $p.StandardOutput.ReadToEndAsync()
  $err = $p.StandardError.ReadToEndAsync()
  $status = ''
  if (-not $p.WaitForExit(60000)) {
    try { $p.Kill($true) } catch { try { $p.Kill() } catch { } }
    $status = 'did not stop in 60 s'
  }
  [void]$out.Wait(5000)
  [void]$err.Wait(5000)
  $text = ($out.Result + $err.Result) -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 5
  if ($p.HasExited) { $status = "exit $($p.ExitCode)" }
  return (@($text) + "($status)") -join "`n"
}

# Show-Tree DIR DEPTH: list the folders below DIR to DEPTH, the files at
# the first level, and the .exe and .node files at the first two levels.
# A folder that was listed before is not listed again.
$script:Shown = @{}
function Show-Tree([string]$Dir, [int]$Depth) {
  if (-not (Test-Path -LiteralPath $Dir)) { Out-Line "  (no folder $Dir)"; return }
  Out-Line "  folder: $Dir"
  if ($script:Shown.ContainsKey($Dir)) { Out-Line '  (listed above)'; return }
  $script:Shown[$Dir] = $true
  $base = (Resolve-Path -LiteralPath $Dir).ProviderPath.TrimEnd('\')
  $items = Get-ChildItem -LiteralPath $Dir -Recurse -Depth ($Depth - 1) -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\node_modules\\.+\\node_modules\\' }
  $n = 0
  foreach ($i in $items) {
    $rel = $i.FullName.Substring($base.Length).TrimStart('\')
    $level = ($rel -split '\\').Count
    if ($i.PSIsContainer) {
      if ($level -gt 2) { continue }
      $line = "  d $rel\"
    } elseif ($level -eq 1 -or ($level -eq 2 -and $i.Extension -in '.exe', '.node')) {
      $line = "  f $rel ($($i.Length) bytes)"
    } else {
      continue
    }
    Out-Line $line
    $n++
    if ($n -ge 30) { Out-Line '  (more entries not shown)'; break }
  }
}

# Get-HomeFolders: the hidden folders and files in the home folder, and the
# folders in %APPDATA% and %LOCALAPPDATA%.
function Get-HomeFolders {
  $list = @(Get-ChildItem -LiteralPath $HOME -Force -ErrorAction SilentlyContinue |
      Where-Object { $_.Name.StartsWith('.') } | ForEach-Object { $_.FullName })
  foreach ($a in @($env:APPDATA, $env:LOCALAPPDATA)) {
    if (-not $a) { continue }
    $list += @(Get-ChildItem -LiteralPath $a -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
  }
  return @($list | Sort-Object)
}

$npmRoot = (& npm root -g 2>$null | Select-Object -First 1)
$npmPrefix = (& npm prefix -g 2>$null | Select-Object -First 1)
Out-Line '# agent-signals Windows install layout'
Out-Line ('date: ' + (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))
Out-Line "os: $([System.Environment]::OSVersion.VersionString)"
Out-Line "cpu: $env:PROCESSOR_ARCHITECTURE"
Out-Line "node: $(& node --version 2>$null)"
Out-Line "npm: $(& npm --version 2>$null)"
Out-Line "npm prefix: $npmPrefix"
Out-Line "npm root: $npmRoot"
$before = Get-HomeFolders
Out-Line ''
Out-Line '## agent folders in the home folder after the installs'
foreach ($h in $before) {
  if ($h -match '\\\.?(claude|codex|cursor|cursor-agent|opencode|gemini|copilot|qwen|amp|crush|continue|factory|cline|kilo|augment|kimi-code|config|local)$') { Out-Line "  $h" }
}

foreach ($spec in $args) {
  $f = $spec -split '='
  $name = $f[0]
  $cmd = $f[1]
  $pkg = if ($f.Count -gt 2) { $f[2] } else { '' }
  Out-Line ''
  Out-Line "################ $name ($cmd)"
  $found = @(Get-Command $cmd -All -ErrorAction SilentlyContinue)
  if (-not $found) {
    Out-Line 'not installed'
    continue
  }
  Out-Line '## Get-Command'
  foreach ($c in $found) { Out-Line "  $($c.CommandType) $($c.Source)" }
  Out-Line '## --version'
  Out-Line (Run-Capped $env:ComSpec "/d /c $cmd --version")
  if ($pkg) {
    $dir = Join-Path $npmRoot $pkg
    $json = Join-Path $dir 'package.json'
    if (Test-Path -LiteralPath $json) {
      $v = (Get-Content -LiteralPath $json -Raw | ConvertFrom-Json).version
      Out-Line "## npm package $pkg, package.json version: $v"
    }
    Show-Tree $dir 3
    # The native binaries and the folders whose names hold a version.
    Out-Line '## binaries below the package'
    Get-ChildItem -LiteralPath $dir -Recurse -Force -Include '*.exe', '*.node' -ErrorAction SilentlyContinue |
      Select-Object -First 20 | ForEach-Object {
        # The parts with spaces, because the scrub reads a.b.c.d as an IPv4 address.
        $vi = $_.VersionInfo
        $fv = '{0} {1} {2} {3}' -f $vi.FileMajorPart, $vi.FileMinorPart, $vi.FileBuildPart, $vi.FilePrivatePart
        Out-Line "  $($_.FullName.Substring($dir.Length)) ($($_.Length) bytes, file version parts: $fv)"
      }
    Out-Line '## the npm shims'
    foreach ($ext in '', '.cmd', '.ps1') {
      $shim = Join-Path $npmPrefix ($cmd + $ext)
      if (Test-Path -LiteralPath $shim) {
        $target = Select-String -LiteralPath $shim -Pattern 'node_modules[\\/][^"'' ]+' -AllMatches |
          ForEach-Object { $_.Matches.Value } | Select-Object -Unique -First 2
        Out-Line "  $cmd$ext -> $($target -join ', ')"
      }
    }
  } else {
    foreach ($c in $found) {
      if ($c.Source -and (Test-Path -LiteralPath $c.Source)) {
        $dir = Split-Path -Parent $c.Source
        if ((Split-Path -Leaf $dir) -eq 'bin') { $dir = Split-Path -Parent $dir }
        Show-Tree $dir 3
        break
      }
    }
  }
}

Out-Line ''
Out-Line '## folders that the version calls made in the home folder'
foreach ($h in (Get-HomeFolders)) { if ($before -notcontains $h) { Out-Line "  $h" } }

$d = Get-ScrubDefaults
$r = Invoke-Scrub $sb.ToString() $d.HomeDir $d.User $d.HostName
[Console]::Out.Write($r.Text)
foreach ($k in $script:ScrubKinds) { Write-Output ('scrub: {0} {1}' -f $r.Counts[$k], $k) }
exit 0
