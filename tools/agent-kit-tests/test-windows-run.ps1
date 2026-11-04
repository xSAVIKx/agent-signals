# kit start, plan, step, check and edit on Windows, with a fake home that
# holds known secret strings (LEAK-CANARY-<n>), a fake claude and a stub
# Python for the conpty first run.
. (Join-Path $env:ROOT 'tools/agent-kit-tests/lib.ps1')
$out = Join-Path $T 'out'
# Expect-Kit NAME CODE ARGS: run the kit, and show its output when the
# exit code is not CODE.
function Expect-Kit([string]$Name, [int]$Want) {
    $c = Invoke-Kit @args
    Expect-Code $Name $Want $c
    if ($c -ne $Want) { Get-Content -LiteralPath (Join-Path $T 'out') | ForEach-Object { "  | $_" } }
}
function Expect-NoLine([string]$Name, [string]$Pattern, [string]$File) {
    if (Select-String -LiteralPath $File -Pattern $Pattern -Quiet) { Fail $Name "a line matches: $Pattern" } else { Pass $Name }
}
function New-TextFile([string]$File, [string]$Text) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $File) | Out-Null
    [IO.File]::WriteAllText($File, $Text)
}
function Get-Sha([string]$File) { (Get-FileHash -Algorithm SHA256 -LiteralPath $File).Hash.ToLowerInvariant() }

# The fake home, with secrets that no file of the run may hold.
$h = Join-Path $T 'home'
New-TextFile (Join-Path $h '.claude\.credentials.json') '{"claudeAiOauth":{"accessToken":"LEAK-CANARY-1"}}'
New-TextFile (Join-Path $h '.claude\projects\-work-example\session.jsonl') '{"type":"user","message":{"content":"LEAK-CANARY-2"}}'
New-TextFile (Join-Path $h '.claude\settings.json') '{"env":{"EXAMPLE":"LEAK-CANARY-3"}}'
New-TextFile (Join-Path $h '.codex\auth.json') '{"OPENAI_API_KEY":"LEAK-CANARY-4"}'
$env:USERPROFILE = $h
$env:APPDATA = Join-Path $h 'AppData\Roaming'
$env:LOCALAPPDATA = Join-Path $h 'AppData\Local'
New-Item -ItemType Directory -Force -Path $env:APPDATA, $env:LOCALAPPDATA | Out-Null
$env:EXAMPLE_API_KEY = 'LEAK-CANARY-5-example'
$env:EXAMPLE_SECRET = 'LEAK-CANARY-6-secret'
# A OneDrive folder with a space and a company name, which tools\scrub.ps1
# cannot find by itself.
$env:OneDrive = Join-Path $h 'OneDrive - Contoso'

# A fake claude on PATH, and a stub Python that draws the files of
# scenarios\first-run-windows.py.
$bin = Join-Path $T 'bin'
New-TextFile (Join-Path $bin 'claude.cmd') "@echo off`r`necho 2.1.316 (Claude Code)`r`n"
$py = Join-Path $T 'py\python.cmd'
New-TextFile $py (@(
        '@echo off'
        'if "%~1"=="-c" exit /b 0'
        'mkdir "%SCN_OUT%" 2>nul'
        'echo scenario: first-run-windows-%~2'
        '>"%SCN_OUT%\log.txt" echo 00:00:00 version: stub 1.0 (exit 0)'
        '>"%SCN_OUT%\01-after-5s.screen" echo stub first screen'
        '>"%SCN_OUT%\02-after-20s.screen" echo stub screen after 20 s'
        '>"%SCN_OUT%\02-after-20s.ps" echo 100 99 stub.exe stub'
        '>"%SCN_OUT%\02-after-20s.files" echo 10 0 ^<sandbox^>/home/.stub/state.json'
        '>>"%SCN_OUT%\02-after-20s.screen" echo kit %KIT_ROOT%\probes and %OneDrive%\doc.txt'
        'echo done: stub'
        'exit /b 0'
    ) -join "`r`n")
$env:PATH = "$bin;$env:SystemRoot\System32;$env:SystemRoot;$env:SystemRoot\System32\WindowsPowerShell\v1.0"
$env:AGENT_SIGNALS_PYTHON = $py
Remove-Item Env:\AGENT_SIGNALS_RUN -ErrorAction SilentlyContinue

