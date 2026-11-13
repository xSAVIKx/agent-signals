#!/bin/sh
# Runs the tests of the agent kit (probes/agent): each file
# tools/agent-kit-tests/*.sh, each in a new shell. A test file prints
# "pass: <name>" or "fail: <name>: <reason>" for each case and exits 1
# when a case fails.
# Run: sh tools/test-agent-kit.sh [FILE ...]
# KIT_TEST_SHARD=I/N runs only file I, I+N, I+2N and so on of the list.
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
if [ "$#" -eq 0 ]; then
  set -- "$root"/tools/agent-kit-tests/test-*.sh
fi
shard_i=1
shard_n=1
case ${KIT_TEST_SHARD:-} in
  '') ;;
  [1-9]/[1-9])
    shard_i=${KIT_TEST_SHARD%/*}
    shard_n=${KIT_TEST_SHARD#*/}
    [ "$shard_i" -le "$shard_n" ] || { echo "bad KIT_TEST_SHARD: $KIT_TEST_SHARD" >&2; exit 2; }
    ;;
  *) echo "bad KIT_TEST_SHARD: $KIT_TEST_SHARD" >&2; exit 2 ;;
esac
fail=0
k=0
for t in "$@"; do
  k=$((k + 1))
  [ $(((k - 1) % shard_n + 1)) -eq "$shard_i" ] || continue
  echo "== $(basename "$t")"
  ROOT=$root sh "$t" || fail=1
done
exit "$fail"
