# kit doctor on Windows: print facts about this machine as "key: value"
# lines, as probes/agent/doctor.sh does. It is a fact collector, not a
# pass or fail list. It always exits 0.
#
#   kit doctor [--python PATH]
#
# The lines, in this order:
#   kit: <kit version>
#   os: windows
#   os_version: <Windows caption> <version>
#   cpu: x86_64|arm64
#   shell: powershell <version> <edition>
#   tool: <name> <path|missing>   for python, uv, psmux, handle and git
#   tool: conpty <python PATH|uv PATH|missing>
#       the program that runs scenarios\conpty.py: --python PATH,
#       AGENT_SIGNALS_PYTHON, the Python of the run, uv, or python.
#   agent: <name> missing
#   agent: <name> <resolved path> <version|unknown>
#       The version rules (the doctor never runs the agent):
#         1. ...\claude\versions\<v>, ...\cursor-agent\versions\<v>\ and
#            ...\packages\<kind>\releases\<v>-<target>\ (Codex) in the path.
#         2. ~\.local\bin\claude.exe: the file of
#            ~\.local\share\claude\versions\ with the same size (fact 071).
#         3. %LOCALAPPDATA%\cursor-agent\: the newest versions\<v>\ folder
#            (fact 047).
#         4. the "version" of package.json of the npm package (fact 047).
#         5. else unknown, for example %LOCALAPPDATA%\agy\bin\agy.exe.
#       A renamed program, for example claude.exe.old.<ms>.<pid>, is not
#       an install (fact 071).
#   orchestrator: <agent> <pid>
#   orchestrator: unknown -
#       The first parent process whose name or program path matches the
#       process pattern of probes\<agent>\windows.ps1, or whose command
#       line matches it when the process is not a shell (fact 070).
#   orchestrator_terminal: <NAME=value>, or "none"
#       The terminal variables of the kit process, which it gets from the
#       orchestrator (fact 069).
# When a run exists, the lines also go to 00-doctor.txt in the run folder.
# All output goes through tools\scrub.ps1. It opens no session file.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')
# The arguments as strings (see Get-KitArgs in lib.ps1).
[string[]]$argv = @(Get-KitArgs $args)
. (Join-Path $script:KitRoot 'probes\lib.ps1')

$python = ''
for ($i = 0; $i -lt $argv.Count; $i++) {
    $a = [string]$argv[$i]
    if ($a -eq '--python' -and $i + 1 -lt $argv.Count) { $python = [string]$argv[++$i] }
    else { Stop-Kit 2 'usage: kit doctor [--python PATH]' }
}
$run = Find-KitRunDir

$lines = New-Object System.Collections.ArrayList
function Add-Fact([string]$Text) { [void]$lines.Add($Text) }

$os = Get-KitOsInfo
Add-Fact "kit: $(Get-KitVersion)"
Add-Fact "os: $($os.Os)"
Add-Fact "os_version: $($os.Version)"
Add-Fact "cpu: $($os.Cpu)"
Add-Fact "shell: powershell $($PSVersionTable.PSVersion) $($PSVersionTable.PSEdition)"

$tools = [ordered]@{ 'python' = @('python', 'py'); 'uv' = @('uv'); 'psmux' = @('psmux', 'pmux'); 'handle' = @('handle', 'handle64'); 'git' = @('git') }
foreach ($t in $tools.Keys) {
    $file = $null
    foreach ($c in $tools[$t]) {
        $f = Get-KitCommandFile $c
        if ($f -and $f -notmatch '(?i)[\\/]WindowsApps[\\/]') { $file = $f; break }
    }
    if ($file) { Add-Fact "tool: $t $file" } else { Add-Fact "tool: $t missing" }
}
$ct = Get-KitConptyTool $python $run
if ($ct) { Add-Fact "tool: conpty $($ct.Kind) $($ct.Path)" } else { Add-Fact 'tool: conpty missing' }

$found = @{}
foreach ($a in @(Find-KitAgents)) { $found[$a.Name] = $a }
foreach ($n in $script:KitAgentCommands.Keys) {
    if ($found.ContainsKey($n)) {
        $a = $found[$n]
        Add-Fact "agent: $n $(Get-ResolvedPath $a.File) $($a.Version)"
    } else {
        Add-Fact "agent: $n missing"
    }
}

# The orchestrator: the first parent of the kit that is an agent.
$patterns = [ordered]@{}
foreach ($n in $script:KitAgentCommands.Keys) {
    $p = Get-KitAgentPattern $n
    if ($p) { $patterns[$n] = $p }
}
$shells = @('cmd', 'powershell', 'pwsh', 'bash', 'sh', 'zsh', 'conhost', 'openconsole', 'wsl', 'windowsterminal')
$orch = 'unknown'
$orchPid = '-'
$chain = @(Get-ParentObjects $PID)
for ($i = 1; $i -lt $chain.Count -and $orch -eq 'unknown'; $i++) {
    $q = $chain[$i]
    $base = [IO.Path]::GetFileNameWithoutExtension([string]$q.Name).ToLowerInvariant()
    foreach ($n in $patterns.Keys) {
        $hit = Test-AgentProcess $q $patterns[$n]
        if (-not $hit -and $shells -notcontains $base -and $q.CommandLine) { $hit = ([string]$q.CommandLine -match $patterns[$n]) }
        if ($hit) { $orch = $n; $orchPid = [string]$q.ProcessId; break }
    }
}
Add-Fact "orchestrator: $orch $orchPid"
$term = 0
foreach ($v in 'WT_SESSION', 'WT_PROFILE_ID', 'TERM_PROGRAM', 'TERM_PROGRAM_VERSION', 'TERM', 'TMUX', 'PSMUX', 'ConEmuPID', 'VSCODE_PID', 'TERMINAL_EMULATOR') {
    $val = [Environment]::GetEnvironmentVariable($v)
    if ($val) { Add-Fact "orchestrator_terminal: $v=$val"; $term++ }
}
if ($term -eq 0) { Add-Fact 'orchestrator_terminal: none' }

$start = Get-KitTime
$text = ConvertTo-KitScrubbed (($lines -join "`n") + "`n")
[Console]::Out.Write($text)
if ($run) {
    $file = Join-Path $run '00-doctor.txt'
    Write-KitText $file $text
    Add-KitManifest $run @('step', 'doctor', 'none', 'ok', $start, (Get-KitTime), '00-doctor.txt', (Get-KitSha256 $file))
}
exit 0
