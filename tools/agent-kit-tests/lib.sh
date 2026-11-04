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
_cleanup() {
  [ -f "$T/.pids" ] && while read -r p; do kill "$p" 2>/dev/null; done <"$T/.pids"
  rm -rf "$T"
}
trap _cleanup EXIT INT TERM

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
