# kit plan on Windows: print the steps that this machine can run.
#
#   kit plan [--home real|throwaway|fixture] [--unattended] [--skip-agent AGENT]... [--python PATH]
#
# One line for each step of probes\agent\steps.tsv, in file order:
#   step: <name>@<backend> needs=<needs> cost=<cost> measures=<text>
# A step whose agent is not installed, or whose backend tool is missing,
# is not printed. With the throwaway home, a step with needs=login has
# " skip=no-login" at the end. With no --home, the home mode of the run
# counts, else "real". A step of an agent of --skip-agent, or of a
# "skip_agent" line of the run when the command has no --skip-agent, has
# " skip=by-operator".
# The backends on Windows, from the column "backends":
#   none      the probe.
#   conpty    the first run: a driver Python (or uv) and the scenario
#             files. A test session (permission, new-chat, interrupt):
#             scenarios\conpty.py and a Python that imports winpty, pyte,
#             wcwidth and psutil, as "kit session start --via conpty"
#             finds it (also a uv environment). When the plan drops the
#             session steps on conpty, it writes the reason to stderr.
#   psmux     a test session: psmux (or pmux) on PATH.
#   operator  the real session of the operator: no tool.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')
# The arguments as strings (see Get-KitArgs in lib.ps1).
[string[]]$argv = @(Get-KitArgs $args)

$homeMode = ''
$unattended = ''
$python = ''
$skipped = @()
$given = $false
for ($i = 0; $i -lt $argv.Count; $i++) {
    $a = [string]$argv[$i]
    if ($a -eq '--home' -and $i + 1 -lt $argv.Count) { $homeMode = [string]$argv[++$i] }
    elseif ($a -eq '--unattended') { $unattended = 'yes' }
    elseif ($a -eq '--skip-agent' -and $i + 1 -lt $argv.Count) {
        $sa = [string]$argv[++$i]
        $why = Get-KitSkipAgentProblem $sa
        if ($why) { Stop-Kit 2 $why }
        $skipped += $sa
        $given = $true
    }
    elseif ($a -eq '--python' -and $i + 1 -lt $argv.Count) { $python = [string]$argv[++$i] }
    else { Stop-Kit 2 'usage: kit plan [--home real|throwaway|fixture] [--unattended] [--skip-agent AGENT]... [--python PATH]' }
}
$run = Find-KitRunDir
if (-not $homeMode) {
    if ($run) { $homeMode = Get-KitMeta $run 'home' }
    if (-not $homeMode) { $homeMode = 'real' }
}
if (-not $unattended) {
    if ($run) { $unattended = Get-KitMeta $run 'unattended' }
    if (-not $unattended) { $unattended = 'no' }
}
# With no --skip-agent, the plan uses the skip_agent lines of the run.
if (-not $given -and $run) { $skipped = @(Get-KitMetaAll $run 'skip_agent') }
if ($homeMode -cnotin 'real', 'throwaway', 'fixture') { Stop-Kit 2 "unknown home mode: $homeMode" }

$agents = @{}
foreach ($a in @(Find-KitAgents)) { $agents[$a.Name] = $a }
$conpty = Get-KitConptyTool $python $run
$scenario = Test-KitScenario
# A release kit can lack the driver of the test sessions. Then "kit step"
# skips with the reason needs-scenario, as the first run does.
$conptyDriver = Test-Path -LiteralPath (Join-Path $script:KitRoot 'scenarios\conpty.py') -PathType Leaf

# Test-SessionPython: true when a Python of "kit session" imports the
# packages of the conpty driver. The order of session.ps1:
# AGENT_SIGNALS_PYTHON, the Python of the run, python and python3 on PATH
# (not the WindowsApps alias). The plan reads the answer one time.
$script:SessionPython = $null
function Test-SessionPython {
    if ($null -ne $script:SessionPython) { return $script:SessionPython }
    $c = @()
    if ($env:AGENT_SIGNALS_PYTHON) { $c += $env:AGENT_SIGNALS_PYTHON }
    if ($run) {
        $f = ((Read-KitText (Join-Path $run '.kit\python')) -split "`r?`n")[0]
        if ($f) { $c += $f }
    }
    foreach ($n in 'python', 'python3') {
        $g = Get-Command $n -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($g -and $g.Source -notmatch '(?i)[\\/]WindowsApps[\\/]') { $c += $g.Source }
    }
    $script:SessionPython = $false
    foreach ($py in $c) {
        if (-not $py -or -not (Test-Path -LiteralPath $py -PathType Leaf)) { continue }
        $r = Invoke-KitNative $py @('-I', '-c', 'import winpty, pyte, wcwidth, psutil')
        if ($r.Code -eq 0) { $script:SessionPython = $true; break }
    }
    if (-not $script:SessionPython -and (Get-KitUvDriverPython $run)) { $script:SessionPython = $true }
    return $script:SessionPython
}
$script:ConptyWhy = ''
$psmux = [bool]((Get-KitCommandFile 'psmux') -or (Get-KitCommandFile 'pmux'))

foreach ($s in @(Read-KitSteps)) {
    $agent = [string]$s.agent
    if ($agent -and $agent -ne '-' -and -not $agents.ContainsKey($agent)) { continue }
    foreach ($backend in @(Get-KitStepBackends $s)) {
        if (-not (Test-KitStepRuns $s $backend)) { continue }
        if ($backend -eq 'conpty') {
            if ($s.kind -eq 'first-run') {
                # The conpty first run needs a driver Python and the scenario files.
                if (-not $conpty -or -not $scenario) { continue }
            } elseif (-not $conptyDriver) {
                if (-not $script:ConptyWhy) { $script:ConptyWhy = 'the kit has no scenarios\conpty.py' }
                continue
            } elseif (-not (Test-SessionPython)) {
                if (-not $script:ConptyWhy) { $script:ConptyWhy = 'no Python imports winpty, pyte, wcwidth and psutil, and uv is missing or failed (set AGENT_SIGNALS_PYTHON or kit start --python)' }
                continue
            }
        }
        if ($backend -eq 'psmux' -and -not $psmux) { continue }
        $cost = if ($homeMode -eq 'fixture') { 'none' } else { $s.cost }
        $line = 'step: {0}@{1} needs={2} cost={3} measures={4}' -f $s.name, $backend, $s.needs, $cost, $s.measures
        $why = Get-KitLoginSkip $homeMode $s.needs $s.agent
        if (-not $why) { $why = Get-KitOperatorSkip $skipped $s.agent }
        if (-not $why) { $why = Get-KitUnattendedSkip $unattended $s.needs $backend }
        if ($why) { $line += " skip=$why" }
        Write-Output $line
    }
}
if ($script:ConptyWhy) { [Console]::Error.WriteLine("kit: the session steps on conpty do not run: $($script:ConptyWhy)") }
exit 0
