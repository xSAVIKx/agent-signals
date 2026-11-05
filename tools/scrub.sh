#!/bin/sh
# Scrub probe and scenario output before it leaves the machine.
#
# Usage: sh tools/scrub.sh [file] > scrubbed.txt
# It reads the file, or stdin, and writes the scrubbed text to stdout. For
# each kind of change it writes one line "scrub: <count> <kind>" to stderr,
# with the number of lines that changed.
#
# Changes, in this order:
#   0. each extra root: a line of SCRUB_EXTRA (for example the run folder of
#      the agent kit), and the values of OneDrive, OneDriveCommercial and
#      OneDriveConsumer                              -> /work/example
#   1. the home folder of this account               -> ~
#   2. other home folders (/Users/<name>, /home/<name>, C:\Users\<name>) -> ~
#   3. a path below ~ that is not in an agent or system folder:
#      the folders up to the first hidden folder     -> /work/example
#      (~/code/app/.claude/x -> /work/example/.claude/x, ~/code/app/a.go -> /work/example)
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
cat "${1:--}" >"$tmp/a"

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
: >"$tmp/extra.sed"
while IFS= read -r _x; do
  printf 's#%s#/work/example#g\n' "$(q "$_x")" >>"$tmp/extra.sed"
done <"$tmp/extra"
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
      if (!match(w, /^ [^ \t"'\'',:;()\/\\~][^ \t"'\'',:;()\/\\]*[\/\\][^ \t"'\'',:;()]*/)) break
    } else if (!match(w, /^ [^ \t"'\'',:;()\/~][^ \t"'\'',:;()\/]*\/[^ \t"'\'',:;()]*/)) break
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
    if (match(line, /(~|\/srv|\/work)\/[^ \t"'\'',:;()]+/)) { s1 = RSTART; l1 = span(line, RSTART, RLENGTH, 0) }
    if (match(line, /[A-Za-z]:(\\|\/)+[^ \t"'\'',:;()]+/)) { s2 = RSTART; l2 = span(line, RSTART, RLENGTH, 1) }
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

# Agents name a project folder by its path with dashes: Claude
# "-srv-work-app" or "-Users-alice-code-app", Cursor "Users-alice-code-app".
# On Windows the key starts with an upper-case drive letter: Claude
# "D--Projects-app", Cursor "C-Users-alice-app" or "D-Projects-app". The
# token after the drive letter must hold one more dash, so that a word such
# as "X-ray" stays.
rule "project key" 's#(^|[/\\ "])-?(srv|Users|home|var-lib|work)-[A-Za-z0-9._-]+#\1-work-example#g; s#(^|[/\\ "])[A-Z]--?[A-Za-z0-9._]+-[A-Za-z0-9._-]+#\1-work-example#g'

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
rule "email" "s#(^|[^A-Za-z0-9._%+-])([0-9]+-[a-z0-9-]+)@($kb)\\.txt([^A-Za-z0-9.-]|\$)#\\1\\2%KITAT%\\3.txt\\4#g; s#(^|[^A-Za-z0-9._%+-])([0-9]+-[a-z0-9-]+)@($kb)\\.txt([^A-Za-z0-9.-]|\$)#\\1\\2%KITAT%\\3.txt\\4#g; s#[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}#<email>#g; s#%KITAT%#@#g"
# A dotted quad after "v" or "version", or before a letter, "-" or "+", is a
# version number. Its dots become @D@ until the IP rule is done.
q4='([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})'
sed -E "s#([vV]|[Vv]ersion[^0-9]{0,4})$q4#\1\2@D@\3@D@\4@D@\5#g; s#$q4([-+A-Za-z])#\1@D@\2@D@\3@D@\4\5#g" "$tmp/a" |
  sed -E 's#(^|[^0-9.])127\.0\.0\.1([^0-9.]|$)#\1@LOOPBACK@\2#g; s#(^|[^0-9.])0\.0\.0\.0([^0-9.]|$)#\1@ANY@\2#g' |
  sed -E 's#(^|[^0-9.])([0-9]{1,3}\.){3}[0-9]{1,3}([^0-9.]|$)#\1<ip>\3#g' |
  sed 's#@LOOPBACK@#127.0.0.1#g; s#@ANY@#0.0.0.0#g; s#@D@#.#g' >"$tmp/b"
count "ip"

cat "$tmp/a"
