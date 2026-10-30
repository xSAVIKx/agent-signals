#!/bin/sh
# Scenario: the pid file status and the hooks for more Claude Code waits.
#
# It records, at each step: the screen, the pid file ~/.claude/sessions/<pid>.json,
# the open files of the process, and every hook payload. While each wait
# lasts, it reads the "status" field of the pid file every 1 s. It answers
# these questions:
#   1. Which status does the pid file show for a question from the agent
#      (AskUserQuestion), for a Bash command dialog, and for a background
#      shell?
#   2. Which hook carries the question and its options, and in which shape?
#   3. Which hooks fire after "No" on a Bash permission dialog, and which
#      status follows?
#   4. Does the process hold the task folder open before its first
#      background task? Does the folder change after /clear?
#   5. Does a read-only command (ls) open a Bash dialog?
#
# Needs: claude, tmux, python3, and a Claude login in REAL_HOME (copied).
# Cost: five short prompts (about nine model turns) on the subscription
# of the login.
# Run: sh scenarios/claude/dialog-states.sh
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=scenarios/lib.sh
. "$here/lib.sh"

SCN_NAME=claude-dialog-states
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

status() {
  # Print the status field of the pid file, or "none".
  python3 - "$SCN_HOME/.claude/sessions/$(agent_pid).json" <<'EOF' 2>/dev/null || echo none
import json, sys
print(json.load(open(sys.argv[1])).get("status"))
EOF
}

poll() {
  # $1: label, $2: seconds, $3: optional digit. Every 1 s, append the
  # time and the status to status.log. With a digit: when a dialog shows,
  # send the digit once.
  i=0
  sent=
  while [ "$i" -lt "$2" ]; do
    st=$(status)
    echo "$(date -u +%H:%M:%S) $1 $st" >>"$SCN_OUT/status.log"
    # Keep one copy of the pid file for each status of this wait.
    [ -f "$SCN_OUT/$1.$st.pid.json" ] || pidfile "$1.$st"
    if [ -n "${3:-}" ] && [ -z "$sent" ] && screen | grep -Eq 'Do you want'; then
      capture "$1-dialog"
      send_key "$3"
      sent=1
      note "$1: sent $3 to a dialog"
    fi
    sleep 1
    i=$((i + 1))
  done
}

# The task folder of Claude Code is outside HOME (fact 025):
# /tmp/claude-<uid>/<project key>/<session id>/tasks.
TASK_ROOT=/tmp/claude-$(id -u)/$(printf '%s' "$SCN_WORK" | tr -c 'A-Za-z0-9' '-')

tasks_tree() {
  # $1: step name. List the folders and files below the task root.
  [ -d "$TASK_ROOT" ] || { echo "none" >"$SCN_OUT/$1.tasks"; return 0; }
  find "$TASK_ROOT" | sed "s#$TASK_ROOT#<task root>#" | sort >"$SCN_OUT/$1.tasks"
}

step() {
  # $1: step name. Record everything for this step.
  capture "$1"
  tasks_tree "$1"
  pidfile "$1"
  scn_open_files "$1" "$(agent_pid)"
  snapshot_files "$1" "$SCN_HOME/.claude/sessions" "$SCN_HOME/.claude/projects"
  note "step $1 status=$(status)"
}

tmux_start claude --model haiku --permission-mode default
note "started"
wait_for 'trust this folder' 30 || note "no trust dialog seen"
sleep 2
# In 2.1.314 the first option is "No, exit" (fact 010). Select the second.
send_key Down
sleep 0.5
send_key Enter
wait_for 'for shortcuts|\? for' 30 || note "no input box seen"
sleep 3
# No background task ran yet. Is the task folder open?
step 01-idle

# A question from the agent.
send_text "Ask me with your question tool whether I prefer red or blue, then reply with my answer."
send_key Enter
wait_for 'Enter to select|Esc to cancel' 90 || note "no question seen"
sleep 2
step 02-question
poll 02-question 10
send_key 1
sleep 2
if screen | grep -q 'Submit answers'; then
  capture 02-question-review
  send_key 1
  note "sent 1 to the review screen"
fi
poll 03-after-question 12
step 03-after-question

# A read-only command. Does it open a dialog?
send_text "Run the command ls in the work folder with your Bash tool. Do not do anything else."
send_key Enter
if wait_for 'Do you want' 30; then
  note "ls opened a dialog"
  step 04-ls-dialog
  send_key 1
else
  note "ls opened no dialog"
fi
poll 04-ls 5
step 04-after-ls

# A Bash command dialog, denied with its "No" option. The command makes a
# folder, because a read-only command can run with no dialog. In 2.1.314
# the Bash dialog has four options, and "3." switches to auto mode. So
# the digit comes from the "No" line of the screen.
send_text "Run the command mkdir build in the work folder with your Bash tool. Do not do anything else."
send_key Enter
if wait_for 'Do you want' 90; then
  sleep 2
  step 04-bash-dialog
  poll 04-bash-dialog 10
  no=$(screen | sed -n 's/^[^0-9]*\([0-9]\)\. No$/\1/p' | head -n 1)
  note "the No option is ${no:-not found}"
  if [ -n "$no" ]; then send_key "$no"; fi
else
  note "no Bash dialog seen"
  step 04-bash-dialog
fi
sleep 1
capture 05-after-no-0
poll 05-after-no 10
step 05-after-no

# A background shell. A dialog for the command gets "1. Yes".
send_text "Run the command sleep 30 with your Bash tool in the background. Then reply with the word started. Do not do anything else."
send_key Enter
poll 06-background 50 1
step 06-after-background

# After /clear, the task folder and the pid file.
send_text "/clear"
send_key Enter
sleep 5
step 07-after-clear
send_text "Run the command sleep 3 with your Bash tool in the background. Then reply with the word started. Do not do anything else."
send_key Enter
poll 08-background-after-clear 25 1
step 08-after-clear-background

send_key C-c
sleep 1
send_key C-c
sleep 3
note "stopped"

# A summary of the hooks with no conversation text: the event, the tool,
# and the shape of an AskUserQuestion tool_input (keys and the number of
# options).
python3 - "$SCN_OUT/hooks.jsonl" >"$SCN_OUT/hooks.summary" <<'EOF'
import json, sys

def shape(v):
    if isinstance(v, dict):
        return {k: shape(x) for k, x in v.items()}
    if isinstance(v, list):
        return [shape(v[0]), "x%d" % len(v)] if v else []
    return type(v).__name__

for line in open(sys.argv[1]):
    line = line.strip()
    if not line:
        continue
    d = json.loads(line)
    out = [d.get("hook_event_name", "?"), d.get("tool_name", ""),
           d.get("notification_type", ""), d.get("source", ""), d.get("reason", ""),
           d.get("session_id", "")[:8]]
    print(" ".join(x for x in out if x))
    if d.get("tool_name") == "AskUserQuestion":
        print("  keys:", sorted(d.keys()))
        print("  tool_input:", json.dumps(shape(d.get("tool_input"))))
        if "tool_response" in d:
            print("  tool_response:", json.dumps(shape(d.get("tool_response"))))
EOF
echo "done: $SCN_OUT"
