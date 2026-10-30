# The probe kit for Windows.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File probes\run.ps1 [-All]
#
# The kit runs each probes\<agent>\windows.ps1 whose agent command it finds.
# With -All, it runs all probes. It sends the output through
# tools\scrub.ps1 and writes one file in the current folder:
# agent-signals-probe-windows-<yyyyMMdd-HHmmss>.txt.
#
# The probes only read. They start no agent, type nothing, and read no
# conversation text. The scrub removes names, but it cannot find all of
# them. Read the file before you send it.

param([switch]$All)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'tools\scrub.ps1')

# The commands that show that an agent is installed.
$commands = @{
  'claude'   = @('claude')
  'codex'    = @('codex')
  'agy'      = @('agy')
  'cursor'   = @('agent', 'cursor-agent')
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
  $out = $p.StandardOutput.ReadToEndAsync()
  $err = $p.StandardError.ReadToEndAsync()
  if (-not $p.WaitForExit(600000)) {
    try { $p.Kill() } catch { }
    [void]$sb.AppendLine('kit: the probe did not stop in 600 s')
  }
  [void]$out.Wait(5000)
  [void]$err.Wait(5000)
  [void]$sb.Append($out.Result)
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
