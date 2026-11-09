#!/bin/sh
# Scrub probe and scenario output before it leaves the machine.
#
# Usage: sh tools/scrub.sh [file] > scrubbed.txt
# It reads the file, or stdin, and writes the scrubbed text to stdout. For
# each kind of change it writes one line "scrub: <count> <kind>" to stderr,
# with the number of lines that changed.
#
# Changes, in this order:
#   W. a path that an agent wrapped onto the next screen lines: its line
#      ends move to just after the path, so that the rules below see the
#      full path. The line count stays. See the comment of the pass.
#   0. each extra root: a line of SCRUB_EXTRA (for example the run folder of
#      the agent kit), and the values of OneDrive, OneDriveCommercial and
#      OneDriveConsumer                              -> /work/example
#   1. the home folder of this account               -> ~
#   2. other home folders (/Users/<name>, /home/<name>, C:\Users\<name>) -> ~
#   3. a path below ~ that is not in an agent or system folder:
#      the folders up to the first hidden folder     -> /work/example
#      (~/code/app/.claude/x -> /work/example/.claude/x, ~/code/app/a.go -> /work/example)
#   3a. a Windows account SID, S-1-5-21-...          -> <sid>
#      It comes before 4: a project key also matches a bare SID. The
#      well-known SIDs (S-1-5-18, S-1-5-32-544) name no machine, and stay.
#   4. /srv/... and /work/<name>/...                 -> /work/example, the same way,
#      and a Windows drive path such as D:\Projects\shop, also after a \\?\
#      prefix. C:\Windows, C:\Program Files and C:\ProgramData stay.
#   5. the account name                              -> dev
#   6. the host name                                 -> host,
#      and SCRUB_DOMAIN as a whole word              -> domain
#   7. API keys and tokens                           -> <secret>
#      sk-ant-, sk-proj-, AIza, ghp_, gho_, ghu_, ghs_, ghr_, github_pat_,
#      glpat- and xoxa-, xoxb-, xoxp-, xoxr-, xoxs-, each with 16 or more
#      key characters after it; sk- with 16 or more and one digit or more;
#      AKIA with 16 upper-case letters or digits; key_ with 32 or more hex
#      characters; a JWT (eyJ..., a dot, eyJ...). A letter, a digit or a
#      "-" must not come just before it. A "_" or a "=" can.
#   8. UUIDs                                         -> <uuid>
#   9. hex runs of 16 characters or more             -> <hex>
#  10. e-mail addresses                              -> <email>
#  11. IPv4 addresses, except 127.0.0.1 and 0.0.0.0  -> <ip>
#      (not a version number: after v or version, or before a letter, - or +)
#  A path can hold spaces. After a space, a word that holds a / (or a \ in
#  a drive path) and does not start a new path continues the path. So
#  ~/My Projects/Client Acme/a.go is one path. A last folder with a space
#  and no / after it ends the path at the space, except in quotes: a path
#  just after a " goes to the next ".
#  A project key (a path with dashes, see below) becomes -work-example. A
#  Windows key starts with a drive letter: D--Projects-shop, C-Users-alice-shop.
#
# The scrub is a help, not a proof. Read the output before you send it.
# SCRUB_HOME, SCRUB_USER and SCRUB_HOST replace the values of this machine.
# The tests use them. SCRUB_EXTRA holds more roots, one on each line.
set -eu

home=${SCRUB_HOME:-$HOME}
user=${SCRUB_USER:-$(id -un)}
host=${SCRUB_HOST:-$(hostname 2>/dev/null || uname -n)}
short=${host%%.*}

# Quote a value for use in an extended regular expression with # as the
# separator.
q() { printf '%s' "$1" | sed 's/[][\.*^$+?(){}|#]/\\&/g'; }

