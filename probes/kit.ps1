# One-line start of the probe kit on Windows, in PowerShell:
#
#   irm https://xsavikx.github.io/agent-signals/kit.ps1 | iex
#
# To give arguments to probes\run.ps1, for example -All:
#
#   & ([scriptblock]::Create((irm https://xsavikx.github.io/agent-signals/kit.ps1))) -All
#
# It downloads the kit of the latest release (agent-signals-kit.zip) to a
# temporary folder, runs probes\run.ps1 in a new PowerShell process with the
# execution policy Bypass, and deletes the folder. The kit writes its file
# in the current folder. When the release has no kit file, it downloads the
# repository archive of main.
#
# The environment can change the source:
#   AGENT_SIGNALS_REF  a branch or a tag; the kit then comes from the
#                      repository archive of that ref
#   AGENT_SIGNALS_URL  the URL of a .zip archive, or a path to a local .zip

& {
  param([switch]$All)
  $ErrorActionPreference = 'Stop'
  if ($env:AGENT_SIGNALS_URL) {
    $urls = @($env:AGENT_SIGNALS_URL)
  } elseif ($env:AGENT_SIGNALS_REF) {
    $urls = @("https://codeload.github.com/xSAVIKx/agent-signals/zip/$($env:AGENT_SIGNALS_REF)")
  } else {
    $urls = @('https://github.com/xSAVIKx/agent-signals/releases/latest/download/agent-signals-kit.zip',
      'https://codeload.github.com/xSAVIKx/agent-signals/zip/main')
  }
  $tmp = Join-Path ([IO.Path]::GetTempPath()) ('agent-signals-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $tmp | Out-Null
  try {
    $zip = Join-Path $tmp 'kit.zip'
    $got = $null
    foreach ($url in $urls) {
      Write-Host "kit: download $url"
      try {
        if ($url -match '^https?://') {
          [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
          Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $zip
        } else {
          Copy-Item -LiteralPath $url -Destination $zip
        }
        $got = $url
        break
      } catch {
        Write-Host "kit: $url failed"
      }
    }
    if (-not $got) { throw 'kit: the download failed' }
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
