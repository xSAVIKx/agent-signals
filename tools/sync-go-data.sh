#!/bin/sh
# Copies corpus/ and facts/ into go/data/, so that the Go library can embed
# them. Then it runs tools/sync-python-data.sh, which makes the copy for the
# Python package. Run it from any folder after each change of the corpus.
set -eu
root="$(cd "$(dirname "$0")/.." && pwd)"
rm -rf "$root/go/data"
mkdir -p "$root/go/data"
cp -R "$root/corpus" "$root/go/data/corpus"
cp -R "$root/facts" "$root/go/data/facts"
sh "$root/tools/sync-python-data.sh"
