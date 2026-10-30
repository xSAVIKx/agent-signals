# Scrub probe output before a person sends it or a fact uses it.
# It makes the same changes as the Unix scrub, in the same order.
#
# Usage:
#   powershell -NoProfile -File tools\scrub.ps1 [-Path file]
# With no -Path, it reads the text from stdin. It writes the scrubbed text
# to stdout and one line "scrub: <count> <kind>" for each kind to stderr.
#
# The environment can set the values to remove:
#   SCRUB_HOME  the home folder (default: $HOME)
#   SCRUB_USER  the account name (default: USERNAME or USER)
#   SCRUB_HOST  the host name (default: the DNS host name)
#
# The changes, in this order:
#   1. home       the home folder -> ~
#   2. other-home /Users/<name>, /home/<name>, C:\Users\<name> -> ~
#   3. project    a project path below ~, /srv/ or /work/<name> -> /work/example
#   4. key        a project key such as -Users-alice-code-shop -> -work-example
#   5. user       the account name as a whole word -> dev
#   6. host       the host name and its short form as whole words -> host
#   7. uuid       UUIDs -> <uuid>
#   8. hex        hex runs of 16 or more characters -> <hex>
#   9. email      e-mail addresses -> <email>
#  10. ip         IPv4 addresses -> <ip>, but not 127.0.0.1 and 0.0.0.0
#
# Other scripts can dot-source this file to get Invoke-Scrub. Then the file
# does not read stdin.

param([string]$Path)

$script:ScrubKinds = @('home', 'other-home', 'project', 'key', 'user', 'host', 'uuid', 'hex', 'email', 'ip')

# A path ends at white space, a quote, a colon, a comma, a semicolon or a
# parenthesis.
$script:PathChars = '[^\s"'':,;()]'

function Invoke-ScrubReplace([string]$Text, [string]$Pattern, [scriptblock]$Change, [hashtable]$Counts, [string]$Kind) {
  $evaluator = [System.Text.RegularExpressions.MatchEvaluator] {
    param($m)
    $new = & $Change $m
    if ($new -cne $m.Value) { $Counts[$Kind] = 1 + $Counts[$Kind] }
    return $new
  }
  return [regex]::Replace($Text, $Pattern, $evaluator)
}

# Changes the folders of a project path to /work/example. The folders up to
# the first hidden folder that is not the first folder go. The rest stays.
function Convert-ProjectPath([string]$Rest, [string]$Original, [string[]]$Keep) {
  $parts = [regex]::Split($Rest, '([/\\]+)')
  $first = $parts[0]
  if (-not $first -or $first.StartsWith('.') -or ($Keep -ccontains $first)) { return $Original }
  for ($i = 2; $i -lt $parts.Count; $i += 2) {
    if ($parts[$i].StartsWith('.')) {
      return '/work/example' + (($parts[($i - 1)..($parts.Count - 1)]) -join '')
    }
  }
  return '/work/example'
}

function Get-WordPattern([string]$Word) {
  # A whole word: no letter, digit, "_", "-" or "." next to it. A "." at the
  # end of a sentence is not part of the word.
  return '(?<![A-Za-z0-9_.-])' + [regex]::Escape($Word) + '(?![A-Za-z0-9_-])(?!\.[A-Za-z0-9_])'
}

