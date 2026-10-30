#!/bin/sh
# Scenario: the life of the Codex app-server daemon, a --no-daemon TUI next
# to it, and the table layout of the state database.
#
# It answers:
#   1. Which tables does ~/.codex/state_5.sqlite have while two TUIs run?
#      It reads only the layout (.tables and .schema), never a row.
#   2. Which process holds the rollout file of a `codex --no-daemon` TUI
#      that starts next to a running daemon?
#   3. Does a TUI that starts after the first TUIs exit use the same
#      daemon?
#   4. How long does the daemon live after the last TUI exits? It watches
#      for up to 300 s, and logs the pid and the release of the daemon
#      each 10 s.
#
# Needs: codex, tmux, python3 (or sqlite3), and a Codex login in REAL_HOME
# (copied).
# Cost: three short turns on the plan of the login.
# Run: sh scenarios/codex/daemon-life.sh
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=scenarios/lib.sh
. "$here/lib.sh"

SCN_NAME=codex-daemon-life
sandbox_start
copy_login codex || die "no Codex login that is safe to copy"

# daemons NAME: for each process that runs from the throwaway folder: pid,
# ppid and the command, then the session files and the databases that it
# holds open.
daemons() {
  for q in $(sandbox_pids); do
    ps -o pid=,ppid=,tty=,args= -p "$q" 2>/dev/null | cut -c1-200
    for f in /proc/"$q"/fd/*; do readlink "$f" 2>/dev/null; done |
      grep -E 'sessions/.*jsonl|thread-writer-locks/|\.sqlite' |
      sort -u | sed "s#^#  open: #"
  done | sed "s#$SCN_DIR#<sandbox>#g" >"$SCN_OUT/$1.daemons"
}

# holders NAME: the session files that each pid holds open, for the TUIs
# in the tmux windows and their trees, and for the sandbox processes.
holders() {
  {
    for w in $(tmux -L "$SCN_SOCK" list-windows -t scn -F '#{window_index}' 2>/dev/null); do
      tp=$(tmux -L "$SCN_SOCK" display -p -t "scn:$w" '#{pane_pid}')
      echo "window $w tui $tp"
      for p in $(tree "$tp"); do
        for f in /proc/"$p"/fd/*; do readlink "$f" 2>/dev/null; done |
          grep -E 'sessions/.*jsonl|thread-writer-locks/|\.sqlite' |
          sort -u | sed "s#^#  $p open: #"
      done
    done
  } | sed "s#$SCN_DIR#<sandbox>#g" >"$SCN_OUT/$1.holders"
  daemons "$1"
}

# daemon_pid: the pid of the app-server daemon, or nothing.
daemon_pid() {
  for q in $(sandbox_pids); do
    ps -o args= -p "$q" 2>/dev/null | grep -q -- '--managed-daemon' && echo "$q"
  done | head -1
}

# daemon_desc: the pid, the parent pid and the release folder (the
# version) of the app-server daemon, or "none".
daemon_desc() {
  d=$(daemon_pid)
  if [ -z "$d" ]; then
    echo none
    return
  fi
  v=$(ps -o args= -p "$d" | sed -n 's#.*/releases/\([^/]*\)/bin/.*#\1#p')
  echo "pid $d ppid $(ps -o ppid= -p "$d" | tr -d ' ') release $v"
}

# start_tui WINDOW ARGS...: start a TUI in a new window of the tmux server.
start_tui() {
  w=$1
  shift
  tmux -L "$SCN_SOCK" new-window -t "scn:$w" -c "$SCN_WORK" \
    sh -c 'exec codex "$@"' codex "$@"
}

# answer_trust WINDOW: answer the folder-trust question, when it shows.
answer_trust() {
  if tmux -L "$SCN_SOCK" capture-pane -p -t "scn:$1" | grep -Eqi 'Trust this folder'; then
    tmux -L "$SCN_SOCK" send-keys -t "scn:$1" 1
    sleep 1
    tmux -L "$SCN_SOCK" send-keys -t "scn:$1" Enter
    sleep 5
  fi
}

