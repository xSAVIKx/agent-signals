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
#   SCRUB_EXTRA more roots, one on each line, for example the run folder
#               of the agent kit. The values of OneDrive,
#               OneDriveCommercial and OneDriveConsumer are roots too.
#   SCRUB_DOMAIN the domain of the account (default: USERDOMAIN, when it
#               is not the host name)
#
# The changes, in this order:
#   W. wrap       a path that an agent wrapped onto the next screen lines:
#                 its line ends move to just after the path, so that the
#                 rules below see the full path. The line count stays.
#                 See Invoke-ScrubUnwrap.
#   0. extra     each extra root, the longest first -> /work/example
#   1. home       the home folder -> ~
#   2. other-home /Users/<name>, /home/<name>, C:\Users\<name> -> ~
#   3. project    a project path below ~, /srv/ or /work/<name>, or a drive
#                 path such as D:\Projects\shop -> /work/example. C:\Windows,
#                 C:\Program Files and C:\ProgramData stay.
#   3a. sid       a Windows account SID, S-1-5-21-... -> <sid>. The
#                 well-known SIDs stay.
#   4. key        a project key such as -Users-alice-code-shop,
#                 D--Projects-shop or C-Users-alice-shop -> -work-example
#   5. user       the account name as a whole word -> dev
#   6. domain     the domain as a whole word -> domain
#      host       the host name and its short form as whole words -> host
#   7. secret     API keys and tokens -> <secret>: sk-ant-, sk-proj-, AIza,
#                 gh[pousr]_, github_pat_, glpat-, xox[abprs]- with 16 or
#                 more key characters; sk- with 16 or more and a digit;
#                 AKIA with 16 upper-case letters or digits; key_ with 32
#                 or more hex characters (Cursor); a JWT. A letter, a digit
#                 or a "-" must not come just before it.
#   8. uuid       UUIDs -> <uuid>
#   9. hex        hex runs of 16 or more characters -> <hex>
#  10. email      e-mail addresses -> <email>
#  11. ip         IPv4 addresses -> <ip>, but not 127.0.0.1 and 0.0.0.0, and
#                 not a version number (after v or version, or before a
#                 letter, - or +)
#
# A path can hold spaces. After a space, a word that holds a / or a \ and
# does not start a new path continues the path. So
# ~/My Projects/Client Acme/a.go is one path. A last folder with a space
# and no / after it ends the path at the space, except in quotes: a path
# just after a " goes to the next ".
#
# Other scripts can dot-source this file to get Invoke-Scrub. Then the file
# does not read stdin.

param([string]$Path)

$script:ScrubKinds = @('wrap', 'extra', 'home', 'other-home', 'project', 'temp', 'sid', 'key', 'user', 'domain', 'host', 'secret', 'uuid', 'hex', 'email', 'ip')

# A path ends at white space, a quote, a colon, a comma, a semicolon or a
# parenthesis.
$script:PathChars = '[^\s"'':,;()]'
# The words after a path that continue it: a space, then a word that does
# not start a new path and holds a / or a \.
$script:PathMore = '(?:\x20(?![/\\~])[^\s"'':,;()/\\]+[/\\][^\s"'':,;()]*)*'

# Get-RootPattern ROOT: a pattern for the folder ROOT. A Windows folder
# matches in any case and with one or more slashes or backslashes between
# its parts.
function Get-RootPattern([string]$Root) {
  if ($Root -match '^[A-Za-z]:') {
    $parts = @($Root -split '[\\/]+' | ForEach-Object { [regex]::Escape($_) })
    return '(?i)(?<![A-Za-z0-9_.-])' + ($parts -join '[\\/]+') + '(?![A-Za-z0-9._-])'
  }
  return '(?<![A-Za-z0-9_.~-])' + [regex]::Escape($Root) + '(?![A-Za-z0-9._-])'
}

