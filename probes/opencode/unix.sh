#!/bin/sh
# Read-only probe of opencode sessions on Linux and macOS.
#
# It reads process data, open file names, and the layout of the opencode
# data, config, state and cache folders. It reads no conversation text.
# Run: sh probes/opencode/unix.sh > opencode-probe.txt 2>&1
# The output holds real paths. Send it through tools/scrub.sh first.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=probes/lib.sh
. "$here/lib.sh"

header opencode/unix.sh 1 opencode
p=$(pids '(^|[ /])opencode( |$)')
data=${XDG_DATA_HOME:-$HOME/.local/share}/opencode

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

section "Folder and open opencode files of each process"
[ -n "$p" ] || none
for x in $p; do
  echo "== $x cwd: $(cwd "$x")"
  open_files "$x" 'opencode'
done

section "Layout of the opencode folders (two levels)"
for d in "$data" "${XDG_CONFIG_HOME:-$HOME/.config}/opencode" \
  "${XDG_STATE_HOME:-$HOME/.local/state}/opencode" "${XDG_CACHE_HOME:-$HOME/.cache}/opencode" \
  "$HOME/Library/Application Support/opencode"; do
  echo "== $d"
  layout "$d" 2
done

section "Newest session file: record types (no text)"
t=$(find "$data" -name '*.json' -path '*session*' 2>/dev/null | head -n 200 | xargs ls -t 2>/dev/null | head -n 1)
if [ -n "$t" ]; then
  echo "file: $t"
  json_keys "$t"
else
  none
fi
exit 0
