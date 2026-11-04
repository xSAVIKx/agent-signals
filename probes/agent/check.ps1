# kit check on Windows: prove that the run is complete and that the scrub
# ran. It is the only pass or fail command of the kit.
#
#   kit check
#
# It fails (exit 1, one "check: <reason>" line for each failure) when:
#   - a step line of manifest.tsv has no file;
#   - a file has a SHA-256 that is not the one of its last step or edit
#     line, or a file is not in the manifest;
#   - a file of the kit (.raw\) is left from a stopped step;
#   - a file holds the home folder, the account name, the host name, or
#     the value of an environment variable *_API_KEY or *_TOKEN. The kit
#     reads these raw values now and writes them nowhere;
#   - a probe section of a probe file is missing, as
#     tools/check-probe-output.sh checks it;
#   - a pid of pids\ still runs;
#   - the run folder or its parent folder is not a safe place (kit start).
# Else it writes manifest.json, summary.txt and the archive
# agent-signals-run-windows-<time>.zip next to the run folder, and prints:
#   check: ok
#   run: <run folder>
#   archive: <zip file>
# The archive does not hold pids\, sessions\, .kit\ or .raw\.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')
if ($args.Count -gt 0) { Stop-Kit 2 'usage: kit check' }

$run = (Resolve-Path -LiteralPath (Get-KitRunDir)).ProviderPath.TrimEnd('\', '/')
$fails = New-Object System.Collections.ArrayList
function Add-Fail([string]$Text) { [void]$fails.Add("check: $Text") }

$lines = @(Read-KitManifest $run)
$want = @{}
$steps = @()
$edits = @()
foreach ($f in $lines) {
    if ($f[0] -eq 'step' -and $f.Count -ge 8) {
        $steps += , $f
        $want[$f[6]] = $f[7]
        if (-not (Test-Path -LiteralPath (Join-Path $run $f[6]) -PathType Leaf)) { Add-Fail "no file for the step $($f[1])@$($f[2]): $($f[6])" }
    } elseif ($f[0] -eq 'edit' -and $f.Count -ge 4) {
        $edits += , $f
        $want[$f[1]] = $f[3]
    }
}

# The files of the run.
$content = @()
foreach ($i in @(Get-ChildItem -LiteralPath $run -Recurse -File -Force)) {
    $rel = $i.FullName.Substring($run.Length + 1).Replace('\', '/')
    if ($rel -match '^(pids|sessions|\.kit)/' -or $rel -in 'manifest.json', 'summary.txt') { continue }
    if ($rel -match '^\.raw/') { Add-Fail "a raw file of a stopped step is left: $rel"; continue }
    if ($rel -eq 'manifest.tsv') { $content += $i.FullName; continue }
    $content += $i.FullName
    if (-not $want.ContainsKey($rel)) { Add-Fail "the file is not in the manifest: $rel"; continue }
    if ((Get-KitSha256 $i.FullName) -ne $want[$rel]) { Add-Fail "the file changed with no 'kit edit' line: $rel" }
}

# The raw values. They stay in memory.
$raw = @()
foreach ($h in @(Get-KitHomes)) {
    $t = $h.TrimEnd('/', '\')
    if ($t.Length -lt 3) { continue }
    $parts = @($t -split '[\\/]+' | ForEach-Object { [regex]::Escape($_) })
    $raw += New-Object PSObject -Property @{ Kind = 'the home folder'; Pattern = '(?i)' + ($parts -join '[\\/]+') }
}
$d = Get-ScrubDefaults
if ($d.User -and $d.User -ne 'dev') {
    $raw += New-Object PSObject -Property @{ Kind = 'the account name'; Pattern = '(?i)' + (Get-WordPattern $d.User) }
}
$hosts = @($d.HostName, $env:COMPUTERNAME)
if ($d.HostName) { $hosts += $d.HostName.Split('.')[0] }
foreach ($n in @($hosts | Where-Object { $_ -and $_ -ne 'host' } | Select-Object -Unique)) {
    $raw += New-Object PSObject -Property @{ Kind = 'the host name'; Pattern = '(?i)' + (Get-WordPattern $n) }
}
foreach ($e in @(Get-ChildItem env: | Where-Object { $_.Name -match '(?i)(_API_KEY|_TOKEN)$' -and ([string]$_.Value).Length -ge 8 })) {
    $raw += New-Object PSObject -Property @{ Kind = "the value of $($e.Name)"; Pattern = [regex]::Escape([string]$e.Value) }
}
foreach ($c in $content) {
    $text = Read-KitText $c
    $flat = $text -replace "`r?`n", ''
    $rel = $c.Substring($run.Length + 1).Replace('\', '/')
    foreach ($r in $raw) {
        if ($text -match $r.Pattern -or $flat -match $r.Pattern) { Add-Fail "$rel holds $($r.Kind)" }
    }
}

# The probe files: each probe block has all its sections, as
# tools/check-probe-output.sh checks one probe.
foreach ($s in $steps) {
    $file = Join-Path $run $s[6]
    if ($s[1] -ne 'probe' -or -not (Test-Path -LiteralPath $file)) { continue }
    $blocks = [regex]::Split((Read-KitText $file), '(?m)^(?===== probe )')
    foreach ($b in $blocks) {
        $m = [regex]::Match($b, '^==== probe ([a-z0-9-]+)/windows\.ps1\r?$', 'Multiline')
        if (-not $m.Success) { continue }
        $probe = Join-Path $script:KitRoot ("probes\{0}\windows.ps1" -f $m.Groups[1].Value)
        $src = Read-KitText $probe
        $n = [regex]::Matches($src, '(?m)^[ \t]*(Section|Invoke-Section) ["'']').Count
        if ($src -match '(?m)^[ \t]*Header ') { $n++ }
        $got = [regex]::Matches($b, '(?m)^### [0-9]+\. ').Count
        $who = "$($s[6]): $($m.Groups[1].Value)/windows.ps1"
        if ($got -ne $n) { Add-Fail "${who}: $got sections, want $n" }
        for ($k = 1; $k -le $n; $k++) {
            if ($b -notmatch "(?m)^### $k\. ") { Add-Fail "${who}: no section $k" }
        }
        foreach ($k in 'os', 'cpu') {
            if ($b -notmatch "(?m)^${k}: ") { Add-Fail "${who}: no `"${k}:`" line" }
        }
    }
}

# The pids of the run.
$pd = Join-Path $run 'pids'
foreach ($p in @(Get-ChildItem -LiteralPath $pd -File -ErrorAction SilentlyContinue)) {
    if ($p.Name -match '^[0-9]+$' -and (Test-KitPidOurs $run ([int]$p.Name))) {
        $label = (([string](Get-Content -LiteralPath $p.FullName -TotalCount 1)) -split "`t")[0]
        Add-Fail "the pid $($p.Name) of the run still runs ($label)"
    }
}

# The place, again before the archive.
$parent = Split-Path -Parent $run
foreach ($w in @(Test-KitPlace $parent)) { Add-Fail "the parent folder: $w" }
foreach ($w in @(Test-KitPlace $run) | Where-Object { $_ -notmatch 'belongs to another account' }) { Add-Fail "the run folder: $w" }

if ($fails.Count -gt 0) {
    foreach ($l in $fails) { Write-Output $l }
    exit 1
}

# manifest.json and summary.txt.
$os = Get-KitOsInfo
$homeMode = Get-KitMeta $run 'home'
if (-not $homeMode) { $homeMode = 'real' }
$start = Get-KitMeta $run 'start'
$end = Get-KitTime
$orch = 'unknown'
$dm = [regex]::Match((Read-KitText (Join-Path $run '00-doctor.txt')), '(?m)^orchestrator: (\S+)')
if ($dm.Success) { $orch = $dm.Groups[1].Value }
$version = Get-KitMeta $run 'kit'
if (-not $version) { $version = Get-KitVersion }

$sl = @()
foreach ($s in $steps) {
    $sl += New-Object PSObject -Property ([ordered]@{ name = $s[1]; backend = $s[2]; result = $s[3]; start = $s[4]; end = $s[5]; file = $s[6]; sha256 = $s[7] })
}
$el = @()
foreach ($e in $edits) {
    $el += New-Object PSObject -Property ([ordered]@{ file = $e[1]; reason = $e[2]; sha256 = $e[3] })
}
$j = [ordered]@{
    kit = $version; os = $os.Os; cpu = $os.Cpu; os_version = $os.Version; home = $homeMode
    start = $start; end = $end; orchestrator = $orch; steps = $sl; edits = $el
}
Write-KitText (Join-Path $run 'manifest.json') ((ConvertTo-Json -InputObject $j -Depth 5) + "`n")

$sum = New-Object System.Text.StringBuilder
[void]$sum.AppendLine("kit $version on $($os.Os) ($($os.Cpu)), $($os.Version). Run from $start to $end ($homeMode).")
foreach ($s in $steps) { [void]$sum.AppendLine("step: $($s[1])@$($s[2]) $($s[3])") }
foreach ($e in $edits) { [void]$sum.AppendLine("edit: $($e[1]) $($e[2])") }
Write-KitText (Join-Path $run 'summary.txt') ($sum.ToString() -replace "`r`n", "`n")

# The archive.
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$name = Split-Path -Leaf $run
$zipPath = Join-Path $parent "$name.zip"
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
$zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($i in @(Get-ChildItem -LiteralPath $run -Recurse -File -Force)) {
        $rel = $i.FullName.Substring($run.Length + 1).Replace('\', '/')
        if ($rel -match '^(pids|sessions|\.kit|\.raw)/') { continue }
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $i.FullName, "$name/$rel")
    }
} finally {
    $zip.Dispose()
}
Write-Output 'check: ok'
Write-Output "run: $run"
Write-Output "archive: $zipPath"
exit 0
