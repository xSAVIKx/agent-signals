# kit edit on Windows: record a change that a person or an agent made by
# hand in a file of the run, for example a name that the scrub missed.
#
#   kit edit FILE REASON...
#
# FILE is a file of the run folder, as a name in the run folder or as a
# path. It appends one line to manifest.tsv:
#   edit <file> <reason> <new sha256>
# and prints "edit: <file> <sha256>".
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')
# kit.ps1 can pass one $null for no arguments.
$argv = @($args | Where-Object { $null -ne $_ })

if ($argv.Count -lt 2) { Stop-Kit 2 'usage: kit edit FILE REASON...' }
$run = Get-KitRunDir
$runFull = [IO.Path]::GetFullPath($run).TrimEnd('\', '/')
$f = [string]$argv[0]
$reason = (@($argv[1..($argv.Count - 1)] | ForEach-Object { [string]$_ }) -join ' ').Trim()
if (-not $reason) { Stop-Kit 2 'the reason is empty' }

$cand = $f
if (-not [IO.Path]::IsPathRooted($f)) {
    if (Test-Path -LiteralPath (Join-Path $run $f) -PathType Leaf) { $cand = Join-Path $run $f }
}
if (-not (Test-Path -LiteralPath $cand -PathType Leaf)) { Stop-Kit 2 "no such file in the run: $f" }
$full = (Resolve-Path -LiteralPath $cand).ProviderPath
if (-not $full.StartsWith($runFull + '\', [StringComparison]::OrdinalIgnoreCase)) { Stop-Kit 2 "the file is not in the run folder: $f" }
$rel = $full.Substring($runFull.Length + 1).Replace('\', '/')
if ($rel -in 'manifest.tsv', 'manifest.json', 'summary.txt' -or $rel -match '^(pids|sessions|\.kit|\.raw)/') {
    Stop-Kit 2 "the kit owns this file: $rel"
}
$sha = Get-KitSha256 $full
Add-KitManifest $run @('edit', $rel, $reason, $sha)
Write-Output "edit: $rel $sha"
exit 0
