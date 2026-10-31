# Installs one group of agents on a Windows runner, for the Windows jobs of
# the scenarios workflow. The install commands come from the npm registry or
# the vendor's install page. A failed install skips that agent and does not
# stop the script.
#
# Needs: Node.js and npm on PATH, and uv for group d. Writes to GITHUB_PATH
# when it is set, so that the next steps find the agents that do not
# install with npm.
# Run: pwsh -NoProfile -File scenarios\install-windows-agents.ps1 -Group a|b|c|d

param([Parameter(Mandatory = $true)][ValidateSet('a', 'b', 'c', 'd')][string]$Group)

$ErrorActionPreference = 'Continue'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools\scrub.ps1')
$scrub = Get-ScrubDefaults

$npm = @{
  a = @('@anthropic-ai/claude-code', '@openai/codex', 'opencode-ai', '@google/gemini-cli',
    '@github/copilot', '@qwen-code/qwen-code')
  b = @('@ampcode/cli', '@charmland/crush', '@continuedev/cli', '@factory/cli', 'cline',
    '@kilocode/cli', '@augmentcode/auggie', '@opencode/cli')
  c = @('codebuff', '@qoder-ai/qodercli', '@tencent-ai/codebuddy-code',
    '@letta-ai/letta-code', '@neovate/code', '@just-every/code', '@iflow-ai/iflow-cli')
  d = @()
}

# The Python agents of group d, for "uv tool install". uv puts their
# commands in %USERPROFILE%\.local\bin.
$uv = @('aider-chat', 'openhands', 'gptme', 'mistral-vibe')

function Add-ToPath([string]$Dir) {
  $env:PATH = "$Dir;$env:PATH"
  if ($env:GITHUB_PATH) { $Dir | Out-File -FilePath $env:GITHUB_PATH -Append -Encoding utf8 }
}

# Runs an install page in a child PowerShell, so that an "exit" in the page
# does not stop this script. An install page prints the real profile path,
# so its output goes through the scrub.
function Invoke-InstallPage([string]$Url) {
  $text = (& pwsh -NoProfile -Command "irm '$Url' | iex" 2>&1 | Out-String)
  $rc = $LASTEXITCODE
  [Console]::Out.Write((Invoke-Scrub $text $scrub.HomeDir $scrub.User $scrub.HostName).Text)
  return $rc
}

foreach ($p in $npm[$Group]) {
  Write-Output "::group::npm install -g $p"
  $text = (& npm install -g $p 2>&1 | Out-String)
  $rc = $LASTEXITCODE
  [Console]::Out.Write((Invoke-Scrub $text $scrub.HomeDir $scrub.User $scrub.HostName).Text)
  Write-Output '::endgroup::'
  Write-Output "install $p`: exit $rc"
}

function Install-Step([string]$Name, [scriptblock]$Body) {
  Write-Output "::group::$Name"
  $text = (& $Body 2>&1 | Out-String)
  $rc = $LASTEXITCODE
  [Console]::Out.Write((Invoke-Scrub $text $scrub.HomeDir $scrub.User $scrub.HostName).Text)
  Write-Output '::endgroup::'
  Write-Output "install $Name`: exit $rc"
}

if ($Group -eq 'a') {
  # The Windows installer of the Cursor CLI. It adds
  # %LOCALAPPDATA%\cursor-agent to the PATH of the user.
  Write-Output '::group::Cursor CLI'
  $rc = Invoke-InstallPage 'https://cursor.com/install?win32=true'
  Write-Output '::endgroup::'
  Write-Output "install Cursor CLI: exit $rc"
  Add-ToPath "$env:LOCALAPPDATA\cursor-agent"
} elseif ($Group -eq 'b') {
  Write-Output '::group::Kimi Code CLI'
  $rc = Invoke-InstallPage 'https://code.kimi.com/kimi-code/install.ps1'
  Write-Output '::endgroup::'
  Write-Output "install Kimi Code CLI: exit $rc"
  Add-ToPath "$HOME\.kimi-code\bin"
} elseif ($Group -eq 'c') {
  # The Windows installer of the Kiro CLI (https://kiro.dev/docs/cli/). It
  # installs an x64 MSI.
  Write-Output '::group::Kiro CLI'
  $rc = Invoke-InstallPage 'https://cli.kiro.dev/install.ps1'
  Write-Output '::endgroup::'
  Write-Output "install Kiro CLI: exit $rc"
  # The installer prints C:\Program Files\Kiro-Cli, but the MSI can put
  # kiro-cli.exe elsewhere. Look in the PATH that the MSI wrote to the
  # registry, then in the usual install folders.
  $dirs = @(([Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
      [Environment]::GetEnvironmentVariable('Path', 'User')) -split ';' | Where-Object { $_ })
  $kiro = $dirs | ForEach-Object { Join-Path $_ 'kiro-cli.exe' } | Where-Object { Test-Path -LiteralPath $_ } |
    Select-Object -First 1
  if (-not $kiro) {
    $roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, "$env:LOCALAPPDATA\Programs", $env:LOCALAPPDATA)
    $kiro = $roots | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | ForEach-Object {
      Get-ChildItem -LiteralPath $_ -Recurse -Depth 4 -Filter 'kiro-cli.exe' -ErrorAction SilentlyContinue
    } | Select-Object -First 1 -ExpandProperty FullName
  }
  if ($kiro) {
    $d = Split-Path -Parent $kiro
    $t = (Invoke-Scrub "Kiro CLI: kiro-cli.exe in $d" $scrub.HomeDir $scrub.User $scrub.HostName).Text
    Write-Output $t
    Add-ToPath $d
  } else {
    Write-Output 'Kiro CLI: no kiro-cli.exe in PATH or in the install folders'
  }
  # The Junie installer of the JetBrains/junie README. It puts the shim
  # junie.bat in %USERPROFILE%\.local\bin and the binary in
  # %USERPROFILE%\.local\share\junie.
  Write-Output '::group::Junie CLI'
  $rc = Invoke-InstallPage 'https://junie.jetbrains.com/install.ps1'
  Write-Output '::endgroup::'
  Write-Output "install Junie CLI: exit $rc"
  Add-ToPath "$HOME\.local\bin"
} else {
  foreach ($p in $uv) {
    Install-Step "uv tool install $p" { & uv tool install --python 3.12 $p }
  }
  Add-ToPath "$HOME\.local\bin"
  # The Goose script of the block/goose repository. It installs the x64
  # CLI to %USERPROFILE%\.local\bin and stops on arm64.
  Write-Output '::group::Goose'
  $env:CONFIGURE = 'false'
  $rc = Invoke-InstallPage 'https://raw.githubusercontent.com/block/goose/main/download_cli.ps1'
  Write-Output '::endgroup::'
  Write-Output "install Goose: exit $rc"
  # The installer of the Rust Open Interpreter (its README). It installs to
  # %LOCALAPPDATA%\Programs\Open Interpreter\bin.
  Write-Output '::group::Open Interpreter'
  $rc = Invoke-InstallPage 'https://www.openinterpreter.com/install.ps1'
  Write-Output '::endgroup::'
  Write-Output "install Open Interpreter: exit $rc"
  Add-ToPath "$env:LOCALAPPDATA\Programs\Open Interpreter\bin"
}
exit 0
