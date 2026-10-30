#!/bin/sh
# Scenario: two Codex TUIs with the same HOME, in the default daemon mode.
#
# It answers: do the two TUIs share one app-server daemon, and which
# process holds the rollout file of each session?
#
# Needs: codex, tmux, python3, and a Codex login in REAL_HOME (copied).
# Cost: two short turns on the plan of the login.
# Run: sh scenarios/codex/two-sessions.sh
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=scenarios/lib.sh
. "$here/lib.sh"

SCN_NAME=codex-two-sessions
sandbox_start
copy_login codex || die "no Codex login that is safe to copy"

tmux_start codex --sandbox read-only --ask-for-approval on-request
tmux -L "$SCN_SOCK" new-window -t scn -c "$SCN_WORK" \
  sh -c 'exec codex --sandbox read-only --ask-for-approval on-request'
sleep 10
for w in 0 1; do
  tmux -L "$SCN_SOCK" send-keys -t "scn:$w" -l -- "Reply with the single word done."
  sleep 0.5
  tmux -L "$SCN_SOCK" send-keys -t "scn:$w" Enter
  sleep 2
done
sleep 20

# For each TUI: its pid. For each sandbox process: its parent and the
# session files that it holds open.
for w in 0 1; do
  echo "tui $w pid $(tmux -L "$SCN_SOCK" display -p -t "scn:$w" '#{pane_pid}')"
done >"$SCN_OUT/tuis"
for q in $(sandbox_pids); do
  pp=$(ps -o ppid= -p "$q" | tr -d ' ')
  for f in /proc/"$q"/fd/*; do readlink "$f" 2>/dev/null; done |
    grep -E 'sessions/.*jsonl|thread-writer-locks/[0-9a-f]' |
    sed "s#^#$q $pp #"
done | sed "s#$SCN_DIR#<sandbox>#g" | sort -u >"$SCN_OUT/holders"
note "done"
echo "done: $SCN_OUT"
