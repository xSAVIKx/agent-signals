#!/bin/sh
# Check the output of a probe: it has one "### N." header for each section
# that the probe declares, in order, and the header holds the OS and the
# CPU type.
# Usage: sh tools/check-probe-output.sh PROBE OUTPUT
set -eu
probe=$1
output=$2
# A shell probe calls "section" and "header"; a PowerShell probe calls
# "Invoke-Section" and "Header". The header adds one section.
want=$(grep -c -E "^[[:space:]]*([Ss]ection|Invoke-Section) [\"']" "$probe" || true)
grep -q -E '^[[:space:]]*[Hh]eader ' "$probe" && want=$((want + 1))
got=$(grep -c '^### [0-9][0-9]*\. ' "$output" || true)
fail=0
if [ "$got" -ne "$want" ]; then
  echo "check: $probe: $got sections, want $want" >&2
  fail=1
fi
i=1
while [ "$i" -le "$want" ]; do
  grep -q "^### $i\. " "$output" || { echo "check: $probe: no section $i" >&2; fail=1; }
  i=$((i + 1))
done
for k in os cpu; do
  grep -q "^$k: " "$output" || { echo "check: $probe: no \"$k:\" line" >&2; fail=1; }
done
[ "$fail" -eq 0 ] && echo "check: $probe: $got sections, pass"
exit "$fail"