# The step list of the test. It has the columns of probes/agent/steps.tsv.
$steps = Join-Path $T 'steps.tsv'
New-TextFile $steps ((@(
            "name`tkind`tagent`tbackends`tneeds`tcost`tprompt`twait_regex`tanswer`tmeasures`tfacts"
            "probe`tprobe`t-`t-`tnone`tnone`t-`t-`t-`tthe full probe kit`t-"
            "first-run-claude`tfirst-run`tclaude`ttmux,conpty`tnone`tnone`t-`t-`t-`tthe first start with no login`t029"
            "first-run-codex`tfirst-run`tcodex`ttmux,conpty`tnone`tnone`t-`t-`t-`tthe first start with no login`t029"
            "first-run-tmux-claude`tfirst-run`tclaude`ttmux,pty`tnone`tnone`t-`t-`t-`ta line with no Windows backend`t-"
            "first-login-claude`tfirst-run`tclaude`tconpty`tlogin`tturns:1`t-`t-`t-`ta test line with a login`t-"
            "permission-claude`tpermission`tclaude`ttmux,pty,conpty`tlogin`tturns:1`tCreate a file named agent-signals-test.txt that holds the word hello.`tDo you want`t1`tthe permission dialog`t023"
        ) -join "`n") + "`n")
$env:KIT_STEPS = $steps

# kit start refuses unsafe places.
$repo = Join-Path $T 'repo'
New-Item -ItemType Directory -Force -Path (Join-Path $repo '.git'), (Join-Path $repo 'sub') | Out-Null
Expect-Kit 'start refuses a git work tree' 2 'start' '--out' (Join-Path $repo 'sub')
$agentDir = Join-Path $h '.claude\runs'
Expect-Kit 'start refuses an agent folder' 2 'start' '--out' $agentDir
$open = Join-Path $T 'open'
New-Item -ItemType Directory -Path $open | Out-Null
$ErrorActionPreference = "Continue"
$null = & icacls.exe $open /grant "*S-1-1-0:(OI)(CI)M" 2>&1
$ErrorActionPreference = "Stop"
Expect-Kit 'start refuses a folder that Everyone can write' 2 'start' '--out' $open
Expect-Line 'start names the reason' 'Everyone can write' $out
Expect-Line 'start prints the icacls fix' '^  icacls ".*open" /inheritance:r /grant:r ' $out
# The allow list: an account that is not in it (Backup Operators) fails.
$other = Join-Path $T 'other'
New-Item -ItemType Directory -Path $other | Out-Null
$ErrorActionPreference = "Continue"
$null = & icacls.exe $other /grant "*S-1-5-32-551:(OI)(CI)M" 2>&1
$ErrorActionPreference = "Stop"
Expect-Kit 'start refuses a write right outside the allow list' 2 'start' '--out' $other
Expect-Line 'start names the account' 'can write to the folder' $out
Expect-Kit 'start refuses an unknown home mode' 2 'start' '--home' 'other' '--out' (Join-Path $T 'x')
Expect-Kit 'start refuses an unknown option' 2 'start' '-Home' 'real'

# kit start in a folder with a space.
$dir = Join-Path $T 'out dir'
Expect-Kit 'start exits 0' 0 'start' '--out' $dir
Expect-Line 'start prints the run' '^run: .*agent-signals-run-windows-[0-9]{8}T[0-9]{6}Z$' $out
$run = (Get-Content -LiteralPath (Join-Path $dir '.agent-signals-run') -TotalCount 1)
if ($run -and (Test-Path -LiteralPath $run -PathType Container)) { Pass 'the run file names the run' } else { Fail 'the run file names the run' 'no run folder' }
Expect-Line 'the manifest has the home mode' '^meta\thome\treal$' (Join-Path $run 'manifest.tsv')
$acl = Get-Acl -LiteralPath $run
$openRule = @($acl.Access | Where-Object { $_.IdentityReference.Value -match '(?i)Everyone|\\Users$|Authenticated Users' })
if ($openRule.Count -eq 0) { Pass 'the run folder is private' } else { Fail 'the run folder is private' "$($openRule.Count) open rules" }
# start made DIR, so DIR is private too.
$me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$dacl = @((Get-Acl -LiteralPath $dir).GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]) | ForEach-Object { $_.IdentityReference.Value } | Where-Object { $_ -ne $me -and $_ -ne 'S-1-5-18' })
if ($dacl.Count -eq 0) { Pass 'a new DIR is private' } else { Fail 'a new DIR is private' ($dacl -join ' ') }

