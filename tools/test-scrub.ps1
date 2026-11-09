# Test tools\scrub.ps1 on the fixtures in tools\testdata\scrub: input.txt
# (LF line ends) and crlf-input.txt (CRLF line ends).
# It runs the scrub in a new PowerShell process with fixed values for the
# home folder, the account name and the host name, and compares the bytes
# of the output with expected.txt and crlf-expected.txt.
# Usage: powershell -NoProfile -File tools\test-scrub.ps1
# Exit status: 0 when each output is the same, 1 when one is different.

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$scrub = Join-Path $here 'scrub.ps1'
$fail = $false

foreach ($pair in @(@('input.txt', 'expected.txt'), @('crlf-input.txt', 'crlf-expected.txt'))) {
  $inputFile = Join-Path $here ('testdata/scrub/' + $pair[0])
  $expectedFile = Join-Path $here ('testdata/scrub/' + $pair[1])

  $info = New-Object System.Diagnostics.ProcessStartInfo
  $info.FileName = (Get-Process -Id $PID).Path
  $info.Arguments = '-NoProfile -NonInteractive -File "' + $scrub + '" -Path "' + $inputFile + '"'
  $info.UseShellExecute = $false
  $info.RedirectStandardOutput = $true
  $info.RedirectStandardError = $true
  $info.EnvironmentVariables['SCRUB_HOME'] = '/Users/alice'
  $info.EnvironmentVariables['SCRUB_USER'] = 'alice'
  $info.EnvironmentVariables['SCRUB_HOST'] = 'alice-mbp.local'
  $info.EnvironmentVariables['SCRUB_EXTRA'] = "/opt/kit runs`n/var/tmp/agent-signals-run-linux-20260101T000000Z`nC:\Users\alice\Box - Fabrikam Org`nC:\Windows\Private"
  $info.EnvironmentVariables['SCRUB_DOMAIN'] = 'CONTOSO'
  $info.EnvironmentVariables['OneDrive'] = 'C:\Users\alice\OneDrive - Contoso'
  foreach ($k in @('OneDriveCommercial', 'OneDriveConsumer')) {
    if ($info.EnvironmentVariables.ContainsKey($k)) { $info.EnvironmentVariables.Remove($k) }
  }

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
    Write-Output "FAIL: $($pair[0]): scrub.ps1 exit status $($p.ExitCode)"
    $fail = $true
    continue
  }
  if (-not $same) {
    $utf8 = New-Object System.Text.UTF8Encoding $false
    Write-Output "FAIL: $($pair[0]): the output is different from $($pair[1])"
    Write-Output '--- expected'
    Write-Output $utf8.GetString($expected)
    Write-Output '--- actual'
    Write-Output $utf8.GetString($actual)
    $fail = $true
    continue
  }
  Write-Output "ok: the scrub output of $($pair[0]) is the same as $($pair[1])"
}
if ($fail) { exit 1 }
exit 0
