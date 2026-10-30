#!/bin/sh
# Scenario: a plan approval, and a resume in a new Claude Code process.
#
# It records, at each step: the screen, the pid file ~/.claude/sessions/<pid>.json,
# the open files of the process, the transcript files, and every hook
# payload. While the plan approval waits, it reads the "status" field of
# the pid file every 1 s. It answers these questions:
#   1. Which status does the pid file show while the plan approval
#      (ExitPlanMode) waits? Which hooks fire?
#   2. After "claude --resume <sessionId>" in a new process, does the new
#      pid file name the same sessionId? Does the transcript file stay the
#      same?
#
# Needs: claude, tmux, python3, and a Claude login in REAL_HOME (copied).
# Cost: two short prompts (about five model turns) on the subscription of
# the login.
# Run: sh scenarios/claude/plan-and-resume.sh
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=scenarios/lib.sh
. "$here/lib.sh"

SCN_NAME=claude-plan-and-resume
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

field() {
  # $1: field name. Print that field of the pid file, or "none".
  python3 - "$SCN_HOME/.claude/sessions/$(agent_pid).json" "$1" <<'EOF' 2>/dev/null || echo none
import json, sys
print(json.load(open(sys.argv[1])).get(sys.argv[2]))
EOF
}

poll() {
  # $1: label, $2: seconds. Every 1 s, append the time and the status to
  # status.log.
  i=0
  while [ "$i" -lt "$2" ]; do
    echo "$(date -u +%H:%M:%S) $1 $(field status)" >>"$SCN_OUT/status.log"
    sleep 1
    i=$((i + 1))
  done
}

step() {
  # $1: step name. Record everything for this step.
  capture "$1"
  pidfile "$1"
  scn_open_files "$1" "$(agent_pid)"
  snapshot_files "$1" "$SCN_HOME/.claude/sessions" "$SCN_HOME/.claude/projects"
  note "step $1 pid=$(agent_pid) status=$(field status) session=$(field sessionId | cut -c1-8)"
}

stop_agent() {
  # Leave with /exit and wait until the tmux server ends with the agent.
  send_text "/exit"
  send_key Enter
  n=0
  while tmux -L "$SCN_SOCK" has-session -t scn 2>/dev/null && [ "$n" -lt 30 ]; do
    sleep 1
    n=$((n + 1))
  done
  tmux -L "$SCN_SOCK" kill-server 2>/dev/null || true
}

tmux_start claude --model haiku --permission-mode plan
note "started"
wait_for 'trust this folder' 30 || note "no trust dialog seen"
sleep 2
# In 2.1.314 the first option is "No, exit" (fact 010). Select the second.
send_key Down
sleep 0.5
send_key Enter
wait_for 'for shortcuts|\? for|plan mode' 30 || note "no input box seen"
sleep 3
step 01-idle

send_text "Make a plan to create a file named note.txt that holds the word hello. The plan has one step. Do not explore the folder."
send_key Enter
wait_for 'Would you like to proceed|Ready to code|keep planning' 120 || note "no plan approval seen"
sleep 2
step 02-plan-approval
poll 02-plan-approval 10
# The first option approves the plan.
send_key 1
poll 03-after-approval 25
step 03-after-approval

session=$(field sessionId)
first_pid=$(agent_pid)
stop_agent
note "first process $first_pid ended"
snapshot_files 04-after-exit "$SCN_HOME/.claude/sessions" "$SCN_HOME/.claude/projects"

# A new process resumes the session by its ID.
tmux_start claude --model haiku --permission-mode default --resume "$session"
note "resume started"
wait_for 'for shortcuts|\? for' 30 || note "no input box seen after resume"
sleep 3
step 05-resumed
if [ "$(field sessionId)" = "$session" ]; then
  note "the new pid file names the same sessionId"
else
  note "the new pid file names another sessionId"
fi
send_text "Reply with the word ok. Do not do anything else."
send_key Enter
poll 06-resumed-turn 15
step 06-resumed-turn
stop_agent
note "stopped"

# The sessions in the hooks: the event and the first 8 characters of the
# session ID, with no conversation text.
python3 - "$SCN_OUT/hooks.jsonl" >"$SCN_OUT/hooks.summary" <<'EOF'
import json, sys
for line in open(sys.argv[1]):
    line = line.strip()
    if not line:
        continue
    d = json.loads(line)
    out = [d.get("hook_event_name", "?"), d.get("tool_name", ""),
           d.get("notification_type", ""), d.get("source", ""), d.get("reason", ""),
           d.get("permission_mode", ""), d.get("session_id", "")[:8]]
    print(" ".join(x for x in out if x))
    if d.get("tool_name") == "ExitPlanMode":
        print("  tool_input keys:", sorted((d.get("tool_input") or {}).keys()))
EOF
[ -f "$SCN_WORK/note.txt" ] && note "note.txt exists" || note "note.txt does not exist"
echo "done: $SCN_OUT"
