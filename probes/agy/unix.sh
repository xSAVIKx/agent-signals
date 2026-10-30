#!/bin/sh
# Read-only probe of Antigravity CLI (agy) sessions on Linux and macOS.
#
# It reads process data, the open conversation files, the layout of
# ~/.gemini, the hook groups and events, and the record types of the newest
# transcript. It reads no conversation text.
# Run: sh probes/agy/unix.sh > agy-probe.txt 2>&1
# The output holds real paths. Send it through tools/scrub.sh first.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=probes/lib.sh
. "$here/lib.sh"

header agy/unix.sh 1 agy
g=$HOME/.gemini
a=$g/antigravity-cli
p=$(pids '(^|[ /])agy( |$)')

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

section "Folder and open conversation files (fact 28)"
[ -n "$p" ] || none
for x in $p; do
  echo "== $x cwd: $(cwd "$x")"
  open_files "$x" 'antigravity-cli/(presence|conversations)/'
done

section "Layout of ~/.gemini/antigravity-cli (one level)"
layout "$a" 1
echo "presence locks: $(find "$a/presence" -name '*.lock' 2>/dev/null | wc -l | tr -d ' ')"
echo "conversations: $(find "$a/conversations" -name '*.db' 2>/dev/null | wc -l | tr -d ' ')"

section "Newest transcript: record types of the last 20 lines (no text)"
t=$(newest "$a"/brain/*/.system_generated/logs/transcript.jsonl)
if [ -n "$t" ]; then
  echo "transcript: $t"
  jsonl_types "$t" 20
else
  none
fi

section "Hooks: groups and events (no commands)"
h=$g/config/hooks.json
if [ -f "$h" ] && need python3; then
  python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
for g, ev in (d.items() if isinstance(d, dict) else []):
    print(" ", "group:", "<group>", "events:", sorted(ev) if isinstance(ev, dict) else type(ev).__name__)
' "$h"
else
  echo "not found: $h"
fi

section "Logs: names and sizes"
layout "$a/log" 1 | tail -n 5
exit 0
