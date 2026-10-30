#!/bin/sh
# Scenario: agy hooks and files for a denied file write, for tool calls,
# and for an Esc; the presence lock; the files that change in a turn.
#
# It records, at each step: the screen, every hook payload (out/ only),
# the open files, the files below ~/.gemini, the kernel locks on the
# presence and conversation files, and the transcript record types. A
# poller lists each file change below ~/.gemini/antigravity-cli every
# 0.5 s.
# It answers:
#   1. Which hooks fire, and which transcript records appear, when the
#      operator answers "2. No, deny creation" on the file dialog?
#   2. Do PreToolUse and PostToolUse fire with the grouped "matcher"
#      shape? With which matcher, and which payload keys?
#   3. Is presence/<id>.lock an advisory lock (flock -n from another
#      process), while agy runs and after it exits?
#   4. Which files change while a turn runs, for a reader with no hooks?
#   5. The screens of agy 1.4.7: idle, busy, the file dialog, after Esc.
#
# Needs: agy, tmux, python3, flock, and an agy login in REAL_HOME (copied).
# Cost: four short turns on the plan of the login.
# Run: sh scenarios/agy/deny-and-tools.sh
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=scenarios/lib.sh
. "$here/lib.sh"
# shellcheck source=scenarios/agy/agy.sh
. "$here/agy/agy.sh"

SCN_NAME=agy-deny-and-tools
sandbox_start
copy_login agy || die "no agy login"
mkdir -p "$SCN_HOME/.gemini/config"
agy_hooks "$SCN_HOME/.gemini/config/hooks.json"
# A file for the read turn.
echo hello >"$SCN_WORK/hello.txt"

tmux_start agy
note "started"
agy_wizard
wait_for 'for shortcuts' 30 || note "no idle footer seen"
sleep 2
agy_step 01-idle
agy_poll_start

# Turn 1: a file write, denied with "2".
note "turn 1 sent"
send_text "Create a file named note.txt that holds the word hello. Do not do anything else."
send_key Enter
sleep 1.5
agy_step 02-busy
wait_for 'Allow creation of this file' 90 || note "no file dialog seen"
sleep 2
agy_step 03-file-dialog
note "deny sent"
send_key 2
sleep 3
agy_step 04-after-deny
wait_for 'for shortcuts' 60 || note "no idle footer after the deny"
sleep 5
agy_step 05-after-deny-idle

# Turn 2: a read, which needs no dialog.
note "turn 2 sent"
send_text "Show the content of the file hello.txt. Do not do anything else."
send_key Enter
sleep 1.5
agy_step 06-busy-read
if ! wait_for 'for shortcuts' 90; then
  # A dialog for the read is not expected. Record it and answer Esc.
  agy_step 06b-read-wait
  send_key Escape
  wait_for 'for shortcuts' 30 || note "no idle footer after the read"
fi
sleep 5
agy_step 07-after-read

# Turn 3: a file write, allowed with "1".
note "turn 3 sent"
send_text "Create a file named done.txt that holds the word done. Do not do anything else."
send_key Enter
wait_for 'Allow creation of this file' 90 || note "no file dialog seen"
sleep 2
note "allow sent"
send_key 1
wait_for 'for shortcuts' 90 || note "no idle footer after the allow"
sleep 5
agy_step 08-after-allow

# Turn 4: a file write, then Esc on the dialog.
note "turn 4 sent"
send_text "Create a file named esc.txt that holds the word esc. Do not do anything else."
send_key Enter
wait_for 'Allow creation of this file' 90 || note "no file dialog seen"
sleep 2
note "esc sent"
send_key Escape
sleep 4
agy_step 09-after-escape
sleep 10
agy_step 10-after-escape-later

# The lock files, for the test after the exit.
agy_exit
note "exited"
sleep 2
agy_poll_stop
agy_step 11-after-exit
ls "$SCN_WORK" >"$SCN_OUT/work.ls"
echo "done: $SCN_OUT"
