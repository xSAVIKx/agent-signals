# The login step of one agent for the kit-login-windows job of scenarios.yml,
# as scenarios/kit-login.sh does it on Linux and macOS.
#
#   pwsh -NoProfile -File scenarios\kit-login.ps1 install AGENT
#   $env:KIT_KEY = ...; pwsh -NoProfile -File scenarios\kit-login.ps1 run AGENT
#
# AGENT is claude, codex or cursor. "install" installs the agent with the
# commands of scenarios\install-windows-agents.ps1. It needs no key, and a
# failed install does not stop the job.
#
# "run" gives the key in KIT_KEY to the agent, runs the first permission-*
# step of the agent that "kit plan" lists, and deletes the key. The key
# goes through a file that only the owner can read:
#   claude  apiKeyHelper in ~\.claude\settings.json, with node: the helper
#           needs no POSIX shell. Not measured on Windows.
#   codex   "codex login --with-api-key" on stdin, and a fixed model at a
#           low effort.
#   cursor  a wrapper cursor-agent.cmd first on PATH that sets
#           CURSOR_API_KEY from the file. It finds the real command as the
#           kit does (Find-KitAgents). With no command, there is no wrapper,
#           and the script prints a "skip:" line.
#
# "run" always exits 0, so that the next steps of the job run. It adds one
# line to $env:RUNNER_TEMP\kit-failed.txt when the agent is not installed,
# its login fails, the plan has no step for it, or its step does not exit
# 0. The last step of the job reads that file.
#
# Needs: RUNNER_TEMP, a run of "kit start" in RUNNER_TEMP\kit. Cost: one
# model turn at most. Output: only through the scrub.
param(
  [Parameter(Mandatory = $true)][ValidateSet('install', 'run')][string]$Command,
  [Parameter(Mandatory = $true)][ValidateSet('claude', 'codex', 'cursor')][string]$Agent
)
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'probes\agent\lib.ps1')
$ErrorActionPreference = 'Continue'
$exe = (Get-Process -Id $PID).Path
$raw = Join-Path $env:RUNNER_TEMP "kit-login-$Agent.txt"

function Show-Raw([int]$Lines) {
  $text = ConvertTo-KitScrubbed (Read-KitText $raw)
  ($text -split "`r?`n" | Where-Object { $_ } | Select-Object -Last $Lines) | ForEach-Object { Write-Output $_ }
}

if ($Command -eq 'install') {
  switch ($Agent) {
    'claude' { & npm install -g '@anthropic-ai/claude-code' *> $raw }
    'codex' { & npm install -g '@openai/codex' *> $raw }
    'cursor' {
      & $exe -NoProfile -Command "irm 'https://cursor.com/install?win32=true' | iex" *> $raw
      if ($env:GITHUB_PATH) { "$env:LOCALAPPDATA\cursor-agent" | Out-File -FilePath $env:GITHUB_PATH -Append -Encoding utf8 }
    }
  }
  Write-Output "install $Agent`: exit $LASTEXITCODE"
  Show-Raw 3
  exit 0
}

$key = $env:KIT_KEY
Remove-Item Env:KIT_KEY -ErrorAction SilentlyContinue
$kd = Join-Path $HOME '.config\agent-signals-keys'
$utf8 = New-Object System.Text.UTF8Encoding $false

