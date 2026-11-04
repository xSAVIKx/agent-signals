#!/bin/sh
# Runs the tests of the agent kit (probes/agent): each file
# tools/agent-kit-tests/*.sh, each in a new shell. A test file prints
# "pass: <name>" or "fail: <name>: <reason>" for each case and exits 1
# when a case fails.
# Run: sh tools/test-agent-kit.sh [FILE ...]
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
if [ "$#" -eq 0 ]; then
  set -- "$root"/tools/agent-kit-tests/test-*.sh
fi
fail=0
for t in "$@"; do
  echo "== $(basename "$t")"
  ROOT=$root sh "$t" || fail=1
done
exit "$fail"
