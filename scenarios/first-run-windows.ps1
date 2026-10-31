# Runs scenarios\first-run-windows.py for each agent, or prints the scrubbed
# summary of the runs. The scenarios workflow calls it on each Windows image.
#
# Run:  pwsh -NoProfile -File scenarios\first-run-windows.ps1 -Python PY NAME=CMD ...
#       pwsh -NoProfile -File scenarios\first-run-windows.ps1 -Summary
#   PY is the Python that has the pinned packages. NAME is the agent label,
#   CMD its command.
#
# The raw output of each run goes to out\run-<name>.txt and to
# out\first-run-<name>-<time>\. It does not go to the log. The summary prints
# it through tools\scrub.ps1, as the Linux summary does with tools/scrub.sh.
# A failure of one agent does not stop the other agents, and the script
# exits with 0.

[CmdletBinding(PositionalBinding = $false)]
param([string]$Python = 'python', [switch]$Summary, [int]$Limit = 180,
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$Agents)

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
New-Item -ItemType Directory -Force -Path (Join-Path $root 'out') | Out-Null

if (-not $Summary) {
  if (Test-Path -LiteralPath $Python) { $Python = (Resolve-Path -LiteralPath $Python).ProviderPath }
  foreach ($spec in $Agents) {
    $f = $spec -split '='
    $name = $f[0]
    $cmd = if ($f.Count -gt 1) { $f[1] } else { $f[0] }
    $log = Join-Path $root "out\run-$name.txt"
    $p = Start-Process -FilePath $Python -NoNewWindow -PassThru `
      -ArgumentList @((Join-Path $root 'scenarios\first-run-windows.py'), $name, $cmd) `
      -WorkingDirectory $root -RedirectStandardOutput $log -RedirectStandardError "$log.err"
    # The handle keeps the exit code readable after the process stops.
    $null = $p.Handle
    if (-not $p.WaitForExit($Limit * 1000)) {
      & taskkill /T /F /PID $p.Id 2>&1 | Out-Null
      "scenario: stopped after $Limit s" | Out-File -FilePath "$log.err" -Append -Encoding utf8
      Write-Output "stopped at the time limit: $name"
    } elseif ($p.ExitCode -eq 0) {
      Write-Output "ran: $name"
    } else {
      Write-Output "skipped or failed: $name"
    }
  }
  exit 0
}

. (Join-Path $root 'tools\scrub.ps1')
$d = Get-ScrubDefaults
function Show([string]$Text) {
  if (-not $Text) { return }
  [Console]::Out.Write((Invoke-Scrub $Text $d.HomeDir $d.User $d.HostName).Text)
  if (-not $Text.EndsWith("`n")) { [Console]::Out.WriteLine() }
}
function Read-Text([string]$Path) {
  if (Test-Path -LiteralPath $Path) { return [IO.File]::ReadAllText($Path) }
  return ''
}
# The path field of a .files line: "size mtime <sandbox>/home/...".
function Get-HomePaths([string]$Path) {
  foreach ($l in ((Read-Text $Path) -split "`n")) {
    $x = $l -split ' ', 3
    if ($x.Count -eq 3) { $x[2] -replace '^<sandbox>/home/', '' }
  }
}
function Show-Counts([string[]]$Paths, [int]$Parts, [int]$Top) {
  $c = @($Paths | Where-Object { $_ } | ForEach-Object { (($_ -split '/') | Select-Object -First $Parts) -join '/' } |
      Group-Object | Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, Name |
      Select-Object -First $Top | ForEach-Object { '{0,7} {1}' -f $_.Count, $_.Name })
  Show (($c -join "`n") + "`n")
}

foreach ($f in (Get-ChildItem (Join-Path $root 'out\run-*.txt') -ErrorAction SilentlyContinue | Sort-Object Name)) {
  Write-Output "== $($f.BaseName)"
  $t = @((Read-Text $f.FullName) -split "`r?`n" | Where-Object { $_ -and $_ -notmatch '^output: ' }) | Select-Object -Last 3
  $e = @((Read-Text "$($f.FullName).err") -split "`r?`n" | Where-Object { $_ }) | Select-Object -Last 5
  Show ((@($t) + @($e)) -join "`n")
}
foreach ($o in (Get-ChildItem (Join-Path $root 'out') -Directory -Filter 'first-run-*' -ErrorAction SilentlyContinue | Sort-Object Name)) {
  Write-Output ('################ ' + ($o.Name -replace '-[0-9T]*Z$', ''))
  $p = $o.FullName
  Show (Read-Text "$p\log.txt")
  Write-Output '--- screen after 20 s'
  $s = @((Read-Text "$p\02-after-20s.screen") -split "`n" | Where-Object { $_.Trim() }) | Select-Object -First 30
  Show ($s -join "`n")
  Write-Output '--- processes (pid ppid name command)'
  Show (Read-Text "$p\02-after-20s.ps")
  Write-Output '--- top folders made in the throwaway home'
  Show-Counts @(Get-HomePaths "$p\02-after-20s.files") 2 15
  Write-Output '--- changes in the real profile folders'
  $c = @((Read-Text "$p\02-after-20s.outside") -split "`n" | Where-Object { $_ }) | Select-Object -First 30
  Show ($c -join "`n")
  Write-Output '--- open files below the throwaway home'
  $of = @((Read-Text "$p\02-after-20s.open") -split "`n" | Where-Object { $_ -match '<sandbox>[\\/]home' } |
      ForEach-Object { ($_ -split ' ', 2)[1] -replace '^<sandbox>[\\/]home[\\/]', '' } | Sort-Object -Unique | Select-Object -First 30)
  Show ($of -join "`n")
  Write-Output '--- folders made in the throwaway home (files in each)'
  Show-Counts @(Get-HomePaths "$p\02-after-20s.files") 3 40
}
exit 0
