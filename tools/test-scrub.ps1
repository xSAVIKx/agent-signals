# Test tools\scrub.ps1 on the fixture in tools\testdata\scrub.
# It runs the scrub in a new PowerShell process with fixed values for the
# home folder, the account name and the host name, and compares the bytes
# of the output with expected.txt.
# Usage: powershell -NoProfile -File tools\test-scrub.ps1
# Exit status: 0 when the output is the same, 1 when it is different.

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$scrub = Join-Path $here 'scrub.ps1'
$inputFile = Join-Path $here 'testdata/scrub/input.txt'
$expectedFile = Join-Path $here 'testdata/scrub/expected.txt'

$info = New-Object System.Diagnostics.ProcessStartInfo
$info.FileName = (Get-Process -Id $PID).Path
$info.Arguments = '-NoProfile -NonInteractive -File "' + $scrub + '" -Path "' + $inputFile + '"'
$info.UseShellExecute = $false
$info.RedirectStandardOutput = $true
$info.RedirectStandardError = $true
$info.EnvironmentVariables['SCRUB_HOME'] = '/Users/alice'
$info.EnvironmentVariables['SCRUB_USER'] = 'alice'
$info.EnvironmentVariables['SCRUB_HOST'] = 'alice-mbp.local'

$p = [System.Diagnostics.Process]::Start($info)
$err = $p.StandardError.ReadToEndAsync()
$ms = New-Object System.IO.MemoryStream
$p.StandardOutput.BaseStream.CopyTo($ms)
$p.WaitForExit()
$actual = $ms.ToArray()
$expected = [IO.File]::ReadAllBytes($expectedFile)

foreach ($l in ($err.Result -split "`r?`n")) { if ($l) { Write-Output $l } }

$same = ($actual.Length -eq $expected.Length)
if ($same) {
  for ($i = 0; $i -lt $actual.Length; $i++) {
    if ($actual[$i] -ne $expected[$i]) { $same = $false; break }
  }
}

if ($p.ExitCode -ne 0) {
  Write-Output "FAIL: scrub.ps1 exit status $($p.ExitCode)"
  exit 1
}
if (-not $same) {
  $utf8 = New-Object System.Text.UTF8Encoding $false
  Write-Output 'FAIL: the output is different from expected.txt'
  Write-Output '--- expected'
  Write-Output $utf8.GetString($expected)
  Write-Output '--- actual'
  Write-Output $utf8.GetString($actual)
  exit 1
}
Write-Output 'ok: the scrub output is the same as expected.txt'
exit 0
