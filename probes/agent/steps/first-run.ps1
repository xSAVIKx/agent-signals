# The step kind "first-run" on Windows, backend conpty: the first start of
# an agent with a throwaway home and no login, as
# scenarios\first-run-windows.py does it in the scenarios workflow.
# kit step runs this script with the KIT_* variables of the step contract.
#
# The driver needs a Python with pywinpty, pyte and psutil: --python of
# kit start, AGENT_SIGNALS_PYTHON, else "uv run --with" the pinned
# packages, else python on PATH when it has the packages. With none, the
# step skips (exit 3).
# The raw output of the scenario goes to a folder in the run folder
# (SCN_OUT), not to scenarios\..\out. The step judges the result from that
# output, because the scenario script can stop with exit 0 after a
# failure. Then it writes a summary to KIT_OUT, as the -Summary of
# scenarios\first-run-windows.ps1 does. kit step scrubs it.
# Needs: no login. Cost: none. It types nothing into the agent.
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib.ps1')

$run = $env:KIT_RUN
$out = $env:KIT_OUT
if (-not $run -or -not $out) { Stop-Kit 2 'run this script with kit step' }
function Exit-Step([int]$Code, [string]$Reason) {
    if ($Reason) { Write-KitText "$out.reason" "$Reason`n" }
    exit $Code
}

$agent = $null
foreach ($a in @(Find-KitAgents)) { if ($a.Name -eq $env:KIT_AGENT) { $agent = $a } }
if (-not $agent) { Write-KitText $out "first-run: $env:KIT_AGENT is not installed`n"; Exit-Step 3 'not-installed' }

$tool = Get-KitConptyTool '' $run
if (-not $tool) { Write-KitText $out "first-run: no Python with pywinpty, pyte and psutil, and no uv`n"; Exit-Step 3 'needs-conpty-python' }
$cmd = Get-KitConptyCommand $tool
$raw = Split-Path -Parent $out
$work = Join-Path $raw ('first-run-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null

if ($tool.Kind -eq 'python') {
    $p = Start-KitProcess $run 'python import check' $cmd.Exe '-c "import winpty, pyte, psutil"' (Join-Path $work 'check.out') (Join-Path $work 'check.err') $work
    if ((Wait-KitProcess $run $p 120) -ne 0) {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        Write-KitText $out "first-run: the Python has not got pywinpty, pyte and psutil`n"
        Exit-Step 3 'needs-conpty-python'
    }
}

$scnOut = Join-Path $work 'out'
$env:SCN_OUT = $scnOut
$scriptFile = Join-Path $script:KitRoot 'scenarios\first-run-windows.py'
$argText = (@($cmd.Args, (Format-KitArg $scriptFile), (Format-KitArg $agent.Name), (Format-KitArg $agent.Command)) | Where-Object { $_ }) -join ' '
$stdout = Join-Path $work 'stdout'
$stderr = Join-Path $work 'stderr'
$p = Start-KitProcess $run "first-run $($agent.Name)" $cmd.Exe $argText $stdout $stderr $work
$code = Wait-KitProcess $run $p 420

function Get-Lines([string]$File, [int]$Max) {
    @((Read-KitText $File) -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First $Max)
}
# The path field of a .files line: "size mtime <sandbox>/home/...".
function Get-HomePaths([string]$File) {
    foreach ($l in ((Read-KitText $File) -split "`r?`n")) {
        $x = $l -split ' ', 3
        if ($x.Count -eq 3) { $x[2] -replace '^<sandbox>/home/', '' }
    }
}
function Get-Counts([string[]]$Paths, [int]$Parts, [int]$Top) {
    @($Paths | Where-Object { $_ } | ForEach-Object { (($_ -split '/') | Select-Object -First $Parts) -join '/' } |
        Group-Object | Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, Name |
        Select-Object -First $Top | ForEach-Object { '{0,7} {1}' -f $_.Count, $_.Name })
}

$sb = New-Object System.Text.StringBuilder
function Add-Out([string[]]$Lines) { foreach ($l in $Lines) { [void]$sb.AppendLine($l) } }
Add-Out @("# first-run-windows $($agent.Name) (conpty, throwaway home, no login)", "first-run: tool $($tool.Kind)")
Add-Out @('### scenario output')
Add-Out @((Get-Lines $stdout 200) | Where-Object { $_ -notmatch '^output: ' })
Add-Out @((Get-Lines $stderr 40))
if ($code -eq -1) { Add-Out @('first-run: stopped at the time limit of 420 s') }
Add-Out @('### log')
Add-Out (Get-Lines (Join-Path $scnOut 'log.txt') 100)
foreach ($s in '01-after-5s', '02-after-20s') {
    Add-Out @("### screen $s")
    Add-Out (Get-Lines (Join-Path $scnOut "$s.screen") 40)
}
Add-Out @('### processes after 20 s (pid ppid name command)')
Add-Out (Get-Lines (Join-Path $scnOut '02-after-20s.ps') 60)
Add-Out @('### top folders made in the throwaway home')
Add-Out (Get-Counts @(Get-HomePaths (Join-Path $scnOut '02-after-20s.files')) 2 15)
Add-Out @('### folders made in the throwaway home (files in each)')
Add-Out (Get-Counts @(Get-HomePaths (Join-Path $scnOut '02-after-20s.files')) 3 40)
Add-Out @('### changes in the real profile folders')
Add-Out (Get-Lines (Join-Path $scnOut '02-after-20s.outside') 30)
Add-Out @('### open files below the throwaway home')
Add-Out @((Get-Lines (Join-Path $scnOut '02-after-20s.open') 400) | Where-Object { $_ -match '<sandbox>[\\/](home|\.)' } |
        ForEach-Object { ($_ -split ' ', 2)[1] -replace '^<sandbox>[\\/]home[\\/]', '' } | Sort-Object -Unique | Select-Object -First 30)
Write-KitText $out $sb.ToString()

# The result comes from the output: the scenario prints "done:" at its
# end, and "scenario: not installed" when the command is missing.
$done = (Read-KitText $stdout) -match '(?m)^done: '
$errText = Read-KitText $stderr
Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
if ($code -eq -1) { Exit-Step 1 'time-limit' }
if ($done -and (Test-Path -LiteralPath $out)) { Exit-Step 0 '' }
if ($errText -match 'not installed') { Exit-Step 3 'not-installed' }
if ($errText -match "No module named|ModuleNotFoundError") { Exit-Step 3 'needs-conpty-python' }
Exit-Step 1 'no-done-line'
