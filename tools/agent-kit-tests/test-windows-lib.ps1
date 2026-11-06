# The helpers of probes/agent/lib.ps1 on Windows: pids, the time limit of a
# process tree, the arguments, the backends and the literal scrub.
. (Join-Path $env:ROOT 'tools/agent-kit-tests/lib.ps1')
. (Join-Path $env:ROOT 'probes/agent/lib.ps1')
$ErrorActionPreference = 'Stop'
function Expect-True([string]$Name, [bool]$Got, [string]$Why) {
    if ($Got) { Pass $Name } else { Fail $Name $Why }
}

$run = Join-Path $T 'run'
New-Item -ItemType Directory -Path $run | Out-Null

# A pid is ours only with its start time.
Add-KitPid $run $PID 'self'
Expect-True 'a recorded pid is ours' (Test-KitPidOurs $run $PID) 'not ours'
Set-Content -LiteralPath (Join-Path $run "pids\$PID") -Value "self`t1"
Expect-True 'a reused pid is not ours' (-not (Test-KitPidOurs $run $PID)) 'ours'
Set-Content -LiteralPath (Join-Path $run "pids\$PID") -Value 'self'
Expect-True 'a pid with no start time is not ours' (-not (Test-KitPidOurs $run $PID)) 'ours'
Expect-True 'a pid with no file is not ours' (-not (Test-KitPidOurs $run 4)) 'ours'

# At the time limit, Wait-KitProcess stops the process and its child, and
# says so in TimedOut.
$p = Start-KitProcess $run 'tree' (Join-Path $env:SystemRoot 'System32\cmd.exe') '/d /c ping -n 60 127.0.0.1' (Join-Path $T 'o') (Join-Path $T 'e') $T
$kids = @()
for ($i = 0; $i -lt 40 -and $kids.Count -eq 0; $i++) {
    Start-Sleep -Milliseconds 250
    $kids = @(Get-KitDescendants $p)
}
Expect-True 'the tree has a child' ($kids.Count -gt 0) 'no child of cmd.exe'
$pidLine = [string](Get-Content -LiteralPath (Join-Path $run "pids\$($p.Id)") -TotalCount 1)
Expect-True 'Start-KitProcess writes the start time' ($pidLine -match "^tree`t[0-9]+$") $pidLine
$w = Wait-KitProcess $run $p 1
Expect-True 'the wait says TimedOut' ([bool]$w.TimedOut) 'not timed out'
Start-Sleep -Milliseconds 500
$left = @($kids | Where-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue })
Expect-True 'the tree is stopped' ($p.HasExited -and $left.Count -eq 0) "$($left.Count) children run"
Expect-True 'the pid file is deleted' (-not (Test-Path -LiteralPath (Join-Path $run "pids\$($p.Id)"))) 'the pid file is there'
$p = Start-KitProcess $run 'quick' (Join-Path $env:SystemRoot 'System32\cmd.exe') '/d /c exit 3' (Join-Path $T 'o2') (Join-Path $T 'e2') $T
$w = Wait-KitProcess $run $p 30
Expect-True 'a quick process gives its exit code' ((-not $w.TimedOut) -and $w.Code -eq 3) "code $($w.Code)"

# Get-KitArgs undoes the splat of kit.ps1.
[string[]]$a = @(Get-KitArgs @($null))
Expect-True 'no arguments from one null' ($a.Count -eq 0) "$($a.Count) arguments"
[string[]]$a = @(Get-KitArgs @([char]'a', [char]'@', [char]'b'))
Expect-True 'characters make one argument' ($a.Count -eq 1 -and $a[0] -eq 'a@b') ($a -join '|')
[string[]]$a = @(Get-KitArgs @('--home', 'real'))
Expect-True 'two arguments stay' ($a.Count -eq 2 -and $a[1] -eq 'real') ($a -join '|')

# The backends of a step line on Windows.
$s = New-Object PSObject -Property @{ name = 'x'; kind = 'first-run'; backends = 'tmux,conpty' }
Expect-True 'tmux,conpty gives conpty' ((@(Get-KitStepBackends $s) -join ',') -eq 'conpty') (@(Get-KitStepBackends $s) -join ',')
$s = New-Object PSObject -Property @{ name = 'x'; kind = 'probe'; backends = '-' }
Expect-True 'a dash gives none' ((@(Get-KitStepBackends $s) -join ',') -eq 'none') (@(Get-KitStepBackends $s) -join ',')
$s = New-Object PSObject -Property @{ name = 'x'; kind = 'probe'; backends = '-'; windows = 'no' }
Expect-True 'windows=no hides the line' (@(Get-KitStepBackends $s).Count -eq 0) 'not hidden'

# The literal scrub: the kit folder and a OneDrive folder with a space.
$env:OneDrive = 'C:\Users\example-user\OneDrive - Contoso'
$x = ConvertTo-KitScrubbed ("a $script:KitRoot\probes b`nc $env:OneDrive\doc.txt d`n")
Expect-True 'the kit folder changes to <kit>' ($x -match '(?m)^a <kit>\\probes b$') $x
Expect-True 'a OneDrive folder changes to <onedrive>' ($x -match '(?m)^c <onedrive>\\doc\.txt d$') $x

# Explicit entries of wide groups, as a new folder in RUNNER_TEMP has them
# on windows-11-arm. The kit removes them and keeps the other entries.
function New-WideFolder([string]$Name) {
    $d = Join-Path $T $Name
    New-Item -ItemType Directory -Path $d | Out-Null
    $null = & icacls.exe $d /grant '*S-1-5-11:(OI)(CI)M' '*S-1-5-32-545:(OI)(CI)M' '*S-1-5-32-544:(OI)(CI)F' 2>&1
    return $d
}
function Get-AclSids([string]$Dir) {
    @((Get-Acl -LiteralPath $Dir).GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]) | ForEach-Object { [string]$_.IdentityReference.Value })
}
$me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$d = New-WideFolder 'wide-set'
Expect-True 'Set-KitPrivate exits 0' ((Set-KitPrivate $d) -eq 0) 'icacls failed'
$sids = @(Get-AclSids $d)
Expect-True 'Set-KitPrivate removes Authenticated Users' ($sids -notcontains 'S-1-5-11') ($sids -join ' ')
Expect-True 'Set-KitPrivate removes Users' ($sids -notcontains 'S-1-5-32-545') ($sids -join ' ')
Expect-True 'Set-KitPrivate keeps this account' ($sids -contains $me) ($sids -join ' ')
Expect-True 'Set-KitPrivate keeps SYSTEM' ($sids -contains 'S-1-5-18') ($sids -join ' ')
Expect-True 'Set-KitPrivate keeps Administrators' ($sids -contains 'S-1-5-32-544') ($sids -join ' ')
$d = New-WideFolder 'wide-hint'
$hint = Get-KitPrivateCommand $d
Expect-True 'the hint removes the wide groups' ($hint -match '/remove:g \*S-1-1-0 ') $hint
# The operator pastes the hint into PowerShell.
$null = Invoke-Expression $hint
$sids = @(Get-AclSids $d)
Expect-True 'the hint works' ($sids -notcontains 'S-1-5-11' -and $sids -notcontains 'S-1-5-32-545' -and $sids -contains $me) ($sids -join ' ')

Complete-Tests
