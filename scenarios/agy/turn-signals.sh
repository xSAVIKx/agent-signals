#!/bin/sh
# Scenario: the signals of an agy turn that do not come from the screen.
#
# It records, at each step: the screen, every hook payload, the open files
# of the process tree, and the files below ~/.gemini (names, sizes, times).
# It answers:
#   1. Which hooks fire at the start and at the end of a turn?
#   2. Does a file show that a turn runs (busy) or that it ended?
#   3. Which file links the process to its conversation?
#   4. What do the hooks and files show for a permission dialog and an Esc?
#
# Needs: agy, tmux, python3, and an agy login in REAL_HOME (copied).
# Cost: three short turns on the plan of the login.
# Run: sh scenarios/agy/turn-signals.sh
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=scenarios/lib.sh
. "$here/lib.sh"

SCN_NAME=agy-turn-signals
sandbox_start
copy_login agy || die "no agy login"

# Each hook appends "<event> <payload>" as one line. The environment of
# the hook goes into the same file, names only.
mkdir -p "$SCN_HOME/.gemini/config"
python3 - "$SCN_HOME/.gemini/config/hooks.json" "$SCN_OUT/hooks.txt" <<'PY'
import json, sys
out = sys.argv[2]
events = ["SessionStart", "PreInvocation", "PostInvocation", "PreToolUse",
          "PostToolUse", "Stop"]
hooks = {}
for e in events:
    cmd = ("{ date -u +%%H:%%M:%%S | tr -d '\\n'; printf ' %s '; tr -d '\\n'; "
           "printf ' ENV:'; env | sed 's/=.*//' | "
           "grep -Ei 'antigravity|gemini|agy|jetski' | tr '\\n' ','; echo; } >> '%s'") % (e, out)
    hooks[e] = [{"type": "command", "command": cmd, "timeout": 10}]
json.dump({"agent-signals": hooks}, open(sys.argv[1], "w"), indent=1)
PY

step() {
  capture "$1"
  processes "$1" "$(agent_pid)"
  scn_open_files "$1" "$(agent_pid)"
  snapshot_files "$1" "$SCN_HOME/.gemini"
  record_types "$1" "$SCN_HOME/.gemini/antigravity-cli/brain"
  note "step $1"
}

tmux_start agy
note "started"
sleep 10
step 01-start
# A new install shows a wizard: a colour page, then the terms page. The
# terms page has a box that opts in to data collection, checked by
# default. Clear it. Stop if it is still checked.
if screen | grep -q 'Navigate · enter Confirm' && screen | grep -q '\[Next\]'; then
  send_key Enter
  sleep 2
fi
if screen | grep -q 'Terms of Service & Data Use'; then
  screen | grep -q '\[x\] Yes, I agree' && send_key Enter
  sleep 1
  screen | grep -q '\[ \] Yes, I agree' || die "the data box is still checked"
  send_key Down
  sleep 0.5
  send_key Right
  sleep 0.5
  send_key Enter
  sleep 5
fi
# Then the trust question. Its first option trusts the folder.
if screen | grep -Eqi 'trust'; then
  send_key Enter
  sleep 5
fi
step 02-idle

send_text "Create a file named note.txt that holds the word hello. Do not do anything else."
send_key Enter
sleep 3
step 03-busy
wait_for 'Allow|allow|approve|Yes' 90 || note "no permission dialog seen"
sleep 2
step 04-dialog
send_key Escape
sleep 6
step 05-after-escape

send_text "Reply with the single word done."
send_key Enter
sleep 2
step 06-busy-2
sleep 20
step 07-after-turn

send_key C-c || true
sleep 1
send_key C-c || true
sleep 4
step 08-after-exit
# The names of the log lines, not their text: the first word after the
# time stamp. And the first line of each crash file.
for f in "$SCN_HOME"/.gemini/antigravity-cli/crashes/*; do
  [ -f "$f" ] && head -n 3 "$f" | cut -c1-200
done >"$SCN_OUT/crashes.txt" 2>/dev/null || true
echo "done: $SCN_OUT"
