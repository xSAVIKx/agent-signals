#!/bin/sh
# Scenario: Ctrl+C and Esc during a turn of Codex CLI, with a command hook
# for each hook event.
#
# It records, at each step: the screen, the record types of the rollout
# file, and whether the TUI process still runs. The hooks write the
# top-level keys of each payload to hooks.log (no values). It answers:
#   1. What does Ctrl+C do while a turn runs? Which records follow?
#   2. Which records does the rollout file get after Esc while a command
#      (sleep 20) runs?
#   3. What do the options "1. Cancel task" and "3. Exit" of the dialog
#      after Ctrl+C do? Does the TUI exit?
#   4. Which hooks fire for each interrupt?
#
# Needs: codex, tmux, python3, and a Codex login in REAL_HOME (copied).
# Cost: four short turns, each with one approved command, on the plan of
# the login.
# Run: sh scenarios/codex/interrupt.sh
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=scenarios/lib.sh
. "$here/lib.sh"

SCN_NAME=codex-interrupt
sandbox_start
copy_login codex || die "no Codex login that is safe to copy"
codex_hooks

step() {
  capture "$1"
  p=$(agent_pid)
  if [ "$p" -gt 0 ] && kill -0 "$p" 2>/dev/null; then
    note "tui $p runs"
  else
    note "no tui process"
  fi
  record_types "$1" "$SCN_HOME/.codex/sessions"
  note "step $1"
}

idle='\? for shortcuts'
running='sleep 20'
# The dialog that Ctrl+C opens while a turn runs.
still='Task is still running'
# A command that runs for 20 s. The prompt holds no digit other than in
# the command, because a digit answers a numbered dialog (fact 4).
sleeper="Run the shell command sleep 20 once outside the sandbox: request approval for it. Then reply with the single word done."

ask() {
  send_text "$1"
  send_key Enter
}

# run_sleep: ask for the command, approve it with "1. Yes, proceed", and
# wait until it runs. On this machine the bwrap sandbox cannot make a
# namespace, so a command in the sandbox fails at once. An approved
# command runs outside the sandbox.
run_sleep() {
  ask "$sleeper"
  wait_for 'Would you like' 60 || note "no approval dialog seen"
  sleep 1
  send_key 1
  wait_for "Running.*$running" 20 || note "no running sleep command seen"
  sleep 3
}

tmux_start codex --sandbox read-only --ask-for-approval on-request
note "started"
sleep 8
if screen | grep -Eqi 'Trust this folder|Do you trust'; then
  send_key 1
  sleep 1
  send_key Enter
  sleep 5
fi
# The hooks review dialog: the digit 2 selects "Trust all", Enter confirms.
if screen | grep -Eq 'Hooks need review'; then
  step 01-hooks-review
  send_key 2
  sleep 1
  send_key Enter
  sleep 3
fi
wait_for "$idle" 30 || note "no input box seen"
step 02-idle

# 1. Ctrl+C while a command runs, then "1. Cancel task".
run_sleep
step 03-command-runs
send_key C-c
sleep 1
step 04-after-ctrl-c
send_key 1
sleep 1
step 05-after-1
if screen | grep -q "$still"; then
  send_key Enter
  sleep 1
  step 05b-after-enter
fi
sleep 6
step 06-after-cancel-later

# 2. Esc while a command runs.
run_sleep
step 07-command-runs
send_key Escape
sleep 1
step 08-after-escape
sleep 6
step 09-after-escape-later

# 3. Ctrl+C while a command runs, then Esc on the dialog: does the turn go on?
run_sleep
send_key C-c
sleep 1
step 10-ctrl-c-dialog
send_key Escape
sleep 2
step 11-after-dialog-escape
# The footer "? for shortcuts" stays drawn during a turn (fact 20), so
# wait for the end of the command.
sleep 20
step 12-after-turn

# 4. Ctrl+C while a command runs, then "3. Exit".
run_sleep
send_key C-c
sleep 1
step 13-ctrl-c-dialog
send_key 3
sleep 1
if screen 2>/dev/null | grep -q "$still"; then
  send_key Enter
fi
sleep 6
step 14-after-exit
echo "done: $SCN_OUT"
