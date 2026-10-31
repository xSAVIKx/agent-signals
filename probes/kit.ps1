# One-line start of the probe kit on Windows, in PowerShell:
#
#   irm https://xsavikx.github.io/agent-signals/kit.ps1 | iex
#
# To give arguments to probes\run.ps1, for example -All:
#
#   & ([scriptblock]::Create((irm https://xsavikx.github.io/agent-signals/kit.ps1))) -All
#
# It downloads the repository archive to a temporary folder, runs
# probes\run.ps1 in a new PowerShell process with the execution policy
# Bypass, and deletes the folder. The kit writes its file in the current
# folder.
#
# The environment can change the source:
#   AGENT_SIGNALS_REF  a branch or a tag (default: main)
#   AGENT_SIGNALS_URL  the URL of a .zip archive, or a path to a local .zip

& {
  param([switch]$All)
  $ErrorActionPreference = 'Stop'
  $ref = if ($env:AGENT_SIGNALS_REF) { $env:AGENT_SIGNALS_REF } else { 'main' }
  $url = if ($env:AGENT_SIGNALS_URL) { $env:AGENT_SIGNALS_URL } else { "https://codeload.github.com/xSAVIKx/agent-signals/zip/$ref" }
  $tmp = Join-Path ([IO.Path]::GetTempPath()) ('agent-signals-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $tmp | Out-Null
  try {
    $zip = Join-Path $tmp 'kit.zip'
    Write-Host "kit: download $url"
    if ($url -match '^https?://') {
      [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
      Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $zip
    } else {
      Copy-Item -LiteralPath $url -Destination $zip
    }
    Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $tmp 'src')
    $run = Get-ChildItem -Path (Join-Path $tmp 'src') -Filter 'run.ps1' -Recurse |
      Where-Object { $_.Directory.Name -eq 'probes' } | Select-Object -First 1
    if (-not $run) { throw 'kit: no probes\run.ps1 in the archive' }
    $exe = (Get-Process -Id $PID).Path
    $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $run.FullName)
    if ($All) { $argv += '-All' }
    & $exe @argv
  } finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
  }
} @args