tmp=$(mktemp -d)
# dash runs no EXIT trap on a signal, so a signal exits first.
trap 'exit 130' INT TERM
trap 'rm -rf "$tmp"' EXIT
# A path after <sandbox> is below a throwaway folder of a scenario. Its home
# is <sandbox>/home/, and no home rule may read the next word as an account
# name. So the "/" after <sandbox> is @S@ until all rules are done.
sed 's#<sandbox>/#<sandbox>@S@#g' "${1:--}" >"$tmp/a"

count() {
  # $1: kind. Count the changed lines between a and b, then keep b.
  n=$(diff "$tmp/a" "$tmp/b" | grep -c '^>' || true)
  [ "$n" -gt 0 ] && echo "scrub: $n $1" >&2
  mv "$tmp/b" "$tmp/a"
}

rule() {
  # $1: kind; $2: sed expression.
  sed -E "$2" "$tmp/a" >"$tmp/b"
  count "$1"
}

# 0. The extra roots, the longest first.
{
  [ -n "${SCRUB_EXTRA:-}" ] && printf '%s\n' "$SCRUB_EXTRA"
  for _v in "${OneDrive:-}" "${OneDriveCommercial:-}" "${OneDriveConsumer:-}"; do
    [ -n "$_v" ] && printf '%s\n' "$_v"
  done
} | awk 'length($0) > 1 { print length($0) "\t" $0 }' | sort -rn | cut -f 2- >"$tmp/extra"
# A Windows root (a drive letter) matches in any case, and each run of /
# and \ in it matches one or more of / and \, as in tools/scrub.ps1.
# Another root matches as it is.
wq() {
  printf '%s' "$1" | LC_ALL=C awk '{
    p = ""; n = length($0)
    for (i = 1; i <= n; i++) {
      c = substr($0, i, 1)
      if (c == "\\" || c == "/") {
        if (substr(p, length(p) - 5) != "[\\\\/]+") p = p "[\\\\/]+"
      } else if (c ~ /[A-Za-z]/) p = p "[" toupper(c) tolower(c) "]"
      else if (index("][.*^$+?(){}|#", c)) p = p "\\" c
      else p = p c
    }
    printf "%s", p
  }'
}
: >"$tmp/extra.sed"
while IFS= read -r _x; do
  case $_x in
    [A-Za-z]:*) printf 's#%s#/work/example#g\n' "$(wq "$_x")" >>"$tmp/extra.sed" ;;
    *) printf 's#%s#/work/example#g\n' "$(q "$_x")" >>"$tmp/extra.sed" ;;
  esac
done <"$tmp/extra"

