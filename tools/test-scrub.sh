#!/bin/sh
# Test tools/scrub.sh against the fixtures in tools/testdata/scrub/:
# input.txt (LF line ends) and crlf-input.txt (CRLF line ends).
# Run: sh tools/test-scrub.sh
set -eu
dir=$(cd "$(dirname "$0")" && pwd)
out=$(mktemp)
trap 'rm -f "$out"' EXIT
fail=0
for name in input crlf-input; do
  exp=$dir/testdata/scrub/$(printf '%s' "$name" | sed 's/input$/expected/').txt
  SCRUB_HOME=/Users/alice SCRUB_USER=alice SCRUB_HOST=alice-mbp.local \
    SCRUB_EXTRA='/opt/kit runs
/var/tmp/agent-signals-run-linux-20260101T000000Z' SCRUB_DOMAIN=CONTOSO OneDrive='C:\Users\alice\OneDrive - Contoso' \
    OneDriveCommercial='' OneDriveConsumer='' \
    sh "$dir/scrub.sh" "$dir/testdata/scrub/$name.txt" >"$out" 2>/dev/null
  if ! diff -u "$exp" "$out"; then
    echo "test-scrub: $name.txt: fail" >&2
    fail=1
  fi
done
if [ "$fail" -ne 0 ]; then
  echo "test-scrub: fail" >&2
  exit 1
fi
echo "test-scrub: pass"
