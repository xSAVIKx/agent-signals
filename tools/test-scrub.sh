#!/bin/sh
# Test tools/scrub.sh against the fixture in tools/testdata/scrub/.
# Run: sh tools/test-scrub.sh
set -eu
dir=$(cd "$(dirname "$0")" && pwd)
out=$(mktemp)
trap 'rm -f "$out"' EXIT
SCRUB_HOME=/Users/alice SCRUB_USER=alice SCRUB_HOST=alice-mbp.local \
  sh "$dir/scrub.sh" "$dir/testdata/scrub/input.txt" >"$out" 2>/dev/null
if diff -u "$dir/testdata/scrub/expected.txt" "$out"; then
  echo "test-scrub: pass"
else
  echo "test-scrub: fail" >&2
  exit 1
fi