# A run folder with letters outside ASCII: a new shell finds it from the
# pointer file, also in Windows PowerShell 5.1.
$uni = Join-Path $T ('run ' + [char]0x00E9 + [char]0x4E2D)
Expect-Kit 'start in a folder outside ASCII exits 0' 0 'start' '--out' $uni
Push-Location -LiteralPath $uni
Expect-Kit 'doctor finds a run outside ASCII' 0 'doctor'
Pop-Location
$uniRun = @(Get-ChildItem -LiteralPath $uni -Directory | Select-Object -First 1)
if ($uniRun.Count -eq 1 -and (Test-Path -LiteralPath (Join-Path $uniRun[0].FullName '00-doctor.txt'))) { Pass 'the doctor file is in the run outside ASCII' } else { Fail 'the doctor file is in the run outside ASCII' 'no 00-doctor.txt' }

# kit plan, from the current folder (a new shell finds the run there).
Push-Location -LiteralPath $dir
Expect-Kit 'plan exits 0' 0 'plan'
Pop-Location
Expect-Line 'plan lists the probe' '^step: probe@none needs=none cost=none measures=the full probe kit$' $out
Expect-Line 'plan lists the first run on conpty' '^step: first-run-claude@conpty needs=none cost=none measures=the first start with no login$' $out
Expect-NoLine 'plan skips an agent that is not installed' 'first-run-codex' $out
Expect-NoLine 'plan lists no session step yet' 'permission-claude' $out
Expect-NoLine 'plan skips a line with no Windows backend' 'first-run-tmux-claude' $out
Expect-NoLine 'plan with the real home has no skip' 'skip=' $out
Expect-Kit 'plan --home throwaway exits 0' 0 'plan' '--home' 'throwaway'
Expect-Line 'plan marks a login step' '^step: first-login-claude@conpty needs=login cost=turns:1 .* skip=no-login$' $out
$env:AGENT_SIGNALS_PYTHON = Join-Path $T 'no-such-python.exe'
Expect-Kit 'plan with no conpty Python exits 0' 0 'plan'
Expect-NoLine 'plan skips conpty with no Python' 'first-run-claude' $out
$env:AGENT_SIGNALS_PYTHON = $py

# kit step, in a new process for each command.
$env:AGENT_SIGNALS_RUN = $run
Expect-Kit 'an unknown step is bad use' 2 'step' 'no-such@none'
Expect-Kit 'a step with no backend is bad use' 2 'step' 'probe'
Expect-Kit 'the first run on tmux is bad use on Windows' 2 'step' 'first-run-claude@tmux'
Expect-Kit 'a line with no Windows backend is bad use' 2 'step' 'first-run-tmux-claude@conpty'
Expect-Kit 'step probe exits 0' 0 'step' 'probe@none'
Expect-Line 'step probe prints ok' '^step: probe@none ok$' $out
$f1 = Join-Path $run '01-probe@none.txt'
if (Test-Path -LiteralPath $f1) { Pass 'the probe file' } else { Fail 'the probe file' 'no 01-probe@none.txt' }
Expect-Line 'the probe ran the claude probe' '^==== probe claude/windows\.ps1$' $f1
Expect-Line 'the manifest line of the probe' ('^step\tprobe\tnone\tok\t[0-9]{8}T[0-9]{6}Z\t[0-9]{8}T[0-9]{6}Z\t01-probe@none\.txt\t' + (Get-Sha $f1) + '$') (Join-Path $run 'manifest.tsv')

Expect-Kit 'step first-run exits 0' 0 'step' 'first-run-claude@conpty'
Expect-Line 'step first-run prints ok' '^step: first-run-claude@conpty ok$' $out
$f2 = Join-Path $run '02-first-run-claude@conpty.txt'
Expect-Line 'the first-run file has the screen' '^stub screen after 20 s' $f2
Expect-Line 'the first-run file has the folders' '\.stub' $f2
Expect-Line 'the kit folder changes to <kit>' '^kit <kit>\\probes and ' $f2
Expect-NoLine 'the OneDrive folder is scrubbed' 'Contoso' $f2
$env:AGENT_SIGNALS_PYTHON = Join-Path $T 'no-such-python.exe'
Expect-Kit 'step first-run with no Python skips' 3 'step' 'first-run-claude@conpty'
Expect-Line 'the skip has a reason' '^step: first-run-claude@conpty skip needs-conpty-python$' $out
$env:AGENT_SIGNALS_PYTHON = $py
Expect-Kit 'a session step skips on Windows' 3 'step' 'permission-claude@conpty'

