# kit plan on Windows: print the steps that this machine can run.
#
#   kit plan [--home real|throwaway] [--python PATH]
#
# One line for each step of probes\agent\steps.tsv, in file order:
#   step: <name>@<backend> needs=<needs> cost=<cost> measures=<text>
# A step whose agent is not installed, or whose backend tool is missing,
# is not printed. With the throwaway home, a step with needs=login has
# " skip=no-login" at the end. With no --home, the home mode of the run
# counts, else "real".
# The backends on Windows, from the column "backends":
#   none      the probe.
#   conpty    the first run: a driver Python (or uv) and the scenario
#             files. A test session (permission, new-chat, interrupt): a
#             Python that imports winpty, pyte, wcwidth and psutil, as
#             "kit session start --via conpty" finds it.
#   psmux     a test session: psmux (or pmux) on PATH.
#   operator  the real session of the operator: no tool.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')
# The arguments as strings (see Get-KitArgs in lib.ps1).
[string[]]$argv = @(Get-KitArgs $args)

$homeMode = ''
$python = ''
for ($i = 0; $i -lt $argv.Count; $i++) {
    $a = [string]$argv[$i]
    if ($a -eq '--home' -and $i + 1 -lt $argv.Count) { $homeMode = [string]$argv[++$i] }
    elseif ($a -eq '--python' -and $i + 1 -lt $argv.Count) { $python = [string]$argv[++$i] }
    else { Stop-Kit 2 'usage: kit plan [--home real|throwaway] [--python PATH]' }
}
$run = Find-KitRunDir
if (-not $homeMode) {
    if ($run) { $homeMode = Get-KitMeta $run 'home' }
    if (-not $homeMode) { $homeMode = 'real' }
}
if ($homeMode -cnotin 'real', 'throwaway') { Stop-Kit 2 "unknown home mode: $homeMode" }

$agents = @{}
foreach ($a in @(Find-KitAgents)) { $agents[$a.Name] = $a }
$conpty = Get-KitConptyTool $python $run
$scenario = Test-KitScenario

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
    return $script:SessionPython
}
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
            } elseif (-not (Test-SessionPython)) { continue }
        }
        if ($backend -eq 'psmux' -and -not $psmux) { continue }
        $line = 'step: {0}@{1} needs={2} cost={3} measures={4}' -f $s.name, $backend, $s.needs, $s.cost, $s.measures
        if ($homeMode -eq 'throwaway' -and $s.needs -eq 'login') { $line += ' skip=no-login' }
        Write-Output $line
    }
}
exit 0
