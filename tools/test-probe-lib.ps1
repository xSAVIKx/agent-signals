# Test the helpers of probes\lib.ps1 that hide names and paths.
# It uses the files in tools\testdata\probe-lib. They hold synthetic names.
# Usage: powershell -NoProfile -File tools\test-probe-lib.ps1
# Exit status: 0 when all checks pass, 1 when a check fails.

$here = $PSScriptRoot
. (Join-Path (Split-Path -Parent $here) 'probes\lib.ps1')
$data = Join-Path $here 'testdata\probe-lib'
$script:Failed = 0

function Test-Same([string]$Name, [string[]]$Want, [string[]]$Got) {
  $w = ($Want -join "`n")
  $g = ($Got -join "`n")
  if ($w -ceq $g) { Write-Output "pass: $Name"; return }
  $script:Failed++
  Write-Output "fail: $Name"
  Write-Output '--- want'
  Write-Output $w
  Write-Output '--- got'
  Write-Output $g
}

# 1. TOML table names. The expected file is the same for toml_tables of
# lib.sh.
$want = @([IO.File]::ReadAllLines((Join-Path $data 'toml-tables.txt')))
$got = @(Get-TomlTables (Join-Path $data 'config.toml'))
Test-Same 'Get-TomlTables hides paths and names' $want $got

# 2. JSON shape: the keys of enabledPlugins and mcpServers, and a key with
# a path in it, show as <name>.
$got = @(Get-JsonShape (Join-Path $data 'settings.json') 2)
$want = @(
  '(top): object',
  'enabledPlugins: object',
  'enabledPlugins.<name> count: 2',
  'enabledPlugins.<name>: bool',
  'mcpServers: object',
  'mcpServers.<name> count: 1',
  'mcpServers.<name>: object',
  'permissions: object',
  'permissions.allow: array[0]',
  'permissions.deny: array[0]',
  'env: object',
  'env.FOO: string',
  'env.<name> count: 1',
  'env.<name>: string',
  'model: string'
)
Test-Same 'Get-JsonShape hides names' $want $got

# 3. A process line: words that are not flags and hold no path separator
# become <arg>, also inside a quoted -Command text, and the line has at
# most 240 characters.
$long = 'pwsh.exe -NoLogo -NoProfile -NoExit -Command "Set-Location shop; function Global:claude { & C:\tools\claude.exe @args }' + (' x' * 300) + '"'
$p = New-Object PSObject -Property @{
  ProcessId = 10; ParentProcessId = 1; CreationDate = $null; Name = 'pwsh.exe'; CommandLine = $long
}
$line = Format-ProcessLine $p
$prefix = 'pid=10 ppid=1 start=unknown name=pwsh.exe cmd: pwsh.exe -NoLogo -NoProfile -NoExit -Command "<arg> <arg> <arg> <arg> <arg> <arg> C:\tools\claude.exe <arg> <arg> <arg>'
Test-Same 'Format-ProcessLine hides words' @('True') @([string]$line.StartsWith($prefix))
Test-Same 'Format-ProcessLine has at most 240 characters' @('240') @([string]$line.Length)

# 4. The agent match uses the process name, the executable path, or the
# script of node. Command-line text of a shell does not count.
$pattern = '(?i)(^|[\\/ "])claude(\.exe|\.cmd)?("|\s|$)|@anthropic-ai[\\/]claude-code'
$shell = New-Object PSObject -Property @{ Name = 'pwsh.exe'; ExecutablePath = 'C:\Program Files\PowerShell\7\pwsh.exe'; CommandLine = $long }
$exe = New-Object PSObject -Property @{ Name = 'claude.exe'; ExecutablePath = 'C:\Users\alice\.local\bin\claude.exe'; CommandLine = 'claude.exe --resume' }
$node = New-Object PSObject -Property @{ Name = 'node.exe'; ExecutablePath = 'C:\Program Files\nodejs\node.exe'; CommandLine = '"C:\Program Files\nodejs\node.exe" --no-warnings C:\Users\alice\AppData\Roaming\npm\node_modules\@anthropic-ai\claude-code\cli.js' }
$other = New-Object PSObject -Property @{ Name = 'node.exe'; ExecutablePath = 'C:\Program Files\nodejs\node.exe'; CommandLine = 'node.exe C:\work\shop\server.js claude' }
$got = @(
  [string](Test-AgentProcess $shell $pattern),
  [string](Test-AgentProcess $exe $pattern),
  [string](Test-AgentProcess $node $pattern),
  [string](Test-AgentProcess $other $pattern)
)
Test-Same 'Test-AgentProcess: shell no, exe yes, node script yes, other node no' @('False', 'True', 'True', 'False') $got

# 5. The form of a project key, and the folders that hold many tools.
$got = @(
  (Get-KeyForm 'D--Projects-shop'),
  (Get-KeyForm 'C-Users-alice-shop'),
  (Get-KeyForm '-srv-work-shop'),
  (Get-KeyForm 'shop'),
  [string](Test-SharedBin 'C:\Users\alice\.local\bin'),
  [string](Test-SharedBin 'C:\Users\alice\AppData\Roaming\npm'),
  [string](Test-SharedBin 'C:\Users\alice\.local\share\claude')
)
Test-Same 'Get-KeyForm and Test-SharedBin' @('<drive>--<path>', '<drive>-<path>', '-work-example', '<other>', 'True', 'True', 'False') $got

# 6. The layout of a projects folder shows a count and a key form, and a
# filter keeps only the names of the agent.
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('probe-lib-' + [guid]::NewGuid().ToString('N'))
try {
  New-Item -ItemType Directory -Path (Join-Path $tmp 'state\projects\D--Projects-shop') -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $tmp 'state\projects\D--Projects-acme') -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $tmp 'bin') -Force | Out-Null
  foreach ($f in 'claude.exe', 'other-tool.exe') { Set-Content -LiteralPath (Join-Path $tmp "bin\$f") -Value 'x' }
  $layout = @(Get-Layout (Join-Path $tmp 'state') 2) -join "`n"
  $ok = ($layout -match 'project folders: 2 \(names not shown\)') -and ($layout -match 'key form <drive>--<path>') -and ($layout -notmatch 'shop|acme')
  Test-Same 'Get-Layout hides the names of project folders' @('True') @([string]$ok)
  $bin = @(Get-Layout (Join-Path $tmp 'bin') 1 @('claude*')) -join "`n"
  $ok = ($bin -match 'claude\.exe') -and ($bin -notmatch 'other-tool')
  Test-Same 'Get-Layout with a filter lists only the agent files' @('True') @([string]$ok)
  $plain = Join-Path $tmp 'bin\claude.exe'
  Test-Same 'Get-LinkType of a plain file' @('none') @(Get-LinkType $plain)
  Test-Same 'Get-LinkType of a missing file' @('not found') @(Get-LinkType (Join-Path $tmp 'bin\missing.exe'))
  $link = Join-Path $tmp 'bin\codex.exe'
  $made = $true
  try { New-Item -ItemType SymbolicLink -Path $link -Target $plain -ErrorAction Stop | Out-Null } catch { $made = $false }
  if ($made) {
    Test-Same 'Get-LinkType of a symbolic link' @('SymbolicLink') @(Get-LinkType $link)
  } else {
    Write-Output 'skip: Get-LinkType of a symbolic link: this user cannot make a symbolic link'
  }
} finally {
  Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:Failed -gt 0) { Write-Output "test-probe-lib: $($script:Failed) checks fail"; exit 1 }
Write-Output 'test-probe-lib: pass'
exit 0
