#!/bin/sh
# Copies corpus/ and facts/ into python/src/agent_signals/data/, so that the
# Python package holds them. Run it from any folder after each change of the
# corpus. tools/sync-go-data.sh runs this script too.
set -eu
root="$(cd "$(dirname "$0")/.." && pwd)"
dest="$root/python/src/agent_signals/data"
rm -rf "$dest"
mkdir -p "$dest"
cp -R "$root/corpus" "$dest/corpus"
cp -R "$root/facts" "$dest/facts"