# turn WINDOW: send one short prompt to the TUI in WINDOW.
turn() {
  tmux -L "$SCN_SOCK" send-keys -t "scn:$1" -l -- "Reply with the single word done."
  sleep 0.5
  tmux -L "$SCN_SOCK" send-keys -t "scn:$1" Enter
}

# quit WINDOW: exit the TUI in WINDOW with two Ctrl+C.
quit() {
  tmux -L "$SCN_SOCK" send-keys -t "scn:$1" C-c 2>/dev/null || true
  sleep 1
  tmux -L "$SCN_SOCK" send-keys -t "scn:$1" C-c 2>/dev/null || true
  sleep 3
}

flags="--sandbox read-only --ask-for-approval on-request"

# Window 0: TUI A. Window 1: TUI B. Both in the default daemon mode.
# shellcheck disable=SC2086
tmux_start codex $flags
sleep 8
answer_trust 0
# shellcheck disable=SC2086
start_tui 1 $flags
sleep 8
answer_trust 1
turn 0
sleep 2
turn 1
sleep 25
note "daemon after two TUIs: $(daemon_desc)"
holders 01-two-tuis

# The table layout of the state databases. No rows.
for db in "$SCN_HOME"/.codex/*.sqlite; do
  [ -f "$db" ] || continue
  b=$(basename "$db")
  if command -v sqlite3 >/dev/null 2>&1; then
    sqlite3 -readonly "$db" ".tables" >"$SCN_OUT/$b.tables" 2>&1 || true
    sqlite3 -readonly "$db" ".schema" >"$SCN_OUT/$b.schema" 2>&1 || true
  else
    python3 - "$db" >"$SCN_OUT/$b.schema" 2>&1 <<'PY' || true
import sqlite3, sys
c = sqlite3.connect("file:%s?mode=ro" % sys.argv[1], uri=True)
for (s,) in c.execute("select sql from sqlite_master where sql is not null"):
    print(s + ";")
PY
  fi
done
ls -la "$SCN_HOME/.codex" | sed "s#$SCN_DIR#<sandbox>#g" >"$SCN_OUT/01-codex-home.ls"
note "schema read"

# Window 2: a --no-daemon TUI next to the daemon.
# shellcheck disable=SC2086
start_tui 2 --no-daemon $flags
sleep 8
answer_trust 2
turn 2
sleep 25
note "daemon with a --no-daemon TUI: $(daemon_desc)"
holders 02-no-daemon-next-to-daemon

d1=$(daemon_pid)
quit 2
quit 1
quit 0
note "all TUIs asked to exit; daemon $(daemon_desc)"
note "windows that still run: $(tmux -L "$SCN_SOCK" list-windows -t scn -F '#{window_index}' 2>/dev/null | tr '\n' ' ')"
holders 03-after-exit
# The hangup ends each TUI that did not exit on Ctrl+C.
tmux -L "$SCN_SOCK" kill-server 2>/dev/null || true
sleep 30
note "30 s after exit; daemon $(daemon_desc)"

# TUI C, after the first TUIs exited.
# shellcheck disable=SC2086
tmux_start codex $flags
sleep 10
answer_trust 0
d2=$(daemon_pid)
note "daemon with TUI C: $d2 (before: $d1); $(daemon_desc)"
holders 04-tui-c
turn 0
sleep 20
holders 05-tui-c-after-turn
quit 0
note "windows that still run: $(tmux -L "$SCN_SOCK" list-windows -t scn -F '#{window_index}' 2>/dev/null | tr '\n' ' ')"
tmux -L "$SCN_SOCK" kill-server 2>/dev/null || true
t0=$(date +%s)
note "TUI C exited; daemon $(daemon_desc)"

# Watch the daemon for up to 300 s. Log it each 10 s, because the
# daemon can change its pid and its version (fact 26).
while :; do
  now=$(($(date +%s) - t0))
  d=$(daemon_pid)
  note "watch $now s: $(daemon_desc)"
  if [ -z "$d" ]; then
    note "no daemon $now s after the last TUI"
    break
  fi
  if [ "$now" -ge 300 ]; then
    note "the daemon $d still runs $now s after the last TUI"
    daemons 06-after-300s
    break
  fi
  sleep 10
done
echo "done: $SCN_OUT"