# A wrapped path. An agent can wrap a long path onto the next screen
# lines, so a line holds only a part of it. Then no rule below sees the
# full path. This pass moves the line ends from a wrapped path to just
# after it, so that the full path is on its first line. Each line end and
# the line count stay. A path is wrapped when:
#   - an anchor is cut by one or more line ends: each extra root, the home
#     folder, /Users/, /home/, ~/, /srv/ and /work/, or
#   - the path after an anchor goes to the end of the line, the first word
#     of the next line is made only of the characters A-Z a-z 0-9 . _ ~ -
#     / and \, and one of these is true:
#     - the path ends with / or \,
#     - the word holds a / or a \,
#     - the path starts at a private anchor (an extra root or the home
#       folder), this is the first line end after the anchor, and the path
#       does not end with a full file extension such as .txt. So the tail
#       of a hash, of a folder name or of a file name joins too.
#     A word that fills its line can be a part of the path too: then the
#     next line decides. A word such as [Y/n], (y/n) or Esc/Ctrl+C does
#     not join. When the line ends just after a whole anchor that does
#     not end with / or \, the word must start with / or \: a join must
#     not make a root such as "C:\Users\a\OneDrive - Org" longer.
# The line after a line end starts with white space. This white space can
# hold one box line (U+2502), as in the command box of Claude Code. A
# right box line can come after the path, with white space before it: the
# line end is then after this box line, and both box lines stay. A
# Windows root (a drive letter) matches in any case, and each / or \ in it
# matches one or more of / and \. tools/scrub.ps1 does the same in
# Invoke-ScrubUnwrap.
# The gap: a next line with no white space at its start does not join, so
# a part of a path on it stays. tmux -J and the pty screen of the kit join
# the lines of a terminal wrap; an agent indents its own wrap.
{
  cat "$tmp/extra"
  printf '%s\n' "$home"
} | awk 'length($0) > 1' >"$tmp/anchors"
np=$(awk 'END { print NR }' "$tmp/anchors")
# The ~ is text here: an agent writes it in a path.
# shellcheck disable=SC2088
printf '%s\n' /Users/ /home/ '~/' /srv/ /work/ >>"$tmp/anchors"
# The pass works on bytes (LC_ALL=C). The awk of macOS reads UTF-8 in a
# UTF-8 locale, and it stops with "towc: multibyte conversion failure" on
# this pass. mawk and busybox awk work on bytes in each locale.
LC_ALL=C awk -v afile="$tmp/anchors" -v np="$np" -v bx="$(printf '\342\224\202')" '
# esc(c): the character c as an ERE that matches only c.
function esc(c) {
  if (c == "\\") return "\\\\"
  if (c == "^") return "\\^"
  if (c == "]") return "[]]"
  if (index(".[*+?{}()|$", c)) return "[" c "]"
  return c
}
# pattern(v, win): the ERE for the anchor v. The search runs on the text
# without its line ends (flat), so that the ERE stays small: the awk of
# macOS fails on a large ERE.
function pattern(v, win,    i, c, p) {
  p = ""
  for (i = 1; i <= length(v); i++) {
    c = substr(v, i, 1)
    if (win && (c == "\\" || c == "/")) p = p "[\\\\/]+"
    else p = p esc(c)
  }
  return p
}
# flat(t, last): set F to t without each line end that comes after a
# character that is not white space. last is the character before t.
# BP[k] is the position in F just after the k-th line end, and BL[k] is
# its length in t. NB is the count of line ends.
function flat(t, last,    r, x, c) {
  F = ""; NB = 0; r = t
  while (match(r, nl)) {
    x = substr(r, 1, RSTART - 1)
    c = (RSTART > 1) ? substr(r, RSTART - 1, 1) : last
    if (c == "" || c ~ /[ \t]/) {
      F = F substr(r, 1, RSTART + RLENGTH - 1)
    } else {
      F = F x; NB++; BP[NB] = length(F) + 1; BL[NB] = RLENGTH
    }
    last = substr(r, RSTART + RLENGTH - 1, 1)
    r = substr(r, RSTART + RLENGTH)
  }
  F = F r
}
# brk(b): a line end that is not the last one keeps no white space after
# it, so that its line stays empty.
function brk(b) { sub(/[ \t]*$/, "", b); return b }
# more(j, after, first, whole): 1 when the path j continues after the line
# end at the start of after. first is 1 for the first line end after a
# private anchor. whole is 1 when the line ends just after a whole anchor
# that does not end with / or \: then the next word must start with / or
# \, so that a join does not make the anchor longer (a root such as
# "C:\Users\a\OneDrive - Org" then "docs/x" stays apart).
function more(j, after, first, whole,    nxt, w) {
  while (match(after, "^" nl pc)) {
    nxt = substr(after, RLENGTH)
    match(nxt, "^" pc "*")
    w = substr(nxt, 1, RLENGTH)
    if (w !~ /^[A-Za-z0-9._~\/\\-]+$/) return 0
    if (whole && w !~ /^[\/\\]/) return 0
    whole = 0
    if (j ~ /[\/\\]$/ || w ~ /[\/\\]/) return 1
    if (first && j !~ /\.[A-Za-z0-9]+$/) return 1
    j = w; first = 0; after = substr(nxt, RLENGTH + 1)
  }
  return 0
}
# unwrap(t): the text t with each wrapped path on one line.
function unwrap(t,    a, out, rest, src, s, l, pre, m, j, nb, b, after, k, first, fs, fl, whole) {
  for (a = 1; a <= n; a++) {
    out = ""; rest = t
    while (1) {
      flat(rest, substr(out, length(out), 1))
      src = win[a] ? tolower(F) : F
      if (!match(src, re[a])) break
      # The match in rest: add the line ends before it and in it.
      fs = RSTART; fl = RLENGTH; s = fs; l = fl
      for (k = 1; k <= NB; k++) {
        if (BP[k] <= fs) s += BL[k]
        else if (BP[k] < fs + fl) l += BL[k]
      }
      pre = (s > 1) ? substr(rest, s - 1, 1) : substr(out, length(out), 1)
      if (pre ~ /[A-Za-z0-9_.~-]/) {
        out = out substr(rest, 1, s); rest = substr(rest, s + 1); continue
      }
      # The anchor without its line ends.
      m = substr(rest, s, l); j = ""; nb = 0
      while (match(m, nl)) {
        j = j substr(m, 1, RSTART - 1)
        b[++nb] = substr(m, RSTART, RLENGTH)
        m = substr(m, RSTART + RLENGTH)
      }
      j = j m
      # The rest of the path, also on the next lines.
      after = substr(rest, s + l)
      first = (a <= np)
      whole = 1
      while (1) {
        match(after, "^" pc "*")
        whole = (whole && RLENGTH == 0 && j !~ /[\/\\]$/)
        j = j substr(after, 1, RLENGTH); after = substr(after, RLENGTH + 1)
        if (!more(j, after, first, whole)) break
        first = 0; whole = 0
        match(after, "^" nl)
        b[++nb] = substr(after, 1, RLENGTH); after = substr(after, RLENGTH + 1)
      }
      if (nb == 0) {
        out = out substr(rest, 1, s + l - 1); rest = substr(rest, s + l); continue
      }
      out = out substr(rest, 1, s - 1) j
      for (k = 1; k < nb; k++) out = out brk(b[k])
      out = out b[nb]
      rest = after
    }
    t = out rest
  }
  return t
}
BEGIN {
  pc = "[^ \t\r\n\"'\'',:;()]"
  # A line end, maybe after a right box line, and the white space at the
  # start of the next line.
  nl = "([ \t]*" bx ")?\r?\n([ \t]*" bx ")?[ \t]+"
  n = 0
  while ((getline v < afile) > 0) {
    n++
    win[n] = (v ~ /^[A-Za-z]:/)
    re[n] = pattern(win[n] ? tolower(v) : v, win[n])
  }
}
{ line[NR] = $0 }
# A block is a line and the next lines that can continue a path on it:
# the line before ends with a character that is not white space, and the
# line starts with white space. The pass looks at one block at a time, so
# that a long file stays fast.
END {
  i = 1
  while (i <= NR) {
    t = line[i]
    while (i < NR && line[i] ~ /[^ \t]\r?$/ && ("\n" line[i + 1]) ~ ("^" nl "[^ \t]")) {
      i++
      t = t "\n" line[i]
    }
    print unwrap(t)
    i++
  }
}' "$tmp/a" >"$tmp/b"
count "wrapped path"

