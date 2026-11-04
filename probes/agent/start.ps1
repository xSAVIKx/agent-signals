# kit start on Windows: make a new run folder.
#
#   kit start [--home real|throwaway] [--out DIR] [--python PATH]
#
# --python names the Python with pywinpty, pyte and psutil for the conpty
# backend (for example the venv of the scenarios). The run keeps it in
# .kit\python, which is not in the archive.
#
# It makes DIR\agent-signals-run-windows-<time>\ (DIR: the current folder
# by default), gives only this account and SYSTEM access to it, and writes
# its path to DIR\.agent-signals-run. The later commands find the run from
# that file in the current folder, or from AGENT_SIGNALS_RUN.
# It refuses (exit 2) a DIR in a git work tree, in ~\.claude, ~\.codex,
# ~\.gemini or ~\.cursor, a DIR that belongs to another account, and a DIR
# that Everyone, Users, Authenticated Users, Guests or Anonymous can write.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')
# The arguments as strings (see Get-KitArgs in lib.ps1).
[string[]]$argv = @(Get-KitArgs $args)

$homeMode = 'real'
$python = ''
$out = (Get-Location).ProviderPath
for ($i = 0; $i -lt $argv.Count; $i++) {
    $a = [string]$argv[$i]
    if ($a -eq '--home' -and $i + 1 -lt $argv.Count) { $homeMode = [string]$argv[++$i] }
    elseif ($a -eq '--out' -and $i + 1 -lt $argv.Count) { $out = [string]$argv[++$i] }
    elseif ($a -eq '--python' -and $i + 1 -lt $argv.Count) { $python = [string]$argv[++$i] }
    else { Stop-Kit 2 'usage: kit start [--home real|throwaway] [--out DIR] [--python PATH]' }
}
if ($homeMode -cnotin 'real', 'throwaway') { Stop-Kit 2 "unknown home mode: $homeMode" }
if ($python) {
    if (-not (Test-Path -LiteralPath $python -PathType Leaf)) { Stop-Kit 2 "no such Python: $python" }
    $python = (Resolve-Path -LiteralPath $python).ProviderPath
}

function Stop-Place([string]$Dir, [string[]]$Why) {
    foreach ($w in $Why) { [Console]::Error.WriteLine("start: $w") }
    if (@($Why | Where-Object { $_ -match 'can write|belongs to' }).Count -gt 0) {
        [Console]::Error.WriteLine('start: to give only this account and SYSTEM access to the folder, run:')
        [Console]::Error.WriteLine('  ' + (Get-KitPrivateCommand $Dir))
    }
    Stop-Kit 2 'the folder is not a safe place for a run'
}

# A new DIR: check the place first, then make DIR private. An existing DIR
# keeps its access list, and the check names what is wrong.
if (-not (Test-Path -LiteralPath $out -PathType Container)) {
    $full = [IO.Path]::GetFullPath($out)
    $why = @(Test-KitPlace $full)
    if ($why.Count -gt 0) { Stop-Place $full $why }
    New-Item -ItemType Directory -Force -Path $full | Out-Null
    if ((Set-KitPrivate $full) -ne 0) { Stop-Kit 1 'icacls did not set the access list of the folder' }
}
$out = (Resolve-Path -LiteralPath $out).ProviderPath
$why = @(Test-KitPlace $out)
if ($why.Count -gt 0) { Stop-Place $out $why }

$time = Get-KitTime
$run = Join-Path $out "agent-signals-run-windows-$time"
if (Test-Path -LiteralPath $run) { Stop-Kit 1 "the run folder exists: $run" }
New-Item -ItemType Directory -Path $run | Out-Null
if ((Set-KitPrivate $run) -ne 0) { Stop-Kit 1 'icacls did not set the access list of the run folder' }
New-Item -ItemType Directory -Path (Join-Path $run 'pids') | Out-Null

Add-KitManifest $run @('meta', 'kit', (Get-KitVersion))
Add-KitManifest $run @('meta', 'os', 'windows')
Add-KitManifest $run @('meta', 'home', $homeMode)
Add-KitManifest $run @('meta', 'start', $time)
# The path of the Python can hold the home folder, so it goes to
# .kit\python, which the archive does not hold.
if ($python) {
    New-Item -ItemType Directory -Path (Join-Path $run '.kit') | Out-Null
    Write-KitText (Join-Path $run '.kit\python') ($python + "`n")
}
# The pointer goes to DIR and to the kit root, as kit_run_dir of lib.sh
# reads it, so that a command in a new shell in another folder finds the
# run.
Write-KitText (Join-Path $out '.agent-signals-run') ($run + "`n")
try { Write-KitText (Join-Path $script:KitRoot '.agent-signals-run') ($run + "`n") } catch { }
Write-Output "run: $run"
exit 0