# A character of a path in a wrapped path (Invoke-ScrubUnwrap).
$script:WrapChar = '[^ \t\r\n"'':,;()]'
# A line end after a character that is not white space, and the white
# space at the start of the next line. This white space can hold one box
# line (U+2502), as in the command box of Claude Code.
$script:WrapBreak = '(?<![ \t])\r?\n(?:[ \t]*\u2502)?[ \t]+'

# Test-ScrubMore J TEXT AT: $true when the path J continues after the line
# end at AT in TEXT: J ends with / or \, or the first word of the next line
# holds a / or a \. A word that fills its line can be a part of the path
# too: then the next line decides.
function Test-ScrubMore([string]$J, [string]$Text, [int]$At) {
  $nl = New-Object System.Text.RegularExpressions.Regex ('\G' + $script:WrapBreak + '(?=' + $script:WrapChar + ')')
  $word = New-Object System.Text.RegularExpressions.Regex ('\G' + $script:WrapChar + '*')
  while ($true) {
    $b = $nl.Match($Text, $At)
    if (-not $b.Success) { return $false }
    $w = $word.Match($Text, $b.Index + $b.Length)
    if ($J -match '[/\\]$' -or $w.Value -match '[/\\]') { return $true }
    $J = $w.Value
    $At = $w.Index + $w.Length
  }
}