if [ -s "$tmp/extra.sed" ]; then
  sed -E -f "$tmp/extra.sed" "$tmp/a" >"$tmp/b"
  count "extra root"
fi

rule "home folder" "s#$(q "$home")([/\\\\\"' :]|\$)#~\\1#g"
rule "other home folder" 's#/Users/[A-Za-z0-9._-]+#~#g; s#/home/[A-Za-z0-9._-]+#~#g; s#[A-Za-z]:\\+Users\\+[A-Za-z0-9._-]+#~#g'

# 3 and 4. A path is a run of characters that are not white space, quotes,
# a colon or a comma. Folders up to the first hidden folder become
# /work/example. Agent and system folders keep their names.
awk '
# fix(path, tilde): path starts with "/". Keep a path below ~ whose first
# folder is an agent or system folder. Else replace the folders up to the
# first hidden folder (not the first folder) with /work/example.
function fix(path, tilde,    n, parts, i, out) {
  n = split(path, parts, "/")
  if (tilde && parts[2] ~ /^(\.[^\/]*|Library|AppData|Applications)$/) return "~" path
  if (!tilde && path ~ /^\/work\/example(\/|$)/) return path
  for (i = 3; i <= n; i++) if (parts[i] ~ /^\./) break
  out = "/work/example"
  for (; i <= n; i++) out = out "/" parts[i]
  return out
}
# wfix(path): path is a Windows drive path, maybe with a \\?\ prefix. Keep a
# system folder and a path whose first folder is hidden. Else replace the
# folders up to the first hidden folder (not the first folder) with
# /work/example. The separators before the hidden folder stay.
function wfix(path,    rest, first, r, r2, sep) {
  rest = substr(path, index(path, ":") + 1)
  sub(/^(\\|\/)+/, "", rest)
  first = rest
  if (match(rest, /(\\|\/)/)) first = substr(rest, 1, RSTART - 1)
  if (tolower(first) ~ /^(windows|program|program files|programdata|progra~1|progra~2)$/ || first ~ /^\./) return path
  r = substr(rest, length(first) + 1)
  while (match(r, /^(\\|\/)+/)) {
    sep = substr(r, 1, RLENGTH)
    r2 = substr(r, RLENGTH + 1)
    if (substr(r2, 1, 1) == ".") return "/work/example" sep r2
    r = ""
    if (match(r2, /(\\|\/)/)) r = substr(r2, RSTART)
  }
  return "/work/example"
}
# more(rest, bs): the length of the words at the start of rest that
# continue a path. Each word starts with one space, does not start a new
# path, and holds a / (or a \ when bs is 1).
function more(rest, bs,    n, w) {
  n = 0
  while (1) {
    w = substr(rest, n + 1)
    if (bs) {
      if (!match(w, /^ [^ \t\r"'\'',:;()\/\\~][^ \t\r"'\'',:;()\/\\]*[\/\\][^ \t\r"'\'',:;()]*/)) break
    } else if (!match(w, /^ [^ \t\r"'\'',:;()\/~][^ \t\r"'\'',:;()\/]*\/[^ \t\r"'\'',:;()]*/)) break
    n += RLENGTH
  }
  return n
}
# span(line, s, l, bs): the length of the path that starts at s and whose
# first word has the length l. A path just after a " goes to the next ".
function span(line, s, l, bs,    q) {
  if (s > 1 && substr(line, s - 1, 1) == "\"") {
    q = index(substr(line, s), "\"")
    if (q - 1 > l) return q - 1
  }
  return l + more(substr(line, s + l), bs)
}
{
  line = $0
  res = ""
  while (1) {
    s1 = 0; s2 = 0
    if (match(line, /(~|\/srv|\/work)\/[^ \t\r"'\'',:;()]+/)) { s1 = RSTART; l1 = span(line, RSTART, RLENGTH, 0) }
    if (match(line, /[A-Za-z]:(\\|\/)+[^ \t\r"'\'',:;()]+/)) { s2 = RSTART; l2 = span(line, RSTART, RLENGTH, 1) }
    if (s1 == 0 && s2 == 0) break
    # A \\?\ or \\? prefix goes with the drive path. Some awks do not
    # match an optional group before the drive letter, so look back here.
    if (s2 > 0 && (s1 == 0 || s2 < s1)) {
      j = s2 - 1
      while (j >= 1 && substr(line, j, 1) == "\\") j--
      if (j >= 2 && substr(line, j, 1) == "?" && substr(line, j - 1, 1) == "\\") {
        q = j; j--
        while (j >= 1 && substr(line, j, 1) == "\\") j--
        p = j + 1
        # Like a look-behind: the prefix must not continue a word.
        while (p < q && p > 1 && substr(line, p - 1, 1) ~ /[A-Za-z0-9_.~-]/) p++
        if (p < q) { l2 += s2 - p; s2 = p }
      }
    }
    if (s1 > 0 && (s2 == 0 || s1 <= s2)) {
      m = substr(line, s1, l1)
      if (substr(m, 1, 1) == "~") rep = fix(substr(m, 2), 1)
      else rep = fix(m, 0)
      res = res substr(line, 1, s1 - 1) rep
      line = substr(line, s1 + l1)
      continue
    }
    # A drive path must not continue a word. Else skip one character.
    prev = (s2 > 1) ? substr(line, s2 - 1, 1) : substr(res, length(res), 1)
    if (prev ~ /[A-Za-z0-9_.~-]/) {
      res = res substr(line, 1, s2)
      line = substr(line, s2 + 1)
      continue
    }
    res = res substr(line, 1, s2 - 1) wfix(substr(line, s2, l2))
    line = substr(line, s2 + l2)
  }
  print res line
}' "$tmp/a" >"$tmp/b"
count "project path"

# The temporary folders of Claude Code and Cursor hold the account number or
# a run name.
rule "agent temp folder" 's#/tmp/claude-[A-Za-z0-9._-]+#/tmp/claude-example#g; s#/tmp/cursor-agent-logs-[0-9]+#/tmp/cursor-agent-logs-example#g'

# Windows account SIDs. This rule comes before the project keys, because a
# project key also matches a bare SID.
rule "sid" 's#S-1-5-21(-[0-9]+){3,4}#<sid>#g'

# Agents name a project folder by its path with dashes: Claude
# "-srv-work-app" or "-Users-alice-code-app", Cursor "Users-alice-code-app".
# On Windows the key starts with a drive letter: Claude
# "D--Projects-app", Cursor "C-Users-alice-app" or "D-Projects-app". The
# token after the drive letter must hold one more dash, so that a word such
# as "X-ray" stays. A lower-case drive letter needs two dashes, so that
# "x-api-key" stays.
rule "project key" 's#(^|[/\\ "])-?(srv|Users|home|var-lib|work)-[A-Za-z0-9._-]+#\1-work-example#g; s#(^|[/\\ "])([A-Z]-|[A-Za-z]--)[A-Za-z0-9._]+-[A-Za-z0-9._-]+#\1-work-example#g'
# A key on another root: the key form of each extra root and of $PWD (one
# or more dashes for each run of other characters), and each key in a
# "projects" folder. A key with one word needs its dash.
{ cat "$tmp/extra"; printf '%s\n' "$PWD"; } | while IFS= read -r r; do
  k=$(printf '%s' "$r" | tr -cs 'A-Za-z0-9' '-' | sed 's/^-*//; s/-*$//')
  [ "${#k}" -gt 3 ] || continue
  case $k in *-*) d='-?' ;; *) d=- ;; esac
  k=$(printf '%s' "$k" | sed 's/-/-+/g')
  printf 's#(^|[/\\\\ "])%s%s[A-Za-z0-9._-]*#\\1-work-example#g\n' "$d" "$k"
done >"$tmp/keys"
printf '%s\n' 's#([/\\]projects[/\\])[A-Za-z0-9._]*-[A-Za-z0-9._-]*([/\\"]|$)#\1-work-example\2#g' >>"$tmp/keys"
rule "project key" "$(cat "$tmp/keys")"

[ -n "$user" ] && rule "account name" "s#(^|[^A-Za-z0-9_.-])$(q "$user")([^A-Za-z0-9_-]|\$)#\\1dev\\2#g"
[ -n "${SCRUB_DOMAIN:-}" ] && rule "domain" "s#(^|[^A-Za-z0-9_-])$(q "$SCRUB_DOMAIN")([^A-Za-z0-9_-]|\$)#\\1domain\\2#g"
[ -n "$host" ] && rule "host name" "s#(^|[^A-Za-z0-9_-])($(q "$host")|$(q "$short"))([^A-Za-z0-9_-]|\$)#\\1host\\3#g"
# 7. API keys and tokens. awk finds each word that can be a key, and
# secret() checks its length and its form, because the ERE of some awks
# has no {n,} and no look-ahead.
awk '
function secret(w,    r) {
  if (w ~ /^eyJ/) return w ~ /^eyJ[A-Za-z0-9_-][A-Za-z0-9_-][A-Za-z0-9_-][A-Za-z0-9_-][A-Za-z0-9_-][A-Za-z0-9_-][A-Za-z0-9_-][A-Za-z0-9_-][A-Za-z0-9_-][A-Za-z0-9_-][A-Za-z0-9_-]*\.eyJ/
  if (w ~ /^AKIA/) return length(w) >= 20
  if (w ~ /^key_/) return length(w) >= 36
  if (w ~ /^(sk-ant-|sk-proj-|github_pat_)/) { r = w; sub(/^(sk-ant-|sk-proj-|github_pat_)/, "", r); return length(r) >= 16 }
  if (w ~ /^sk-/) { r = substr(w, 4); return length(r) >= 16 && r ~ /[0-9]/ }
  r = w
  sub(/^(AIza|gh[pousr]_|glpat-|xox[abprs]-)/, "", r)
  return length(r) >= 16
}
{
  line = $0
  out = ""
  while (match(line, /(sk-|AIza|gh[pousr]_|github_pat_|glpat-|xox[abprs]-)[A-Za-z0-9_-]+|AKIA[0-9A-Z]+|key_[0-9a-fA-F]+|eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]*(\.[A-Za-z0-9_-]+)?/)) {
    s = RSTART
    w = substr(line, s, RLENGTH)
    pre = (s > 1) ? substr(line, s - 1, 1) : ""
    if (pre !~ /[A-Za-z0-9-]/ && secret(w)) w = "<secret>"
    out = out substr(line, 1, s - 1) w
    line = substr(line, s + RLENGTH)
  }
  print out line
}' "$tmp/a" >"$tmp/b"
count "secret"
rule "uuid" 's#[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}#<uuid>#g'
rule "hex" 's#[0-9a-fA-F]{16,}#<hex>#g'
# The file name of a kit step, NN-NAME@BACKEND.txt (probes/agent/step.sh),
# is not an e-mail address. The rule hides its "@" while it runs.
kb='none|tmux|pty|conpty|psmux|operator'
at=$(printf '\001')
keep="s#(^|[^A-Za-z0-9._%+-])([0-9]+-[a-z0-9-]+)@($kb)\\.txt(\\.?([^A-Za-z0-9.-]|\$))#\\1\\2$at\\3.txt\\4#g"
rule "email" "$keep; $keep; s#[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}#<email>#g; s#$at#@#g"
# A dotted quad after "v" or "version", or before a letter, "-" or "+", is a
# version number. Its dots become @D@ until the IP rule is done.
q4='([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})'
sed -E "s#([vV]|[Vv]ersion[^0-9]{0,4})$q4#\1\2@D@\3@D@\4@D@\5#g; s#$q4([-+A-Za-z])#\1@D@\2@D@\3@D@\4\5#g" "$tmp/a" |
  sed -E 's#(^|[^0-9.])127\.0\.0\.1([^0-9.]|$)#\1@LOOPBACK@\2#g; s#(^|[^0-9.])0\.0\.0\.0([^0-9.]|$)#\1@ANY@\2#g' |
  sed -E 's#(^|[^0-9.])([0-9]{1,3}\.){3}[0-9]{1,3}([^0-9.]|$)#\1<ip>\3#g' |
  sed 's#@LOOPBACK@#127.0.0.1#g; s#@ANY@#0.0.0.0#g; s#@D@#.#g' >"$tmp/b"
count "ip"

sed 's#<sandbox>@S@#<sandbox>/#g' "$tmp/a"
