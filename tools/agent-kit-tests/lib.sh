# shellcheck shell=sh
# Helpers for the agent kit tests. A test file starts with:
#   . "$ROOT/tools/agent-kit-tests/lib.sh"
# Each test gets a new folder in $T, which the EXIT trap deletes.
set -u
: "${ROOT:=$(cd "$(dirname "$0")/../.." && pwd)}"
# kit ARGS: run the agent kit of this checkout.
kit() { sh "$ROOT/probes/agent/kit.sh" "$@"; }
T=$(mktemp -d)
# A folder under $T is not in a git work tree, so a run folder there passes
# the checks of kit start.
_fail=0
# _left: the pids of the processes whose command line names $T, other than
# this shell and the ps pipeline. A daemon of an agent (the Codex app-server,
# fact 067) can outlive its session and keep its test home.
_left() {
  ps -A -o pid= -o args= 2>/dev/null | awk -v t="$T/" -v me="$$" 'index($0, t) && $1 != me && !/ps -A -o pid=/ { print $1 }'
}
# _cleanup: stop the background pids of the test and each process that still
# names $T, delete $T, and fail the test when a process stayed.
_cleanup() {
  _rc=$?
  [ -f "$T/.pids" ] && while read -r p; do kill "$p" 2>/dev/null; done <"$T/.pids"
  # A stopped background pid can take a moment to end.
  _n=0
  _stay=$(_left)
  while [ -n "$_stay" ] && [ "$_n" -lt 30 ]; do
    sleep 0.1
    _n=$((_n + 1))
    _stay=$(_left)
  done
  if [ -n "$_stay" ]; then
    echo "fail: a process of the test stayed after the test: $(echo $_stay | wc -w | tr -d ' ')"
    ps -o pid= -o args= -p "$(echo $_stay | tr ' ' ',')" 2>/dev/null | cut -c1-160 | sed 's/^/  left: /'
    for p in $_stay; do kill "$p" 2>/dev/null; done
    sleep 1
    for p in $_stay; do kill -9 "$p" 2>/dev/null; done
    _rc=1
  fi
  rm -rf "$T"
  exit "$_rc"
}
trap _cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# bg_pid PID: kill PID when the test file ends.
bg_pid() { echo "$1" >>"$T/.pids"; }

pass() { echo "pass: $1"; }
fail() { echo "fail: $1: $2"; _fail=1; }

# expect_code NAME WANT GOT
expect_code() {
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "exit $3, want $2"; fi
}

# expect_line NAME ERE FILE
expect_line() {
  if grep -Eq -- "$2" "$3"; then pass "$1"; else fail "$1" "no line matches: $2"; fi
}

# expect_no_line NAME ERE FILE
expect_no_line() {
  if grep -Eq -- "$2" "$3"; then fail "$1" "a line matches: $2"; else pass "$1"; fi
}

done_tests() { exit "$_fail"; }