# kit check passes a clean run, and writes the summary, the JSON and the zip.
Expect-Kit 'check passes a clean run' 0 'check'
Expect-Line 'check prints ok' '^check: ok$' $out
Expect-Line 'check prints the archive' '^archive: .*\.zip$' $out
$summary = Join-Path $run 'summary.txt'
Expect-Line 'the first line of the summary' '^kit \S+ on windows \((x86_64|arm64)\), .+\. Run from [0-9]{8}T[0-9]{6}Z to [0-9]{8}T[0-9]{6}Z \(real\)\.$' $summary
try {
    $j = Get-Content -Raw -LiteralPath (Join-Path $run 'manifest.json') | ConvertFrom-Json
    if (@($j.steps).Count -eq 4) { Pass 'manifest.json has the steps' } else { Fail 'manifest.json has the steps' "$(@($j.steps).Count) steps" }
} catch { Fail 'manifest.json parses' $_.Exception.Message }
$zip = "$run.zip"
Add-Type -AssemblyName System.IO.Compression.FileSystem
$names = @()
$z = [System.IO.Compression.ZipFile]::OpenRead($zip)
try { $names = @($z.Entries | ForEach-Object { $_.FullName }) } finally { $z.Dispose() }
$leaf = Split-Path -Leaf $run
if ($names -contains "$leaf/01-probe@none.txt") { Pass 'the zip holds the probe file' } else { Fail 'the zip holds the probe file' ($names -join ' ') }
if (@($names | Where-Object { $_ -match '/(pids|sessions|\.kit|\.raw)/' }).Count -eq 0) { Pass 'the zip holds no state of the kit' } else { Fail 'the zip holds no state of the kit' ($names -join ' ') }

# The leak test: no canary in the run folder or the archive.
$hits = @(Get-ChildItem -LiteralPath $run -Recurse -File -Force | Select-String -Pattern 'LEAK-CANARY' -SimpleMatch)
if ($hits.Count -eq 0) { Pass 'no canary in the run folder' } else { Fail 'no canary in the run folder' "$($hits.Count) lines" }
$xd = Join-Path $T 'unzip'
[System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $xd)
$hits = @(Get-ChildItem -LiteralPath $xd -Recurse -File -Force | Select-String -Pattern 'LEAK-CANARY' -SimpleMatch)
if ($hits.Count -eq 0) { Pass 'no canary in the archive' } else { Fail 'no canary in the archive' "$($hits.Count) lines" }

# A change with no kit edit fails; kit edit records it.
$keep = [IO.File]::ReadAllText($f2)
[IO.File]::AppendAllText($f2, "a note`n")
Expect-Kit 'check fails a changed file' 1 'check'
Expect-Line 'check names the changed file' "^check: the file changed with no 'kit edit' line: 02-first-run-claude@conpty\.txt$" $out
Expect-Kit 'edit exits 0' 0 'edit' '02-first-run-claude@conpty.txt' 'added' 'a note'
Expect-Line 'edit prints the file' '^edit: 02-first-run-claude@conpty\.txt [0-9a-f]{64}$' $out
Expect-Line 'the edit line' ('^edit\t02-first-run-claude@conpty\.txt\tadded a note\t' + (Get-Sha $f2) + '$') (Join-Path $run 'manifest.tsv')
Expect-Kit 'check passes after kit edit' 0 'check'
Expect-Kit 'edit of a missing file is bad use' 2 'edit' 'no-such.txt' 'x'
Expect-Kit 'edit of the manifest is bad use' 2 'edit' 'manifest.tsv' 'x'

# A raw home folder, account name or secret value fails the check.
[IO.File]::AppendAllText($f2, "home $h`n")
$null = Invoke-Kit 'edit' '02-first-run-claude@conpty.txt' 'test'
Expect-Kit 'check fails the raw home folder' 1 'check'
Expect-Line 'check names the home folder' '^check: 02-first-run-claude@conpty\.txt holds the home folder$' $out
[IO.File]::WriteAllText($f2, $keep + "key LEAK-CANARY-5-exam`nple`n")
$null = Invoke-Kit 'edit' '02-first-run-claude@conpty.txt' 'test'
Expect-Kit 'check fails a secret value over two lines' 1 'check'
Expect-Line 'check names the variable' '^check: 02-first-run-claude@conpty\.txt holds the value of EXAMPLE_API_KEY$' $out
[IO.File]::WriteAllText($f2, $keep + "key LEAK-CANARY-6-secret`n")
$null = Invoke-Kit 'edit' '02-first-run-claude@conpty.txt' 'test'
Expect-Kit 'check fails a _SECRET value' 1 'check'
Expect-Line 'check names the secret variable' '^check: 02-first-run-claude@conpty\.txt holds the value of EXAMPLE_SECRET$' $out
[IO.File]::WriteAllText($f2, $keep + "file $($env:OneDrive)\doc.txt`n")
$null = Invoke-Kit 'edit' '02-first-run-claude@conpty.txt' 'test'
Expect-Kit 'check fails a raw OneDrive folder' 1 'check'
Expect-Line 'check names the OneDrive folder' '^check: 02-first-run-claude@conpty\.txt holds the OneDrive folder$' $out
[IO.File]::WriteAllText($f2, $keep)
$null = Invoke-Kit 'edit' '02-first-run-claude@conpty.txt' 'test'

