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
# On Windows the plan has the probe (backend "none") and the first run
# (backend "conpty"). The session steps come with Task 10 of the plan.
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

foreach ($s in @(Read-KitSteps)) {
    $agent = [string]$s.agent
    if ($agent -and $agent -ne '-' -and -not $agents.ContainsKey($agent)) { continue }
    foreach ($backend in @(Get-KitStepBackends $s)) {
        if (-not (Test-KitStepRuns $s $backend)) { continue }
        # The conpty first run needs a driver Python and the scenario files.
        if ($backend -eq 'conpty' -and (-not $conpty -or -not $scenario)) { continue }
        $line = 'step: {0}@{1} needs={2} cost={3} measures={4}' -f $s.name, $backend, $s.needs, $s.cost, $s.measures
        if ($homeMode -eq 'throwaway' -and $s.needs -eq 'login') { $line += ' skip=no-login' }
        Write-Output $line
    }
}
exit 0
