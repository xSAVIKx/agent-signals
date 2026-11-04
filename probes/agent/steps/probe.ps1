# The step kind "probe" on Windows: the full probe kit, probes\run.ps1.
# kit step runs this script with the KIT_* variables of the step contract.
# It runs the probe of each installed agent, and moves the file of the
# kit to KIT_OUT. kit step scrubs it again into the step file.
# Needs: nothing. Cost: none. It starts no agent session and types
# nothing.
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib.ps1')

$run = $env:KIT_RUN
$out = $env:KIT_OUT
if (-not $run -or -not $out) { Stop-Kit 2 'run this script with kit step' }
$work = Join-Path (Split-Path -Parent $out) ('probe-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null

# The terminal question of macOS has no Windows form. The variable is set
# for the same contract as probe.sh.
$env:AGENT_SIGNALS_TERMINALS = 'no'
$exe = (Get-Process -Id $PID).Path
$runPs1 = Join-Path $script:KitRoot 'probes\run.ps1'
$argText = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' + (Format-KitArg $runPs1)
$p = Start-KitProcess $run 'probe' $exe $argText (Join-Path $work 'stdout') (Join-Path $work 'stderr') $work
$code = Wait-KitProcess $run $p 1500

$files = @(Get-ChildItem -LiteralPath $work -Filter 'agent-signals-probe-windows-*.txt' -File)
$rc = 0
if ($files.Count -eq 1 -and $code -eq 0) {
    Write-KitText $out (Read-KitText $files[0].FullName)
} else {
    $rc = 1
    if ($code -eq -1) { $why = 'time-limit' } elseif ($files.Count -eq 0) { $why = 'no-file' } else { $why = "exit-$code" }
    Write-KitText "$out.reason" "$why`n"
    $text = ''
    foreach ($f in $files) { $text += Read-KitText $f.FullName }
    $text += "### probe output`n" + (Read-KitText (Join-Path $work 'stdout')) + (Read-KitText (Join-Path $work 'stderr'))
    Write-KitText $out $text
}
Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
exit $rc
