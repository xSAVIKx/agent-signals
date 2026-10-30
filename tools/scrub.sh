#!/bin/sh
# Scrub probe and scenario output before it leaves the machine.
#
# Usage: sh tools/scrub.sh [file] > scrubbed.txt
# It reads the file, or stdin, and writes the scrubbed text to stdout. For
# each kind of change it writes one line "scrub: <count> <kind>" to stderr,
# with the number of lines that changed.
#
# Changes, in this order:
#   1. the home folder of this account               -> ~
#   2. other home folders (/Users/<name>, /home/<name>, C:\Users\<name>) -> ~
#   3. a path below ~ that is not in an agent or system folder:
#      the folders up to the first hidden folder     -> /work/example
#      (~/code/app/.claude/x -> /work/example/.claude/x, ~/code/app/a.go -> /work/example)
#   4. /srv/... and /work/<name>/...                 -> /work/example, the same way
#   5. the account name                              -> dev
#   6. the host name                                 -> host
#   7. UUIDs                                         -> <uuid>
#   8. hex runs of 16 characters or more             -> <hex>
#   9. e-mail addresses                              -> <email>
#  10. IPv4 addresses, except 127.0.0.1 and 0.0.0.0  -> <ip>
#      (not a version number: after v or version, or before a letter, - or +)
#  A project key (a path with dashes, see below) becomes -work-example.
#
# The scrub is a help, not a proof. Read the output before you send it.
# SCRUB_HOME, SCRUB_USER and SCRUB_HOST replace the values of this machine.
# The tests use them.
set -eu

home=${SCRUB_HOME:-$HOME}
user=${SCRUB_USER:-$(id -un)}
host=${SCRUB_HOST:-$(hostname 2>/dev/null || uname -n)}
short=${host%%.*}

# Quote a value for use in an extended regular expression with # as the
# separator.
q() { printf '%s' "$1" | sed 's/[][\.*^$+?(){}|#]/\\&/g'; }

tmp=$(mktemp -d)
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
{
  line = $0
  res = ""
  while (match(line, /(~|\/srv|\/work)\/[^ \t"'\'',:;()]+/)) {
    m = substr(line, RSTART, RLENGTH)
    if (substr(m, 1, 1) == "~") rep = fix(substr(m, 2), 1)
    else rep = fix(m, 0)
    res = res substr(line, 1, RSTART - 1) rep
    line = substr(line, RSTART + RLENGTH)
  }
  print res line
}' "$tmp/a" >"$tmp/b"
count "project path"

# Agents name a project folder by its path with dashes: Claude
# "-srv-work-app" or "-Users-alice-code-app", Cursor "Users-alice-code-app".
rule "project key" 's#(^|[/ "])-?(srv|Users|home|var-lib|work)-[A-Za-z0-9._-]+#\1-work-example#g'

[ -n "$user" ] && rule "account name" "s#(^|[^A-Za-z0-9_.-])$(q "$user")([^A-Za-z0-9_-]|\$)#\\1dev\\2#g"
[ -n "$host" ] && rule "host name" "s#(^|[^A-Za-z0-9_-])($(q "$host")|$(q "$short"))([^A-Za-z0-9_-]|\$)#\\1host\\3#g"
rule "uuid" 's#[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}#<uuid>#g'
rule "hex" 's#[0-9a-fA-F]{16,}#<hex>#g'
rule "email" 's#[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}#<email>#g'
# A dotted quad after "v" or "version", or before a letter, "-" or "+", is a
# version number. Its dots become @D@ until the IP rule is done.
q4='([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})'
sed -E "s#([vV]|[Vv]ersion[^0-9]{0,4})$q4#\1\2@D@\3@D@\4@D@\5#g; s#$q4([-+A-Za-z])#\1@D@\2@D@\3@D@\4\5#g" "$tmp/a" |
  sed -E 's#(^|[^0-9.])127\.0\.0\.1([^0-9.]|$)#\1@LOOPBACK@\2#g; s#(^|[^0-9.])0\.0\.0\.0([^0-9.]|$)#\1@ANY@\2#g' |
  sed -E 's#(^|[^0-9.])([0-9]{1,3}\.){3}[0-9]{1,3}([^0-9.]|$)#\1<ip>\3#g' |
  sed 's#@LOOPBACK@#127.0.0.1#g; s#@ANY@#0.0.0.0#g; s#@D@#.#g' >"$tmp/b"
count "ip"

cat "$tmp/a"
