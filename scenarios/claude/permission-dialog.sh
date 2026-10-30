#!/bin/sh
# Scenario: the trust dialog and a permission dialog of Claude Code.
#
# It records, at each step: the screen, the pid file ~/.claude/sessions/<pid>.json,
# the open files of the process, and every hook payload. It answers three
# questions:
#   1. Does a signal show that the folder-trust question waits?
#   2. Which hook payload describes a permission dialog, and with which fields?
#   3. Does the pid file show the wait on a dialog?
#
# Needs: claude, tmux, python3, and a Claude login in REAL_HOME (copied).
# Cost: two short turns on the subscription of the login.
# Run: sh scenarios/claude/permission-dialog.sh
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=scenarios/lib.sh
. "$here/lib.sh"

SCN_NAME=claude-permission-dialog
sandbox_start
copy_login claude || die "no Claude login that is valid for 30 minutes or more"

# Each hook appends its payload as one JSON line, with the event name.
mkdir -p "$SCN_HOME/.claude"
python3 - "$SCN_HOME/.claude/settings.json" "$SCN_OUT/hooks.jsonl" <<'EOF'
import json, sys
cmd = "cat >> '%s'; echo >> '%s'" % (sys.argv[2], sys.argv[2])
events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest",
          "PostToolUse", "Notification", "Stop", "SubagentStop", "SessionEnd",
          "PreCompact"]
hooks = {e: [{"matcher": "", "hooks": [{"type": "command", "command": cmd}]}]
         for e in events}
json.dump({"hooks": hooks}, open(sys.argv[1], "w"), indent=1)
EOF

pidfile() {
  # $1: step name. Copy the pid file of the agent, if there is one.
  f=$SCN_HOME/.claude/sessions/$(agent_pid).json
  if [ -f "$f" ]; then cp "$f" "$SCN_OUT/$1.pid.json"; else echo "none" >"$SCN_OUT/$1.pid.json"; fi
}

step() {
  # $1: step name. Record everything for this step.
  capture "$1"
  pidfile "$1"
  open_files "$1" "$(agent_pid)"
  snapshot_files "$1" "$SCN_HOME/.claude/sessions" "$SCN_HOME/.claude/projects"
  note "step $1"
}

# A new install starts in auto mode, which writes a file with no dialog.
tmux_start claude --model haiku --permission-mode default
note "started"
wait_for 'trust this folder' 30 || note "no trust dialog seen"
sleep 2
step 01-trust

# In 2.1.314 the first option is "No, exit" (fact 010). Select the second.
send_key Down
sleep 0.5
send_key Enter
wait_for 'for shortcuts|\? for' 30 || note "no input box seen"
sleep 3
step 02-idle

send_text "Create a file named note.txt that holds the word hello. Do not do anything else."
send_key Enter
wait_for 'Do you want' 90 || note "no permission dialog seen"
sleep 3
step 03-permission

# Every 2 s for 10 s, record the pid file while the dialog waits.
i=0
while [ "$i" -lt 5 ]; do
  pidfile "03-permission-wait-$i"
  sleep 2
  i=$((i + 1))
done

send_key Escape
sleep 5
step 04-after-deny

send_text "Create a file named note.txt that holds the word hello. Do not do anything else."
send_key Enter
wait_for 'Do you want' 90 || note "no second permission dialog seen"
sleep 2
step 05-permission-again
send_key 1
sleep 8
step 06-after-allow

# After /clear, does the pid file name the new session?
send_text "/clear"
send_key Enter
sleep 5
step 07-after-clear

send_key C-c
sleep 1
send_key C-c
sleep 3
note "stopped"
[ -f "$SCN_WORK/note.txt" ] && note "note.txt exists" || note "note.txt does not exist"
echo "done: $SCN_OUT"
