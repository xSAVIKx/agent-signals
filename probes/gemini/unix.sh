#!/bin/sh
# Read-only probe of Gemini CLI sessions on Linux and macOS.
#
# It reads process data, open file names, and the layout of ~/.gemini
# without the folders of agy (antigravity-cli, config). It reads no
# conversation text.
# Run: sh probes/gemini/unix.sh > gemini-probe.txt 2>&1
# The output holds real paths. Send it through tools/scrub.sh first.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=probes/lib.sh
. "$here/lib.sh"

header gemini/unix.sh 1 gemini
g=$HOME/.gemini
p=$(pids '(^|[ /])gemini( |$)')

section "Processes: pid ppid tty start command"
[ -n "$p" ] || none
for x in $p; do ps_line "$x"; done

section "Parent chain and terminal of each process"
[ -n "$p" ] || none
for x in $p; do
  echo "== $x"
  chain "$x"
  terminal_env "$x"
done

section "Folder and open Gemini files of each process"
[ -n "$p" ] || none
for x in $p; do
  echo "== $x cwd: $(cwd "$x")"
  open_files "$x" '\.gemini/' | grep -v 'antigravity-cli/'
done

section "Layout of ~/.gemini (one level, agy folders left out)"
layout "$g" 1 | grep -v -E '/(antigravity-cli|config)$'
echo "tmp folders: $(find "$g/tmp" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"

section "Newest session file below ~/.gemini/tmp: keys or record types (no text)"
t=$(find "$g/tmp" -type f \( -name '*.json' -o -name '*.jsonl' \) 2>/dev/null | head -n 500 | xargs ls -t 2>/dev/null | head -n 1)
if [ -z "$t" ]; then
  none
else
  # The folder below tmp/ is named after the project, so it is hidden.
  echo "file: $(echo "$t" | sed 's#/tmp/[^/]*/#/tmp/<project>/#')"
  case $t in
    *.jsonl) jsonl_types "$t" 20 ;;
    *) json_keys "$t" ;;
  esac
fi

section "Settings: keys and hook events (no values)"
s=$g/settings.json
if [ -f "$s" ]; then
  json_keys "$s"
  need python3 >/dev/null && python3 -c '
import json, sys
h = json.load(open(sys.argv[1])).get("hooks") or {}
print("  hook events:", sorted(h) if isinstance(h, dict) else type(h).__name__)
' "$s"
else
  echo "not found: $s"
fi
exit 0
