#!/bin/sh
# Read-only probe of Cursor CLI sessions on Linux and macOS.
#
# It reads process data, the open chat files (facts 21 and 22), the layout
# of the newest chat folder, the keys of meta.json, the record types of the
# newest transcript, the hooks file, and the login state. It reads no chat
# text and opens no chat database.
# Run: sh probes/cursor/unix.sh > cursor-probe.txt 2>&1
# The output holds real paths. Send it through tools/scrub.sh first.
# On macOS, also run probes/terminals/macos.sh for the terminal tabs.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=probes/lib.sh
. "$here/lib.sh"

header cursor/unix.sh 2 cursor-agent agent
c=$HOME/.cursor
p=$(pids 'cursor-agent|(^|[ /])agent .*index\.js|/\.local/bin/agent( |$)')

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

section "Folder and open Cursor files of each process"
[ -n "$p" ] || none
for x in $p; do
  echo "== $x cwd: $(cwd "$x")"
  open_files "$x" '/\.cursor/'
done

section "Layout of the newest chat folder (no content)"
# A live store.db cannot be opened, and a copy would hold chat text. This
# section lists names, sizes and times, and the keys of the JSON files.
f=$(newest "$c"/chats/*/*/store.db)
if [ -z "$f" ]; then
  none
else
  d=$(dirname "$f")
  echo "folder: $d"
  layout "$d" 1
  for j in "$d"/*.json; do
    [ -f "$j" ] || continue
    echo "json: $(basename "$j")"
    json_keys "$j"
  done
fi
echo "chat folders: $(find "$c/chats" -mindepth 2 -maxdepth 2 -type d 2>/dev/null | wc -l | tr -d ' ')"

section "Newest transcript: record types of the last 20 lines (no text)"
t=$(newest "$c"/projects/*/agent-transcripts/*/*.jsonl)
if [ -n "$t" ]; then
  echo "transcript: $t"
  jsonl_types "$t" 20
else
  none
fi

section "Hooks and config"
for h in "$c/hooks.json" "$c/cli-config.json"; do
  if [ -f "$h" ]; then
    echo "== $h"
    json_keys "$h"
  else
    echo "not found: $h"
  fi
done
for h in .claude/settings.json .cursor/hooks.json; do
  [ -f "$h" ] && echo "project file: $h (in $(pwd))"
done

section "Login state (no account names)"
for cmd in cursor-agent agent; do
  if command -v "$cmd" >/dev/null 2>&1; then
    # "status" prints the state and starts no login.
    s=$("$cmd" status </dev/null 2>&1 | head -n 1)
    case $s in
      *"Not logged in"*) echo "$cmd: not logged in" ;;
      "") echo "$cmd: no output" ;;
      *) echo "$cmd: logged in or other state" ;;
    esac
    break
  fi
done

section "Install: versions folder"
layout "$HOME/.local/share/cursor-agent/versions" 1 | head -n 10
exit 0