# Invoke-Login: the login and the step. It sets $script:why to the reason
# of a failure.
$script:why = $null
function Invoke-Login {
  if (-not $key) { $script:why = 'the step has no key'; return }
  New-Item -ItemType Directory -Force -Path $kd | Out-Null
  $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  & icacls $kd /inheritance:r /grant:r "*${sid}:(OI)(CI)F" "*S-1-5-18:(OI)(CI)F" | Out-Null
  & icacls $kd /remove:g "*S-1-5-11" "*S-1-5-32-545" | Out-Null
  $found = @(Find-KitAgents | Where-Object { $_.Name -eq $Agent })
  if ($found.Count -eq 0) {
    if ($Agent -eq 'cursor') { Write-Output 'skip: no cursor-agent, so no wrapper' }
    $script:why = 'not installed'; return
  }
  switch ($Agent) {
    'claude' {
      [IO.File]::WriteAllText((Join-Path $kd 'claude'), $key, $utf8)
      New-Item -ItemType Directory -Force -Path (Join-Path $HOME '.claude') | Out-Null
      $helper = "node -p `"require('fs').readFileSync(require('os').homedir()+'/.config/agent-signals-keys/claude','utf8')`""
      $settings = @{ apiKeyHelper = $helper; model = 'haiku' } | ConvertTo-Json -Compress
      [IO.File]::WriteAllText((Join-Path $HOME '.claude\settings.json'), $settings + "`n", $utf8)
      [IO.File]::WriteAllText((Join-Path $HOME '.claude.json'), '{"hasCompletedOnboarding":true,"theme":"dark"}' + "`n", $utf8)
    }
    'codex' {
      $key | & $found[0].Command login --with-api-key *> $raw
      if ($LASTEXITCODE -ne 0) { Show-Raw 3; $script:why = 'codex login failed'; return }
      Write-Output 'codex login: ok'
      New-Item -ItemType Directory -Force -Path (Join-Path $HOME '.codex') | Out-Null
      # The model of the Codex screens in corpus\codex.
      [IO.File]::AppendAllText((Join-Path $HOME '.codex\config.toml'), "model = `"gpt-6-luna`"`nmodel_reasoning_effort = `"low`"`n", $utf8)
    }
    'cursor' {
      [IO.File]::WriteAllText((Join-Path $kd 'cursor'), $key, $utf8)
      $w = Join-Path $env:RUNNER_TEMP 'kit-wrap'
      New-Item -ItemType Directory -Force -Path $w | Out-Null
      $cmd = "@echo off`r`nset /p CURSOR_API_KEY=<`"%USERPROFILE%\.config\agent-signals-keys\cursor`"`r`n`"$($found[0].File)`" %*`r`n"
      [IO.File]::WriteAllText((Join-Path $w 'cursor-agent.cmd'), $cmd)
      $env:PATH = "$w;$env:PATH"
    }
  }
  $kit = Join-Path $root 'probes\agent\kit.ps1'
  $pointer = Join-Path $env:RUNNER_TEMP 'kit\.agent-signals-run'
  if (Test-Path -LiteralPath $pointer) { $env:AGENT_SIGNALS_RUN = (Get-Content -LiteralPath $pointer | Select-Object -First 1) }
  & $exe -NoProfile -ExecutionPolicy Bypass -File $kit plan --home real *> $raw
  $step = ''
  foreach ($l in @(Get-Content -LiteralPath $raw)) {
    # The kit names the Cursor CLI "cursor-agent".
    $kitAgent = if ($Agent -eq 'cursor') { 'cursor-agent' } else { $Agent }
    if ($l -match "^step: (permission-$kitAgent@\S+) ") { $step = $Matches[1]; break }
  }
  if (-not $step) { $script:why = 'the plan has no permission step'; return }
  & $exe -NoProfile -ExecutionPolicy Bypass -File $kit step $step *> $raw
  $rc = $LASTEXITCODE
  Show-Raw 20
  & $exe -NoProfile -ExecutionPolicy Bypass -File $kit session stop --all *> $null
  if ($rc -ne 0) { $script:why = "kit step ${step}: exit $rc"; return }
}

try {
  Invoke-Login
} finally {
  foreach ($f in (Join-Path $kd $Agent), (Join-Path $HOME '.codex\auth.json')) {
    Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
  }
  Remove-Item -LiteralPath $raw -Force -ErrorAction SilentlyContinue
}
if ($script:why) {
  "$Agent`: $($script:why)" | Out-File -FilePath (Join-Path $env:RUNNER_TEMP 'kit-failed.txt') -Append -Encoding utf8
  Write-Output "fail: ${Agent}: $($script:why)"
}
exit 0