function Invoke-Scrub([string]$Text, [string]$HomeDir, [string]$User, [string]$HostName) {
  $counts = @{}
  foreach ($k in $script:ScrubKinds) { $counts[$k] = 0 }
  $pc = $script:PathChars
  $s = $Text

  # 1. The home folder. A Windows home folder matches in any case and with
  # one or more slashes or backslashes between its parts.
  if ($HomeDir) {
    $h = $HomeDir.TrimEnd('/', '\')
    if ($h) {
      if ($h -match '^[A-Za-z]:') {
        $parts = @($h -split '[\\/]+' | ForEach-Object { [regex]::Escape($_) })
        $pat = '(?i)(?<![A-Za-z0-9_.-])' + ($parts -join '[\\/]+') + '(?![A-Za-z0-9._-])'
      } else {
        $pat = '(?<![A-Za-z0-9_.~-])' + [regex]::Escape($h) + '(?![A-Za-z0-9._-])'
      }
      $s = Invoke-ScrubReplace $s $pat { '~' } $counts 'home'
    }
  }

  # 2. Other home folders.
  $s = Invoke-ScrubReplace $s ('(?<![A-Za-z0-9_.~-])/(?:Users|home)/[^/\\\s"'':,;()]+') { '~' } $counts 'other-home'
  $s = Invoke-ScrubReplace $s ('(?i)(?<![A-Za-z0-9_.-])[A-Z]:[\\/]+Users[\\/]+[^/\\\s"'':,;()]+') { '~' } $counts 'other-home'

  # 3. Project paths.
  $keep = @('Library', 'AppData', 'Applications')
  $s = Invoke-ScrubReplace $s ('(?<![A-Za-z0-9_.~-])~[/\\]+(' + $pc + '+)') {
    param($m) Convert-ProjectPath $m.Groups[1].Value $m.Value $keep
  } $counts 'project'
  $s = Invoke-ScrubReplace $s ('(?<![A-Za-z0-9_.~/\\-])/srv/(' + $pc + '+)') {
    param($m) Convert-ProjectPath $m.Groups[1].Value $m.Value @()
  } $counts 'project'
  $s = Invoke-ScrubReplace $s ('(?<![A-Za-z0-9_.~/\\-])/work/(' + $pc + '+)') {
    param($m)
    $first = ([regex]::Split($m.Groups[1].Value, '[/\\]+'))[0]
    if ($first -ceq 'example') { $m.Value } else { Convert-ProjectPath $m.Groups[1].Value $m.Value @() }
  } $counts 'project'

  # 4. Project keys. The Windows form starts with a drive letter, for
  # example C--Users-alice-code-shop.
  $s = Invoke-ScrubReplace $s '(?m)(^|[/\\ "])-?(?:srv|Users|home|var-lib|work)-[A-Za-z0-9._-]+' {
    param($m) $m.Groups[1].Value + '-work-example'
  } $counts 'key'
  $s = Invoke-ScrubReplace $s '(?m)(^|[/\\ "])[A-Za-z]--(?:srv|Users|home|work)-[A-Za-z0-9._-]+' {
    param($m) $m.Groups[1].Value + '-work-example'
  } $counts 'key'

  # 5. The account name.
  if ($User) {
    $s = Invoke-ScrubReplace $s ('(?i)' + (Get-WordPattern $User)) { 'dev' } $counts 'user'
  }

  # 6. The host name, then its short form.
  if ($HostName) {
    $names = @($HostName)
    $short = $HostName.Split('.')[0]
    if ($short -and $short -ne $HostName) { $names += $short }
    foreach ($n in $names) {
      $s = Invoke-ScrubReplace $s ('(?i)' + (Get-WordPattern $n)) { 'host' } $counts 'host'
    }
  }

  # 7. UUIDs.
  $s = Invoke-ScrubReplace $s '(?i)(?<![0-9a-z])[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(?![0-9a-z])' { '<uuid>' } $counts 'uuid'

  # 8. Long hex runs.
  $s = Invoke-ScrubReplace $s '(?i)(?<![0-9a-z])[0-9a-f]{16,}(?![0-9a-z])' { '<hex>' } $counts 'hex'

  # 9. E-mail addresses.
  $s = Invoke-ScrubReplace $s '[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}' { '<email>' } $counts 'email'

  # 10. IPv4 addresses.
  $s = Invoke-ScrubReplace $s '(?<![0-9.])(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?![0-9])(?!\.[0-9])' {
    param($m)
    if ($m.Value -eq '127.0.0.1' -or $m.Value -eq '0.0.0.0') { $m.Value } else { '<ip>' }
  } $counts 'ip'

  return New-Object PSObject -Property @{ Text = $s; Counts = $counts }
}

function Get-ScrubDefaults {
  $h = $env:SCRUB_HOME
  if (-not $h) { $h = $HOME }
  $u = $env:SCRUB_USER
  if (-not $u) { $u = $env:USERNAME }
  if (-not $u) { $u = $env:USER }
  $n = $env:SCRUB_HOST
  if (-not $n) { try { $n = [System.Net.Dns]::GetHostName() } catch { $n = $env:COMPUTERNAME } }
  return New-Object PSObject -Property @{ HomeDir = $h; User = $u; HostName = $n }
}

# Stop here when another script dot-sources this file.
if ($MyInvocation.InvocationName -eq '.') { return }

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding $false
if ($Path) {
  $full = (Resolve-Path -LiteralPath $Path).ProviderPath
  $text = [IO.File]::ReadAllText($full, $utf8)
} else {
  $reader = New-Object System.IO.StreamReader ([Console]::OpenStandardInput()), $utf8
  $text = $reader.ReadToEnd()
}

$d = Get-ScrubDefaults
$r = Invoke-Scrub $text $d.HomeDir $d.User $d.HostName

$bytes = $utf8.GetBytes($r.Text)
$out = [Console]::OpenStandardOutput()
$out.Write($bytes, 0, $bytes.Length)
$out.Flush()
foreach ($k in $script:ScrubKinds) {
  [Console]::Error.WriteLine(('scrub: {0} {1}' -f $r.Counts[$k], $k))
}
exit 0