# A raw file of a stopped step fails, and check names the folder to delete.
New-TextFile (Join-Path $run '.raw\09-probe@none.out') 'x'
Expect-Kit 'check fails a leftover raw file' 1 'check'
Expect-Line 'check tells how to clean the raw folder' "Remove-Item -Recurse -Force -LiteralPath '.*\.raw'" $out
Remove-Item -LiteralPath (Join-Path $run '.raw') -Recurse -Force

# A probe file with a missing section fails.
$pkeep = [IO.File]::ReadAllText($f1)
[IO.File]::WriteAllText($f1, ($pkeep -replace '(?m)^### 2\. ', '### two. '))
$null = Invoke-Kit 'edit' '01-probe@none.txt' 'test'
Expect-Kit 'check fails a probe with a missing section' 1 'check'
Expect-Line 'check names the section' '^check: 01-probe@none\.txt: claude/windows\.ps1: no section 2$' $out
[IO.File]::WriteAllText($f1, $pkeep)
$null = Invoke-Kit 'edit' '01-probe@none.txt' 'test'

# A pid of the run that still runs fails the check.
$sleep = Start-Process -FilePath $Exe -ArgumentList '-NoProfile -Command Start-Sleep -Seconds 120' -PassThru -WindowStyle Hidden
$ticks = $sleep.StartTime.ToUniversalTime().Ticks
[IO.File]::WriteAllText((Join-Path $run "pids\$($sleep.Id)"), "test sleep`t$ticks`n")
Expect-Kit 'check fails a pid that runs' 1 'check'
Expect-Line 'check names the pid' "^check: the pid $($sleep.Id) of the run still runs \(test sleep\)$" $out
[IO.File]::WriteAllText((Join-Path $run "pids\$($sleep.Id)"), "test sleep`t1`n")
Expect-Kit 'check ignores a reused pid' 0 'check'
[IO.File]::WriteAllText((Join-Path $run "pids\$($sleep.Id)"), "test sleep`n")
Expect-Kit 'check ignores a pid with no start time' 0 'check'
Stop-Process -Id $sleep.Id -Force
Remove-Item -LiteralPath (Join-Path $run "pids\$($sleep.Id)")
Expect-Kit 'check passes at the end' 0 'check'

# A file that is not in the manifest fails.
[IO.File]::WriteAllText((Join-Path $run 'extra.txt'), "x`n")
Expect-Kit 'check fails an unknown file' 1 'check'
Expect-Line 'check names the unknown file' '^check: the file is not in the manifest: extra\.txt$' $out

Remove-Item -LiteralPath (Join-Path $run 'extra.txt')

# A kit with no scenario files: the plan has no first run, and the step
# skips with needs-scenario.
$mini = Join-Path $T 'kit'
foreach ($f in @('probes\agent\kit.ps1', 'probes\agent\lib.ps1', 'probes\agent\start.ps1', 'probes\agent\plan.ps1', 'probes\agent\step.ps1',
        'probes\agent\steps\first-run.ps1', 'probes\lib.ps1', 'probes\claude\windows.ps1', 'tools\scrub.ps1')) {
    $to = Join-Path $mini $f
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $to) | Out-Null
    Copy-Item -LiteralPath (Join-Path $env:ROOT $f) -Destination $to
}
$miniOut = Join-Path $T 'mini-out'
function Invoke-Mini {
    $ErrorActionPreference = 'Continue'
    & $Exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $mini 'probes\agent\kit.ps1') @args *> $out
    return $LASTEXITCODE
}
Remove-Item Env:\AGENT_SIGNALS_RUN
Expect-Code 'start in a kit with no scenario' 0 (Invoke-Mini 'start' '--out' $miniOut)
$env:AGENT_SIGNALS_RUN = @(Get-ChildItem -LiteralPath $miniOut -Directory)[0].FullName
Expect-Code 'plan in a kit with no scenario' 0 (Invoke-Mini 'plan')
Expect-NoLine 'plan has no first run with no scenario' 'first-run-claude' $out
Expect-Code 'the first run with no scenario skips' 3 (Invoke-Mini 'step' 'first-run-claude@conpty')
Expect-Line 'the skip names the scenario' '^step: first-run-claude@conpty skip needs-scenario$' $out

Remove-Item Env:\AGENT_SIGNALS_RUN
Complete-Tests
