#!/bin/sh
# Runs kit tests with other POSIX shells as "sh": bash (POSIX mode when it
# runs as sh), zsh (sh emulation when it runs as sh), the ash of BusyBox,
# mksh, ksh, yash and dash. The kit scripts run as "sh FILE", so a folder
# first on PATH with a link "sh" to the shell selects it. A script that
# starts by its #!/bin/sh line still gets /bin/sh.
#
# Run: sh tools/test-shells.sh [SHELL ...] [-- TEST-FILE ...]
#   SHELL      dash, bash, zsh, busybox, mksh, ksh or yash (default: each
#              one that is installed).
#   TEST-FILE  the test files (default: tools/agent-kit-tests/test-core-*.sh
#              and test-session.sh).
#
# It prints the output of each test file with the shell name before each
# line, and at the end one line for each shell:
#   shells: NAME pass=P fail=F exit=N
# A shell that is not installed prints "shells: NAME missing". Exit code: 0
# when no case fails and the runner exits 0 for each shell, 1 else.
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
shells=
while [ "$#" -gt 0 ] && [ "$1" != -- ]; do
  shells="$shells $1"
  shift
done
[ "${1:-}" = -- ] && shift
[ -n "$shells" ] || shells="dash bash zsh busybox mksh ksh yash"
if [ "$#" -eq 0 ]; then
  set -- "$root"/tools/agent-kit-tests/test-core-*.sh "$root/tools/agent-kit-tests/test-session.sh"
fi
tmp=$(mktemp -d) || exit 1
# The trap keeps the exit status: mksh gives the status of the last
# command of the EXIT trap after an exit in a signal trap.
_trap_rc=0
trap '_trap_rc=$?; rm -rf "$tmp"; exit "$_trap_rc"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
rc=0
: >"$tmp/sum"
# yash cannot read a script with bytes outside ASCII in the C locale, so
# each script of the kit holds ASCII only. printf writes such bytes.
na=
for f in "$root"/probes/*.sh "$root"/probes/agent/*.sh "$root"/probes/agent/steps/*.sh "$root/tools/scrub.sh"; do
  [ "$(LC_ALL=C tr -d '\000-\177' <"$f" | wc -c)" -eq 0 ] || na="$na ${f#"$root"/}"
done
if [ -n "$na" ]; then
  echo "shells: a kit script holds bytes outside ASCII:$na" >>"$tmp/sum"
  rc=1
fi
for s in $shells; do
  exe=$(command -v "$s" 2>/dev/null) || exe=
  if [ -z "$exe" ]; then
    echo "shells: $s missing" >>"$tmp/sum"
    continue
  fi
  bin=$tmp/bin-$s
  mkdir "$bin"
  # BusyBox picks its applet from the name of the link, bash and zsh
  # take their sh mode from it.
  ln -s "$exe" "$bin/sh"
  PATH="$bin:$PATH" sh "$root/tools/test-agent-kit.sh" "$@" >"$tmp/out-$s" 2>&1
  code=$?
  p=$(grep -c '^pass:' "$tmp/out-$s")
  f=$(grep -c '^fail:' "$tmp/out-$s")
  sed "s/^/$s: /" "$tmp/out-$s"
  echo "shells: $s pass=$p fail=$f exit=$code" >>"$tmp/sum"
  # The runner can end with no "fail:" line, for example when a test
  # file cannot run.
  [ "$f" -eq 0 ] && [ "$code" -eq 0 ] || rc=1
done
cat "$tmp/sum"
exit "$rc"
