#!/bin/sh
# Read-only probe of GitHub Copilot CLI sessions on Linux and macOS.
#
# It reads process data, the open session files (fact 30), the layout of
# ~/.copilot, and the keys of its config files. It reads no conversation
# text.
# Run: sh probes/copilot/unix.sh > copilot-probe.txt 2>&1
# The output holds real paths. Send it through tools/scrub.sh first.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=probes/lib.sh
. "$here/lib.sh"

header copilot/unix.sh 1 copilot
c=$HOME/.copilot
p=$(pids '(^|[ /])copilot( |$)|/copilot-(linux|darwin)-[a-z0-9]+/copilot')

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

section "Folder and open session files (inuse.<pid>.hold)"
[ -n "$p" ] || none
for x in $p; do
  echo "== $x cwd: $(cwd "$x")"
  open_files "$x" '\.copilot/'
done

section "Layout of ~/.copilot (one level) and the session folders"
layout "$c" 1
echo "session folders: $(find "$c/session-state" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
d=$(ls -td "$c"/session-state/*/ 2>/dev/null | head -n 1)
[ -n "$d" ] && { echo "newest session folder:"; layout "$d" 1; }

section "Config files: keys (no values)"
for f in "$c/config.json" "$c/open-sessions-state.json"; do
  if [ -f "$f" ]; then
    echo "== $f"
    json_keys "$f"
  else
    echo "not found: $f"
  fi
done
exit 0
