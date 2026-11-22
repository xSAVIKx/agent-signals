#!/bin/sh
# Checks snapshot_files of scenarios/lib.sh: a file that find lists but
# that is gone before its size is read is not listed, and it gives no
# error. A stub find lists a file that does not exist. The test deletes its
# temporary folder when it ends.
# Run: sh tools/test-scenario-lib.sh
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
here=$root/scenarios
# shellcheck source=scenarios/lib.sh
. "$here/lib.sh"
tmp=$(mktemp -d)
trap 'rm -rf "${tmp:?}"' EXIT
fail=0

SCN_DIR=$tmp/run
SCN_OUT=$tmp/out
mkdir -p "$SCN_DIR/home/d" "$SCN_OUT"
printf 'abc' >"$SCN_DIR/home/d/here"
# The stub lists one real file and one file that is gone.
find() { printf '%s\n' "$SCN_DIR/home/d/gone" "$SCN_DIR/home/d/here"; }

snapshot_files snap "$SCN_DIR/home/d" 2>"$tmp/err"
unset -f find
if [ -s "$tmp/err" ]; then echo "fail: snapshot_files wrote to stderr: $(head -1 "$tmp/err")"; fail=1; else echo "pass: no error for a file that is gone"; fi
if [ "$(wc -l <"$SCN_OUT/snap.files" | tr -d ' ')" = 1 ]; then echo "pass: the list has one line"; else echo "fail: the list: $(cat "$SCN_OUT/snap.files")"; fail=1; fi
if grep -q '^3 [0-9][0-9]* <sandbox>/home/d/here$' "$SCN_OUT/snap.files"; then echo "pass: the line of the real file has its size and time"; else echo "fail: the line: $(cat "$SCN_OUT/snap.files")"; fail=1; fi
exit "$fail"
