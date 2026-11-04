# The one-line start on Windows keeps the kit with AGENT_SIGNALS_GET.
. (Join-Path $env:ROOT 'tools/agent-kit-tests/lib.ps1')

# The kit archive, as the release makes it.
$stage = Join-Path $T 'stage/agent-signals-kit'
New-Item -ItemType Directory -Path (Join-Path $stage 'tools') | Out-Null
Copy-Item -Recurse -LiteralPath (Join-Path $env:ROOT 'probes') -Destination (Join-Path $stage 'probes')
Copy-Item -LiteralPath (Join-Path $env:ROOT 'tools/scrub.ps1') -Destination (Join-Path $stage 'tools')
$zip = Join-Path $T 'kit.zip'
Compress-Archive -Path $stage -DestinationPath $zip

$kitPs1 = Join-Path $env:ROOT 'probes/kit.ps1'
$out = Join-Path $T 'out'
# Get-Kit DIR: run the one-line start as a file with AGENT_SIGNALS_GET=DIR.
function Get-Kit([string]$Dir) {
    $env:AGENT_SIGNALS_URL = $zip
    $env:AGENT_SIGNALS_GET = $Dir
    # The kit writes a probe file in the current folder, so the test runs
    # it in $T.
    Push-Location -LiteralPath $T
    try {
        & $script:Exe -NoProfile -ExecutionPolicy Bypass -File $kitPs1 *> $out
        return $LASTEXITCODE
    } finally {
        Pop-Location
        Remove-Item Env:AGENT_SIGNALS_URL, Env:AGENT_SIGNALS_GET -ErrorAction SilentlyContinue
    }
}

$k = Join-Path $T 'k'
Expect-Code 'get exits 0' 0 (Get-Kit $k)
$want = Join-Path $k 'agent-signals-kit'
if (Test-Path -LiteralPath (Join-Path $want 'probes/run.ps1')) { Pass 'get keeps the kit' } else { Fail 'get keeps the kit' "no $want\probes\run.ps1" }
$last = (Get-Content -LiteralPath $out | Select-Object -Last 1)
if ($last -eq "kit: ready $want") { Pass 'get prints the folder' } else { Fail 'get prints the folder' "last line: $last" }
if (Get-ChildItem -Path $T -Filter 'agent-signals-probe-*' -Recurse) { Fail 'get runs no probe' 'a probe file exists' } else { Pass 'get runs no probe' }
Expect-Code 'get does not overwrite a kit' 2 (Get-Kit $k)
Expect-Line 'get names the folder that exists' 'already exists' $out

Complete-Tests
