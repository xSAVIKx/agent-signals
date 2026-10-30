#!/bin/sh
# Scenario: agy --continue and agy --conversation <id>.
#
# It starts agy four times in the same throwaway HOME and work folder:
#   1. agy, no prompt (the wizard and the trust question only);
#   2. agy --continue, before any conversation exists, then one turn;
#   3. agy --continue, then one turn;
#   4. agy --conversation <id>, then one turn.
# At each step it records the screen, the hooks, the open files, the
# files below ~/.gemini, the kernel locks and the transcript records.
# It answers:
#   1. Does a new process reuse presence/<id>.lock and
#      conversations/<id>.db of the earlier conversation?
#   2. Does SessionStart fire again for a continued conversation?
#   3. What does agy --continue draw when no conversation exists?
#
# Needs: agy, tmux, python3, flock, and an agy login in REAL_HOME (copied).
# Cost: three short turns on the plan of the login.
# Run: sh scenarios/agy/continue.sh
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=scenarios/lib.sh
. "$here/lib.sh"
# shellcheck source=scenarios/agy/agy.sh
. "$here/agy/agy.sh"

SCN_NAME=agy-continue
sandbox_start
copy_login agy || die "no agy login"
mkdir -p "$SCN_HOME/.gemini/config"
agy_hooks "$SCN_HOME/.gemini/config/hooks.json"

# turn WORD STEP: ask for one word, wait for the idle footer, record.
turn() {
  note "turn $1 sent"
  send_text "Reply with the single word $1. Do not do anything else."
  send_key Enter
  sleep 3
  wait_for 'for shortcuts' 90 || note "no idle footer after turn $1"
  sleep 4
  agy_step "$2"
}

# 1. The first start: the wizard and the trust question. No prompt.
tmux_start agy
note "start 1: agy"
agy_wizard
wait_for 'for shortcuts' 30 || note "no idle footer seen"
sleep 2
agy_step 01-first-start
agy_exit
agy_step 02-after-exit-1

# 2. --continue with no conversation in this folder.
tmux_start agy --continue
note "start 2: agy --continue"
agy_wizard
sleep 6
agy_step 03-continue-empty
turn one 04-turn-one
agy_exit
agy_step 05-after-exit-2

# 3. --continue with one conversation.
tmux_start agy --continue
note "start 3: agy --continue"
agy_wizard
sleep 6
agy_step 06-continue
turn two 07-turn-two
agy_exit
agy_step 08-after-exit-3

# 4. --conversation <id>, with the id of the newest conversation file.
id=$(ls -t "$SCN_HOME/$AGY_DIR_REL/conversations/" | sed -n 's/\.db$//p' | head -n 1)
[ -n "$id" ] || die "no conversation file"
n=0
for f in "$SCN_HOME/$AGY_DIR_REL"/conversations/*.db; do [ -f "$f" ] && n=$((n + 1)); done
note "conversations: $n"
tmux_start agy --conversation "$id"
note "start 4: agy --conversation"
agy_wizard
sleep 6
agy_step 09-conversation
turn three 10-turn-three
agy_exit
agy_step 11-after-exit-4
echo "done: $SCN_OUT"
