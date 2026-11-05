# The step kind "real-session" on Windows, backend operator: the guided
# step for a session of the agent that the operator starts in a real
# terminal app. The kit never types into this session. It is the twin of
# steps/real-session.sh.
#
#   kit step real-session-AGENT@operator            exit 4: what to do
#   kit step real-session-AGENT@operator --ready [--kind KIND]
#
# The first call writes "operator: <action>" lines to the step file and
# exits 4. With --ready, it runs the guided watch (probes\run.ps1 -Guided
# KIND AGENT) for AGENT_SIGNALS_WATCH seconds (default 30). KIND is
# permission (the default), new-chat, resume or interrupt. The watch
# counts only the processes of the agent that are not in RUN\pids\ (the
# kit started them), not above this step, and not the agent that runs the
# kit (the orchestrator) or a process below it. When no such process runs,
# the step exits 4 again.
# Exit codes: 0 ok, 1 fail, 4 the operator must act.
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib.ps1')
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }

$run = $env:KIT_RUN
$out = $env:KIT_OUT
if (-not $run -or -not $out) { Stop-Kit 2 'run this script with kit step' }
[string[]]$argv = @(Get-KitArgs $args)
$ready = $false
$kind = 'permission'
for ($i = 0; $i -lt $argv.Count; $i++) {
    if ($argv[$i] -ceq '--ready') { $ready = $true }
    elseif ($argv[$i] -ceq '--kind' -and $i + 1 -lt $argv.Count) { $kind = $argv[++$i] }
    else { Stop-Kit 2 "usage: kit step $env:KIT_STEP@operator [--ready [--kind permission|new-chat|resume|interrupt]]" }
}
if ($kind -cnotin 'permission', 'new-chat', 'resume', 'interrupt') { Stop-Kit 2 "unknown kind: $kind" }
$agent = [string]$env:KIT_AGENT
$watchS = 30
if ($env:AGENT_SIGNALS_WATCH -match '^[1-9][0-9]*$' -and [int]$env:AGENT_SIGNALS_WATCH -le 600) { $watchS = [int]$env:AGENT_SIGNALS_WATCH }
$actions = @{
    'permission' = 'ask for a file write, for example: Create a file named note.txt that holds the word hello. Do not answer the dialog until the watch ends.'
    'new-chat'   = 'start a new chat: /new-chat in Cursor, /clear in Claude, /new in Codex.'
    'resume'     = 'exit the session, then start it again with its resume command: cursor-agent --resume, claude --continue, codex resume --last, agy --continue.'
    'interrupt'  = 'send a prompt that takes some time, then push Esc while the agent works. Then push Ctrl+C one time.'
}

function Write-Operator([string]$Why) {
    $lines = @(
        "operator: start $agent in a real terminal app (Windows Terminal, a JetBrains IDE or VS Code), in a folder that you choose."
        "operator: wait for its idle screen. Do not type into it yet."
        "operator: then tell the agent that runs the kit to run: kit step $env:KIT_STEP@operator --ready"
        "operator: the kit then watches for $watchS s. In that time, in the session of ${agent}: $($actions[$kind])"
    )
    if ($Why) { $lines = @("operator: $Why") + $lines }
    $text = ($lines -join "`n") + "`n"
    Write-KitText $out $text
    [Console]::Out.Write($text)
    Write-KitText "$out.reason" "start-$agent-then-ready`n"
    exit 4
}

if (-not $ready) { Write-Operator '' }

$runPs1 = Join-Path $script:KitRoot 'probes\run.ps1'
$exe = (Get-Process -Id $PID).Path
$watchOut = "$out.watch"
$argText = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' + (Format-KitArg $runPs1) +
    " -Guided $kind $agent -Wait $watchS -ExceptPids " + (Format-KitArg (Join-Path $run 'pids')) + ' -ExceptCaller -Out ' + (Format-KitArg $watchOut)
New-Item -ItemType Directory -Force -Path (Join-Path $run 'pids') | Out-Null
$p = Start-KitProcess $run "watch real-session $agent" $exe $argText "$out.watch.console" "$out.watch.err" $run
$w = Wait-KitProcess $run $p ($watchS + 120)
$console = (Read-KitText "$out.watch.console") + (Read-KitText "$out.watch.err")
$text = Read-KitText $watchOut
foreach ($x in $watchOut, "$out.watch.console", "$out.watch.err") { Remove-Item -LiteralPath $x -Force -ErrorAction SilentlyContinue }
if ($w.Code -eq 2 -and $console -match 'no session of') { Write-Operator "no session of $agent runs outside the kit." }
if ($w.TimedOut -or $w.Code -ne 0 -or -not $text) {
    Write-KitText $out ("# real-session ${agent}: the watch failed (exit $($w.Code))`n" + $console)
    Write-KitText "$out.reason" "watch-failed`n"
    exit 1
}
Write-KitText $out ("# agent-signals real session: $env:KIT_STEP@operator, kind $kind`n" + $text)
exit 0