# Invoke-ScrubUnwrap TEXT ANCHORS COUNTS: an agent can wrap a long path
# onto the next screen lines, so a line holds only a part of it. Then no
# rule sees the full path. This function moves the line ends from a
# wrapped path to just after it, so that the full path is on its first
# line. Each line end and the line count stay. A path is wrapped when:
#   - an anchor is cut by one or more line ends: each of ANCHORS, then
#     /Users/, /home/, ~/, /srv/ and /work/, or
#   - the path after an anchor goes to the end of the line, and the path
#     ends with / or \ or the first word of the next line holds a / or a
#     \. A word that fills its line can be a part of the path too: then
#     the next line decides.
# The line after a line end starts with white space ($script:WrapBreak).
# A Windows root (a drive letter) matches in any case, and each / or \ in
# it matches one or more of / and \. tools/scrub.sh does the same.
function Invoke-ScrubUnwrap([string]$Text, [string[]]$Anchors, [hashtable]$Counts) {
  $s = $Text
  $word = New-Object System.Text.RegularExpressions.Regex ('\G' + $script:WrapChar + '*')
  $nl = New-Object System.Text.RegularExpressions.Regex ('\G' + $script:WrapBreak)
  foreach ($a in @($Anchors) + @('/Users/', '/home/', '~/', '/srv/', '/work/')) {
    if (-not $a -or $a.Length -le 1) { continue }
    $win = $a -match '^[A-Za-z]:'
    $parts = @(foreach ($c in $a.ToCharArray()) {
        if ($win -and ($c -eq [char]'\' -or $c -eq [char]'/')) { '[\\/]+' } else { [regex]::Escape([string]$c) }
      })
    $pat = '(?<![A-Za-z0-9_.~-])' + ($parts -join ('(?:' + $script:WrapBreak + ')?'))
    $opt = [System.Text.RegularExpressions.RegexOptions]::None
    if ($win) { $opt = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase }
    $re = New-Object System.Text.RegularExpressions.Regex ($pat, $opt)
    $pos = 0
    while ($pos -le $s.Length) {
      $m = $re.Match($s, $pos)
      if (-not $m.Success) { break }
      # The anchor without its line ends.
      $breaks = New-Object System.Collections.Generic.List[string]
      $j = ''
      $last = 0
      foreach ($x in [regex]::Matches($m.Value, $script:WrapBreak)) {
        $j += $m.Value.Substring($last, $x.Index - $last)
        $breaks.Add($x.Value)
        $last = $x.Index + $x.Length
      }
      $j += $m.Value.Substring($last)
      # The rest of the path, also on the next lines.
      $end = $m.Index + $m.Length
      while ($true) {
        $w = $word.Match($s, $end)
        $j += $w.Value
        $end += $w.Length
        if (-not (Test-ScrubMore $j $s $end)) { break }
        $b = $nl.Match($s, $end)
        $breaks.Add($b.Value)
        $end += $b.Length
      }
      if ($breaks.Count -eq 0) { $pos = $m.Index + $m.Length; continue }
      # A line end that is not the last one keeps no white space after
      # it, so that its line stays empty.
      $new = $j
      for ($k = 0; $k -lt $breaks.Count - 1; $k++) { $new += ($breaks[$k] -replace '[ \t]+\z', '') }
      $new += $breaks[$breaks.Count - 1]
      $s = $s.Substring(0, $m.Index) + $new + $s.Substring($end)
      $pos = $m.Index + $new.Length
      $Counts['wrap'] = 1 + $Counts['wrap']
    }
  }
  return $s
}

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

function Invoke-Scrub([string]$Text, [string]$HomeDir, [string]$User, [string]$HostName, [string[]]$Extra = @(), [string]$Domain = '') {
  $counts = @{}
  foreach ($k in $script:ScrubKinds) { $counts[$k] = 0 }
  $pc = $script:PathChars
  $more = $script:PathMore
  # A path after <sandbox> is below a throwaway folder of a scenario. Its home
  # is <sandbox>/home/, and no home rule may read the next word as an account
  # name. So the / after <sandbox> is @S@ until all rules are done.
  $s = $Text.Replace('<sandbox>/', '<sandbox>@S@')
  # A caller with four arguments gets the extra roots and the domain of the
  # environment.
  if (-not $PSBoundParameters.ContainsKey('Extra') -or -not $PSBoundParameters.ContainsKey('Domain')) {
    $dd = Get-ScrubDefaults
    if (-not $PSBoundParameters.ContainsKey('Extra')) { $Extra = $dd.Extra }
    if (-not $PSBoundParameters.ContainsKey('Domain')) { $Domain = $dd.Domain }
  }

  # 0. The extra roots, the longest first.
  $roots = @($Extra | Where-Object { $_ -and $_.TrimEnd('/', '\').Length -gt 1 } | ForEach-Object { $_.TrimEnd('/', '\') } | Sort-Object -Property Length -Descending)
  # A wrapped path: its line ends move to just after it, so that the rules
  # below see the full path.
  $s = Invoke-ScrubUnwrap $s (@($roots) + @($HomeDir)) $counts
  foreach ($r in $roots) {
    $s = Invoke-ScrubReplace $s (Get-RootPattern $r) { '/work/example' } $counts 'extra'
  }

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

  # 3. Project paths. The first pass takes a path just after a quote, up
  # to the next quote, so that it can hold spaces. The second pass takes
  # the other paths.
  $keep = @('Library', 'AppData', 'Applications')
  # A Windows drive path that is not below a home folder, for example
  # D:\Projects\shop. A \\?\ prefix goes with it. The system folders
  # C:\Windows, C:\Program Files, C:\Program Files (x86) and C:\ProgramData
  # stay. A path ends at white space before a word with no slash, so
  # "Program Files (x86)" shows as "Program".
  $system = @('windows', 'program', 'program files', 'programdata', 'progra~1', 'progra~2')
  foreach ($quoted in @($true, $false)) {
    if ($quoted) {
      $lb1 = '(?<=")'; $lb2 = '(?<=")'; $grp = '([^"\r\n]+)(?=")'
    } else {
      $lb1 = '(?<![A-Za-z0-9_.~-])'; $lb2 = '(?<![A-Za-z0-9_.~/\\-])'; $grp = '(' + $pc + '+' + $more + ')'
    }
    $s = Invoke-ScrubReplace $s ($lb1 + '~[/\\]+' + $grp) {
      param($m) Convert-ProjectPath $m.Groups[1].Value $m.Value $keep
    } $counts 'project'
    $s = Invoke-ScrubReplace $s ($lb2 + '/srv/' + $grp) {
      param($m) Convert-ProjectPath $m.Groups[1].Value $m.Value @()
    } $counts 'project'
    $s = Invoke-ScrubReplace $s ($lb2 + '/work/' + $grp) {
      param($m)
      $first = ([regex]::Split($m.Groups[1].Value, '[/\\]+'))[0]
      if ($first -ceq 'example') { $m.Value } else { Convert-ProjectPath $m.Groups[1].Value $m.Value @() }
    } $counts 'project'
    $s = Invoke-ScrubReplace $s ($lb1 + '(?:\\+\?\\*)?[A-Za-z]:[\\/]+' + $grp) {
      param($m)
      $first = ([regex]::Split($m.Groups[1].Value, '[/\\]+'))[0]
      if ($system -contains $first.ToLowerInvariant()) { $m.Value } else { Convert-ProjectPath $m.Groups[1].Value $m.Value @() }
    } $counts 'project'
  }

  # 3b. The temporary folders of Claude Code and Cursor hold the account
  # number or a run name.
  $s = Invoke-ScrubReplace $s '/tmp/claude-[A-Za-z0-9._-]+' { '/tmp/claude-example' } $counts 'temp'
  $s = Invoke-ScrubReplace $s '/tmp/cursor-agent-logs-[0-9]+' { '/tmp/cursor-agent-logs-example' } $counts 'temp'

  # 3a. Windows account SIDs. This rule comes before the project keys,
  # because a project key also matches a bare SID.
  $s = Invoke-ScrubReplace $s 'S-1-5-21(?:-[0-9]+){3,4}' { '<sid>' } $counts 'sid'

  # 4. Project keys. The Windows form starts with a drive
  # letter and one or two dashes: Claude D--Projects-shop, Cursor
  # C-Users-alice-shop. The token after the drive letter must hold one more
  # dash, so that a word such as X-ray stays.
  $s = Invoke-ScrubReplace $s '(?m)(^|[/\\ "])-?(?:srv|Users|home|var-lib|work)-[A-Za-z0-9._-]+' {
    param($m) $m.Groups[1].Value + '-work-example'
  } $counts 'key'
  $s = Invoke-ScrubReplace $s '(?m)(^|[/\\ "])(?:[A-Z]-|[A-Za-z]--)[A-Za-z0-9._]+-[A-Za-z0-9._-]+' {
    param($m) $m.Groups[1].Value + '-work-example'
  } $counts 'key'

  # A key on another root: the key form of each extra root and of the
  # current folder (one or more dashes for each run of other characters),
  # and each key in a "projects" folder. A key with one word needs its dash.
  foreach ($r in @($roots) + @((Get-Location).Path)) {
    $k = ([regex]::Replace($r, '[^A-Za-z0-9]+', '-')).Trim('-')
    if ($k.Length -le 3) { continue }
    $d = if ($k.Contains('-')) { '-?' } else { '-' }
    $s = Invoke-ScrubReplace $s ('(?m)(^|[/\\ "])' + $d + $k.Replace('-', '-+') + '[A-Za-z0-9._-]*') {
      param($m) $m.Groups[1].Value + '-work-example'
    } $counts 'key'
  }
  $s = Invoke-ScrubReplace $s '(?m)([/\\]projects[/\\])[A-Za-z0-9._]*-[A-Za-z0-9._-]*([/\\"]|$)' {
    param($m) $m.Groups[1].Value + '-work-example' + $m.Groups[2].Value
  } $counts 'key'

  # 5. The account name.
  if ($User) {
    $s = Invoke-ScrubReplace $s ('(?i)' + (Get-WordPattern $User)) { 'dev' } $counts 'user'
  }

  # 6. The domain, then the host name and its short form.
  if ($Domain) {
    $s = Invoke-ScrubReplace $s ('(?i)' + (Get-WordPattern $Domain)) { 'domain' } $counts 'domain'
  }
  if ($HostName) {
    $names = @($HostName)
    $short = $HostName.Split('.')[0]
    if ($short -and $short -ne $HostName) { $names += $short }
    foreach ($n in $names) {
      $s = Invoke-ScrubReplace $s ('(?i)' + (Get-WordPattern $n)) { 'host' } $counts 'host'
    }
  }

  # 7. API keys and tokens. A letter, a digit or a "-" must not come just
  # before a key. A "_" or a "=" can.
  $s = Invoke-ScrubReplace $s '(?<![A-Za-z0-9-])(?:(?:sk-ant-|sk-proj-|github_pat_|AIza|gh[pousr]_|glpat-|xox[abprs]-)[A-Za-z0-9_-]{16,}|sk-(?!ant-|proj-)(?=[A-Za-z0-9_-]*[0-9])[A-Za-z0-9_-]{16,}|AKIA[0-9A-Z]{16,}|key_[0-9a-fA-F]{32,}|eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]*(?:\.[A-Za-z0-9_-]+)?)' { '<secret>' } $counts 'secret'

  # 8. UUIDs.
  $s = Invoke-ScrubReplace $s '(?i)(?<![0-9a-z])[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(?![0-9a-z])' { '<uuid>' } $counts 'uuid'

  # 9. Long hex runs.
  $s = Invoke-ScrubReplace $s '(?i)(?<![0-9a-z])[0-9a-f]{16,}(?![0-9a-z])' { '<hex>' } $counts 'hex'

  # 10. E-mail addresses. The file name of a kit step,
  # NN-NAME@BACKEND.txt (probes/agent/step.ps1), is not an e-mail address.
  $s = Invoke-ScrubReplace $s '(?<![A-Za-z0-9._%+-])(?![0-9]+-[a-z0-9-]+@(?:none|tmux|pty|conpty|psmux|operator)\.txt(?!\.?[A-Za-z0-9-]))[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}' { '<email>' } $counts 'email'

  # 11. IPv4 addresses. A dotted quad after "v" or "version", or before a
  # letter, "-" or "+", is a version number and stays.
  $s = Invoke-ScrubReplace $s '(?<![0-9.vV])(?<!(?i:version)[^0-9\r\n]{0,4})(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?![0-9])(?!\.[0-9])(?![-+A-Za-z])' {
    param($m)
    if ($m.Value -eq '127.0.0.1' -or $m.Value -eq '0.0.0.0') { $m.Value } else { '<ip>' }
  } $counts 'ip'

  $s = $s.Replace('<sandbox>@S@', '<sandbox>/')
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
  $x = @()
  if ($env:SCRUB_EXTRA) { $x += @($env:SCRUB_EXTRA -split "`r?`n" | Where-Object { $_ }) }
  foreach ($v in @($env:OneDrive, $env:OneDriveCommercial, $env:OneDriveConsumer)) { if ($v) { $x += $v } }
  $d = $env:SCRUB_DOMAIN
  if (-not $d -and $env:USERDOMAIN) {
    $short = ([string]$n).Split('.')[0]
    if ($env:USERDOMAIN -ne $n -and $env:USERDOMAIN -ne $short -and $env:USERDOMAIN -ne $env:COMPUTERNAME) { $d = $env:USERDOMAIN }
  }
  return New-Object PSObject -Property @{ HomeDir = $h; User = $u; HostName = $n; Extra = $x; Domain = $d }
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
$r = Invoke-Scrub $text $d.HomeDir $d.User $d.HostName $d.Extra $d.Domain

$bytes = $utf8.GetBytes($r.Text)
$out = [Console]::OpenStandardOutput()
$out.Write($bytes, 0, $bytes.Length)
$out.Flush()
foreach ($k in $script:ScrubKinds) {
  [Console]::Error.WriteLine(('scrub: {0} {1}' -f $r.Counts[$k], $k))
}
exit 0
