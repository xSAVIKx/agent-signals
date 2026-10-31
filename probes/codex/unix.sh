#!/bin/sh
# Read-only probe of Codex CLI sessions on Linux and macOS.
#
# It reads process data, the open session files of the TUI and of the
# app-server daemon, the layout of ~/.codex, and the record types of the
# newest rollout file. It reads no conversation text.
# Run: sh probes/codex/unix.sh > codex-probe.txt 2>&1
# The output holds real paths. Send it through tools/scrub.sh first.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=probes/lib.sh
. "$here/lib.sh"

header codex/unix.sh 1 codex
c=${CODEX_HOME:-$HOME/.codex}
tui=$(pids '(^|[ /])codex( |$)' | while read -r x; do
  ps -o args= -p "$x" 2>/dev/null | grep -q 'app-server' || echo "$x"
done)
daemon=$(pids 'codex app-server')

section "TUI processes: pid ppid tty start command"
[ -n "$tui" ] || none
for x in $tui; do ps_line "$x"; done

section "App-server daemon processes (fact 26)"
[ -n "$daemon" ] || none
for x in $daemon; do ps_line "$x"; done

section "Parent chain, terminal and children of each TUI"
[ -n "$tui" ] || none
for x in $tui; do
  echo "== $x"
  chain "$x"
  terminal_env "$x"
  echo "children:"
  for k in $(children "$x"); do [ "$k" = "$x" ] || ps_line "$k"; done
done

section "Open session files: rollout files and thread locks"
[ -n "$tui$daemon" ] || none
for x in $tui $daemon; do
  echo "== $x cwd: $(cwd "$x")"
  open_files "$x" 'sessions/.*\.jsonl|thread-writer-locks/[0-9a-f]'
done

section "Layout of ~/.codex (one level) and the newest sessions"
layout "$c" 1
echo "thread locks:"
layout "$c/thread-writer-locks" 1 | head -n 20
echo "newest rollout files:"
# shellcheck disable=SC2012
ls -t "$c"/sessions/*/*/*/rollout-*.jsonl 2>/dev/null | head -n 5

section "Newest rollout file: record types of the last 20 lines (no text)"
t=$(newest "$c"/sessions/*/*/*/rollout-*.jsonl)
if [ -n "$t" ]; then
  echo "rollout: $t"
  jsonl_types "$t" 20
else
  none
fi

section "Install: the version in the package path"
layout "$c/packages" 4 | grep -E 'releases/[^/]+$|bin/codex$' | head -n 20
[ -d "$c/packages" ] || none

section "Config: table names of config.toml and hooks files (no values)"
# Table names such as [projects."<path>"] and [mcp_servers.<name>] hold
# paths and names. toml_tables prints them in a general form, with a count.
toml_tables "$c/config.toml"
for h in "$c/hooks.json" "$c/hooks.toml"; do
  [ -f "$h" ] && { echo "== $h"; json_keys "$h"; }
done
exit 0
