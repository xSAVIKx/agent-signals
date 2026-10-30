#!/bin/sh
# Scenario: an approval dialog, an interrupt and a resume in Codex CLI.
#
# It records, at each step: the screen, the process tree, the open files of
# the tree, and the list of files below ~/.codex. It answers:
#   1. Does the TUI hold its rollout file open? From when?
#   2. Is the sandbox helper a direct child of the TUI?
#   3. Which record does the rollout file get after Esc on an approval?
#   4. Does `codex resume --last` append to the old rollout file?
#
# Needs: codex, tmux, python3, and a Codex login in REAL_HOME (copied).
# Cost: three short turns on the plan of the login.
# Run: sh scenarios/codex/approval.sh
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=scenarios/lib.sh
. "$here/lib.sh"

# CODEX_DAEMON=0 adds --no-daemon.
daemon_flag=
[ "${CODEX_DAEMON:-1}" = 0 ] && daemon_flag=--no-daemon
SCN_NAME=codex-approval-daemon-${CODEX_DAEMON:-1}
sandbox_start
copy_login codex || die "no Codex login that is safe to copy"

step() {
  capture "$1"
  processes "$1" "$(agent_pid)"
  open_files "$1" "$(agent_pid)"
  # The daemon can outlive the TUI, so record it on its own too.
  for d in $(sandbox_pids); do
    ps -o pid=,ppid=,tty=,args= -p "$d" 2>/dev/null | cut -c1-160
    for f in /proc/"$d"/fd/*; do readlink "$f" 2>/dev/null; done |
      grep -E 'sessions/|thread-writer' | sed "s#^#  open: #"
  done | sed "s#$SCN_DIR#<sandbox>#g" >"$SCN_OUT/$1.daemons"
  snapshot_files "$1" "$SCN_HOME/.codex"
  record_types "$1" "$SCN_HOME/.codex/sessions"
  note "step $1"
}

prompt="Create a file named note.txt that holds the word hello. Do not do anything else."

# The read-only sandbox and the on-request policy: a file write needs approval.
# shellcheck disable=SC2086
tmux_start codex $daemon_flag --sandbox read-only --ask-for-approval on-request
note "started"
sleep 8
step 01-start
# A trust question can come first. Answer "yes" with its first option.
if screen | grep -Eqi 'trust|Do you trust'; then
  send_key 1
  sleep 1
  send_key Enter
  sleep 5
fi
wait_for 'for shortcuts|context left|›' 30 || note "no input box seen"
step 02-idle

send_text "$prompt"
send_key Enter
wait_for 'Would you like|Allow|approve|Yes, proceed' 120 || note "no approval dialog seen"
sleep 3
step 03-approval

send_key Escape
sleep 6
step 04-after-escape

send_text "$prompt"
send_key Enter
wait_for 'Would you like|Allow|approve|Yes, proceed' 120 || note "no second approval dialog seen"
sleep 2
step 05-approval-again
send_key 1
sleep 1
send_key Enter
sleep 15
step 06-after-approve

# Exit, then resume the same session in a new process.
# The TUI can exit after the first C-c, so a failed send is not an error.
send_key C-c || true
sleep 1
send_key C-c || true
sleep 4
step 07-after-exit
tmux -L "$SCN_SOCK" kill-server 2>/dev/null || true
sleep 1
# shellcheck disable=SC2086
tmux_start codex resume --last $daemon_flag --sandbox read-only --ask-for-approval on-request
sleep 10
step 08-resumed
send_text "Reply with the single word done."
send_key Enter
sleep 20
step 09-after-resume-turn

[ -f "$SCN_WORK/note.txt" ] && note "note.txt exists" || note "note.txt does not exist"
echo "done: $SCN_OUT"
