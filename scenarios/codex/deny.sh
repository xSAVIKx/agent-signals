#!/bin/sh
# Scenario: a denial with "3. No" on the approval dialog of Codex CLI, with
# a command hook for each hook event.
#
# It records, at each step: the screen, the record types of the rollout
# file, and the files below ~/.codex. The hooks write the top-level keys of
# each payload to hooks.log (no values). It answers:
#   1. Which records does the rollout file get after "3. No, and tell
#      Codex what to do differently"? Does the turn end or go on?
#   2. What does the screen show after "3"?
#   3. Which hooks fire, with which payload keys, for a normal turn, an
#      approval, a denial with "3" and an Esc on the dialog?
#
# Needs: codex, tmux, python3, and a Codex login in REAL_HOME (copied).
# Cost: five short turns on the plan of the login.
# Run: sh scenarios/codex/deny.sh
# The screens hold the path of the throwaway folder. Scrub it to
# /work/example and record the edit before a screen goes into the corpus.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=scenarios/lib.sh
. "$here/lib.sh"

SCN_NAME=codex-deny
sandbox_start
copy_login codex || die "no Codex login that is safe to copy"
codex_hooks

step() {
  capture "$1"
  snapshot_files "$1" "$SCN_HOME/.codex"
  record_types "$1" "$SCN_HOME/.codex/sessions"
  note "step $1"
}

dialog='Would you like'
# The footer of an idle box after a turn.
idle='\? for shortcuts'

# ask TEXT: type TEXT and send it.
ask() {
  send_text "$1"
  send_key Enter
}

tmux_start codex --sandbox read-only --ask-for-approval on-request
note "started"
sleep 8
step 01-start
# A trust question can come first. Answer "yes" with its first option.
if screen | grep -Eqi 'Trust this folder|Do you trust'; then
  send_key 1
  sleep 1
  send_key Enter
  sleep 5
fi
# The hooks review dialog comes next. The digit 2 selects "2. Trust all
# and continue"; Enter confirms it.
if screen | grep -Eq 'Hooks need review'; then
  step 01b-hooks-review
  send_key 2
  sleep 1
  send_key Enter
  sleep 3
  step 01c-after-hooks-review
fi
wait_for "$idle" 30 || note "no input box seen"
step 02-idle

# write N: ask for a file write that needs an approval.
write() {
  ask "Create a file named $1 that holds the word hello. The workspace is read-only, so request approval for the write. Do not do anything else."
}

ask "Reply with the single word done."
sleep 15
step 03-after-normal-turn

# An approval with "1. Yes, proceed".
write note.txt
wait_for "$dialog" 120 || note "no first approval dialog seen"
sleep 3
step 04-approval
# A digit answers a numbered dialog (fact 4). Send no Enter.
send_key 1
sleep 15
step 05-after-approve

# Esc on the dialog.
write note2.txt
wait_for "$dialog" 120 || note "no second approval dialog seen"
sleep 3
step 06-approval-again
send_key Escape
sleep 6
step 07-after-escape

# The denial with "3. No, and tell Codex what to do differently". A model
# that saw a denial can refuse the next write with no dialog, so this
# comes last.
write note3.txt
wait_for "$dialog" 120 || note "no third approval dialog seen"
sleep 3
step 08-approval-third
send_key 3
sleep 3
step 09-after-3
sleep 5
step 10-after-3-later
ask "Do not create the file. Reply with the single word ok."
sleep 15
step 11-after-follow-up

# The TUI can exit after the first C-c, so a failed send is not an error.
send_key C-c || true
sleep 1
send_key C-c || true
sleep 5
step 12-after-exit

for f in note.txt note2.txt note3.txt; do
  [ -f "$SCN_WORK/$f" ] && note "$f exists" || note "$f does not exist"
done
echo "done: $SCN_OUT"
