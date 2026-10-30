# Installs one group of agents on a Windows runner, for the Windows jobs of
# the scenarios workflow. The install commands come from the npm registry or
# the vendor's install page. A failed install skips that agent and does not
# stop the script.
#
# Needs: Node.js and npm on PATH. Writes to GITHUB_PATH when it is set, so
# that the next steps find the agents that do not install with npm.
# Run: pwsh -NoProfile -File scenarios\install-windows-agents.ps1 -Group a|b

param([Parameter(Mandatory = $true)][ValidateSet('a', 'b')][string]$Group)

$ErrorActionPreference = 'Continue'

$npm = @{
  a = @('@anthropic-ai/claude-code', '@openai/codex', 'opencode-ai', '@google/gemini-cli',
    '@github/copilot', '@qwen-code/qwen-code')
  b = @('@ampcode/cli', '@charmland/crush', '@continuedev/cli', '@factory/cli', 'cline',
    '@kilocode/cli', '@augmentcode/auggie')
}

function Add-ToPath([string]$Dir) {
  $env:PATH = "$Dir;$env:PATH"
  if ($env:GITHUB_PATH) { $Dir | Out-File -FilePath $env:GITHUB_PATH -Append -Encoding utf8 }
}

# Runs an install page in a child PowerShell, so that an "exit" in the page
# does not stop this script.
function Invoke-InstallPage([string]$Url) {
  & pwsh -NoProfile -Command "irm '$Url' | iex" | Out-Host
  return $LASTEXITCODE
}

foreach ($p in $npm[$Group]) {
  Write-Output "::group::npm install -g $p"
  & npm install -g $p
  $rc = $LASTEXITCODE
  Write-Output '::endgroup::'
  Write-Output "install $p`: exit $rc"
}

if ($Group -eq 'a') {
  # The Windows installer of the Cursor CLI. It adds
  # %LOCALAPPDATA%\cursor-agent to the PATH of the user.
  Write-Output '::group::Cursor CLI'
  $rc = Invoke-InstallPage 'https://cursor.com/install?win32=true'
  Write-Output '::endgroup::'
  Write-Output "install Cursor CLI: exit $rc"
  Add-ToPath "$env:LOCALAPPDATA\cursor-agent"
} else {
  Write-Output '::group::Kimi Code CLI'
  $rc = Invoke-InstallPage 'https://code.kimi.com/kimi-code/install.ps1'
  Write-Output '::endgroup::'
  Write-Output "install Kimi Code CLI: exit $rc"
  Add-ToPath "$HOME\.kimi-code\bin"
}
exit 0
