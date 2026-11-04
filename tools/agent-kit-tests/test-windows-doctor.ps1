# kit doctor on Windows: versions from the install paths, no agent runs,
# and the orchestrator from the parent processes.
. (Join-Path $env:ROOT 'tools/agent-kit-tests/lib.ps1')
$out = Join-Path $T 'out'
function Expect-NoLine([string]$Name, [string]$Pattern, [string]$File) {
    if (Select-String -LiteralPath $File -Pattern $Pattern -Quiet) { Fail $Name "a line matches: $Pattern" } else { Pass $Name }
}
function New-TextFile([string]$File, [string]$Text) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $File) | Out-Null
    [IO.File]::WriteAllText($File, $Text)
}

# A fake home with installs. The doctor must read the versions from the
# paths and run nothing.
$h = Join-Path $T 'home'
$la = Join-Path $h 'AppData\Local'
New-TextFile (Join-Path $h '.local\bin\claude.exe') 'abcdefg'
New-TextFile (Join-Path $h '.local\bin\claude.exe.old.1730000000000.4242') 'abc'
New-TextFile (Join-Path $h '.local\share\claude\versions\2.1.316') 'gfedcba'
New-TextFile (Join-Path $h '.local\share\claude\versions\2.1.315') 'abcdefghij'
New-TextFile (Join-Path $la 'cursor-agent\cursor-agent.cmd') "@echo off`r`necho ran> `"%~dp0ran-cursor`"`r`n"
New-Item -ItemType Directory -Force -Path (Join-Path $la 'cursor-agent\versions\2026.10.22-27dcf5f') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $la 'cursor-agent\versions\2026.9.30-abc1234') | Out-Null
New-TextFile (Join-Path $la 'agy\bin\agy.exe.1a2b3c.old') 'old'
$npm = Join-Path $T 'npm'
New-TextFile (Join-Path $npm 'codex.cmd') "@echo off`r`necho ran> `"%~dp0ran-codex`"`r`necho codex-cli 0.166.0`r`n"
New-TextFile (Join-Path $npm 'node_modules\@openai\codex\package.json') '{ "name": "@openai/codex", "version": "0.166.0" }'
New-TextFile (Join-Path $npm 'gemini.cmd') "@echo off`r`necho ran> `"%~dp0ran-gemini`"`r`n"

$env:USERPROFILE = $h
$env:LOCALAPPDATA = $la
$env:APPDATA = Join-Path $h 'AppData\Roaming'
$env:PATH = "$npm;$env:SystemRoot\System32;$env:SystemRoot;$env:SystemRoot\System32\WindowsPowerShell\v1.0"
Remove-Item Env:\AGENT_SIGNALS_RUN -ErrorAction SilentlyContinue

Expect-Code 'doctor exits 0' 0 (Invoke-Kit 'doctor')
Expect-Line 'the first line is the kit version' '^kit: ' $out
Expect-Line 'os is windows' '^os: windows$' $out
Expect-Line 'cpu' '^cpu: (x86_64|arm64)$' $out
Expect-Line 'the shell' '^shell: powershell [0-9]' $out
Expect-Line 'a tool line' '^tool: git ' $out
Expect-Line 'the conpty tool line' '^tool: conpty ' $out
Expect-Line 'claude from the size of a versions file' '^agent: claude ~[\\/]\.local[\\/]bin[\\/]claude\.exe 2\.1\.316$' $out
Expect-Line 'cursor from the newest versions folder' '^agent: cursor ~[\\/]AppData[\\/]Local[\\/]cursor-agent[\\/]cursor-agent\.cmd 2026\.10\.22-27dcf5f$' $out
Expect-Line 'codex from package.json' '^agent: codex \S+codex\.cmd 0\.166\.0$' $out
Expect-Line 'gemini with no version' '^agent: gemini \S+gemini\.cmd unknown$' $out
Expect-Line 'a renamed agy is not an install' '^agent: agy missing$' $out
Expect-Line 'no orchestrator' '^orchestrator: unknown -$' $out
Expect-Line 'the terminal line' '^orchestrator_terminal: ' $out
Expect-NoLine 'no raw home folder' ([regex]::Escape($h)) $out
$ran = @(Get-ChildItem -Path $T -Recurse -Filter 'ran-*' -File)
if ($ran.Count -eq 0) { Pass 'the doctor runs no agent' } else { Fail 'the doctor runs no agent' "$($ran.Count) marker files" }

# The orchestrator: the doctor runs as a child of a process named
# claude.exe (a copy of cmd.exe).
$orch = Join-Path $T 'orch'
New-Item -ItemType Directory -Path $orch | Out-Null
Copy-Item -LiteralPath (Join-Path $env:SystemRoot 'System32\cmd.exe') -Destination (Join-Path $orch 'claude.exe')
$o2 = Join-Path $T 'out2'
$line = '/d /s /c ""{0}" -NoProfile -ExecutionPolicy Bypass -File "{1}" doctor > "{2}" 2>&1"' -f $Exe, $KitPs1, $o2
$p = Start-Process -FilePath (Join-Path $orch 'claude.exe') -ArgumentList $line -NoNewWindow -PassThru -Wait
Expect-Line 'the orchestrator is the claude parent' ('^orchestrator: claude ' + $p.Id + '$') $o2

# With a run, the doctor writes 00-doctor.txt and a manifest line.
$run = Join-Path $T 'run'
New-Item -ItemType Directory -Path $run | Out-Null
$env:AGENT_SIGNALS_RUN = $run
Expect-Code 'doctor with a run exits 0' 0 (Invoke-Kit 'doctor')
if (Test-Path -LiteralPath (Join-Path $run '00-doctor.txt')) { Pass 'the doctor file' } else { Fail 'the doctor file' 'no 00-doctor.txt' }
Expect-Line 'the doctor manifest line' '^step\tdoctor\tnone\tok\t[0-9]{8}T[0-9]{6}Z\t[0-9]{8}T[0-9]{6}Z\t00-doctor\.txt\t[0-9a-f]{64}$' (Join-Path $run 'manifest.tsv')
Expect-Code 'doctor with an argument is bad use' 2 (Invoke-Kit 'doctor' 'extra')

Complete-Tests
