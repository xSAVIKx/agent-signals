#!/bin/sh
# Scenario: keys that reach Claude Code early.
#
# Part "digit": a digit sent just after the Enter of a message that opens a
# Bash permission dialog. It answers these questions:
#   1. When "1" follows the Enter by 0, 50, 200 or 500 ms, does the "1"
#      answer the dialog, stay in the input box, or go nowhere?
#   2. When "1" goes at the moment the PreToolUse or the PermissionRequest
#      hook fires, does it answer the dialog?
# Part "clear": the clear gap of fact 9. A new process gets C-u, then text
# 20 ms later, then Enter, at 0 to 15 s after its input box first draws.
# It answers this question:
#   3. Does the first Enter submit, or does the box keep the text with the
#      "invisible character" notice?
#
# Part "clear" uses a UserPromptSubmit hook that blocks each prompt, so no
# prompt reaches the model. The hook log shows each submission.
#
# Needs: Linux (date +%s%3N), claude, tmux, python3, and a Claude login in
# REAL_HOME (copied).
# Cost: part "digit" sends TRIALS x (the number of DELAYS) short prompts.
# Each prompt takes one model turn, and one more turn when the dialog gets
# "Yes". Part "clear" takes no model turn: about 30 s of wall time for
# each trial.
# Run (the runs of facts 74 and 75):
#   CLAUDE_BIN=claude TRIALS=3 sh scenarios/claude/early-keys.sh digit
#   CLAUDE_BIN=claude TRIALS=4 FRESH=1 DELAYS="pre perm" \
#     sh scenarios/claude/early-keys.sh digit
#   CLAUDE_BIN=claude TRIALS=48 sh scenarios/claude/early-keys.sh clear
#   BOX_RE='^❯' CLAUDE_BIN=claude TRIALS=16 \
#     sh scenarios/claude/early-keys.sh clear
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=scenarios/lib.sh
. "$here/lib.sh"

PART=${1:-digit}
CLAUDE_BIN=${CLAUDE_BIN:-claude}
TRIALS=${TRIALS:-3}
# DELAYS: the waits between the Enter and the "1", in ms. "0" sends both
# keys in one tmux command. "next" sends them in two tmux commands with no
# wait. "pre" and "perm" send the "1" when the PreToolUse or the
# PermissionRequest hook writes its line.
DELAYS=${DELAYS:-0 next 50 200 500}
# FRESH=1 sends /clear before each trial of part "digit".
FRESH=${FRESH:-0}
SCN_NAME=claude-early-keys-$PART
sandbox_start
copy_login claude || die "no Claude login that is valid for 30 minutes or more"
"$CLAUDE_BIN" --version >"$SCN_OUT/version.txt" 2>&1 || true
note "version $(cat "$SCN_OUT/version.txt")"

now_ms() { date +%s%3N; }

# The hook adds one line for each event: the time in ms, the event name and
# the tool name. It writes no prompt text. With "block" as its third
# argument, it blocks a UserPromptSubmit (exit 2), so the prompt does not
# reach the model.
mkdir -p "$SCN_HOME/.claude"
cat >"$SCN_DIR/hook.py" <<'PY'
import json, sys, time
try:
    d = json.loads(sys.stdin.read())
except ValueError:
    d = {}
ev = d.get("hook_event_name", "?")
with open(sys.argv[1], "a") as f:
    f.write("%d %s %s\n" % (time.time() * 1000, ev, d.get("tool_name", "")))
if len(sys.argv) > 2 and sys.argv[2] == "block" and ev == "UserPromptSubmit":
    sys.stderr.write("blocked by the scenario\n")
    sys.exit(2)
PY
: >"$SCN_OUT/hooks.log"
python3 - "$SCN_HOME/.claude/settings.json" "$SCN_DIR/hook.py" "$SCN_OUT/hooks.log" "$PART" <<'EOF'
import json, shlex, sys
out, script, log, part = sys.argv[1:5]
cmd = "python3 %s %s" % (shlex.quote(script), shlex.quote(log))
if part == "clear":
    cmd += " block"
events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest",
          "PostToolUse", "Stop"]
hooks = {e: [{"matcher": "", "hooks": [{"type": "command", "command": cmd}]}]
         for e in events}
json.dump({"hooks": hooks}, open(out, "w"), indent=1)
EOF

count() { grep -c " $1" "$SCN_OUT/hooks.log" || true; }

# box_text: the text of the input box. The box is the last line that
# starts with the prompt mark.
box_text() {
  screen | python3 -c '
import sys
rows = [r for r in sys.stdin.read().splitlines() if r.startswith("\u276f")]
print(rows[-1][1:].replace("\u00a0", " ").strip() if rows else "")
'
}

# box_state: "empty" (no text, or only the hint), "digit" (only "1"), or
# "text" (other text).
box_state() {
  b=$(box_text)
  case $b in
    '' | 'Try "'*) echo empty ;;
    1) echo digit ;;
    *) echo text ;;
  esac
}

# wait_gone REGEX SECONDS: wait until the pane does not match REGEX.
wait_gone() {
  n=0
  while [ "$n" -lt "$(($2 * 2))" ]; do
    screen | grep -Eq -- "$1" || return 0
    sleep 0.5
    n=$((n + 1))
  done
  return 1
}
# The pattern of a drawn input box. BOX_RE='^❯' takes the first frame of the
# box line, which can come before the status line.
BOX=${BOX_RE:-'for shortcuts|\? for'}

start_agent() {
  tmux_start "$CLAUDE_BIN" --model haiku --permission-mode default
}

stop_agent() {
  p=$(agent_pid)
  tmux -L "$SCN_SOCK" kill-session -t scn 2>/dev/null || true
  n=0
  while [ "$p" -gt 0 ] && kill -0 "$p" 2>/dev/null && [ "$n" -lt 20 ]; do
    sleep 0.5
    n=$((n + 1))
  done
  [ "$p" -gt 0 ] && kill -9 "$p" 2>/dev/null || true
}

# Answer the trust dialog with the digit of its "Yes" line (fact 010: the
# first option can be "No, exit").
trust() {
  if wait_for 'trust this folder' 60; then
    sleep 1
    capture 00-trust
    y=$(screen | sed -n 's/^[^0-9]*\([0-9]\)\. Yes.*$/\1/p' | head -n 1)
    note "trust dialog: Yes is ${y:-not numbered}"
    # A key can be lost on a loaded machine. Try again while the dialog
    # shows.
    a=0
    while [ "$a" -lt 4 ] && screen | grep -q 'trust this folder'; do
      if [ -n "$y" ]; then
        send_key "$y"
      else
        # 2.1.316 numbers no option: "No, exit", then "Yes, I trust".
        send_key Down
        sleep 1
        send_key Enter
      fi
      wait_gone 'trust this folder' 10 || true
      a=$((a + 1))
    done
  else
    note "no trust dialog seen"
  fi
}

if [ "$PART" = digit ]; then
  start_agent
  note "started"
  trust
  wait_for "$BOX" 60 || note "no input box seen"
  # Wait past the 16 s of fact 9 before the first message.
  sleep 20
  capture 01-idle
  echo "trial delay gap_ms result box permission_requests lost_texts" >"$SCN_OUT/results.txt"
  i=0
  t=0
  while [ "$t" -lt "$TRIALS" ]; do
    for d in $DELAYS; do
      i=$((i + 1))
      dir=d$i
      stops=$(count Stop)
      perms=$(count PermissionRequest)
      subs=$(count UserPromptSubmit)
      # Start each trial from an idle box.
      wait_for '\? for shortcuts' 60 || note "trial $i: the box is not idle"
      sleep 1
      if [ "$FRESH" = 1 ]; then
        # A new conversation for each trial. Without it, the model saw
        # the earlier denials and stopped calling the tool.
        send_text "/clear"
        send_key Enter
        sleep 3
        wait_for '\? for shortcuts' 60 || note "trial $i: the box is not idle after /clear"
        sleep 1
      fi
      # Type the message, and check that the box shows it. On the loaded
      # test machine, the typed text did not reach the box in some trials.
      msg="Run the command mkdir $dir with your Bash tool. Do not do anything else."
      lost=0
      while :; do
        send_text "$msg"
        n=0
        while [ "$n" -lt 20 ] && [ "$(box_text)" != "$msg" ]; do
          sleep 0.5
          n=$((n + 1))
        done
        [ "$(box_text)" = "$msg" ] && break
        lost=$((lost + 1))
        note "trial $i: the box does not show the typed text ($lost)"
        capture "trial-$i-lost-$lost"
        [ "$lost" -ge 3 ] && break
        send_key C-u
        sleep 2
      done
      case $d in
        0)
          # One tmux command: the Enter and the digit go in one write.
          t0=$(now_ms)
          tmux -L "$SCN_SOCK" send-keys -t scn Enter 1
          t1=$t0
          ;;
        next)
          # Two tmux commands with no wait between them.
          tmux -L "$SCN_SOCK" send-keys -t scn Enter
          t0=$(now_ms)
          t1=$(now_ms)
          tmux -L "$SCN_SOCK" send-keys -t scn 1
          ;;
        pre | perm)
          # The digit goes when the hook of the tool call writes its line:
          # PreToolUse ("pre") or PermissionRequest ("perm"). This is
          # before the dialog draws, or just after.
          ev=PreToolUse
          [ "$d" = perm ] && ev=PermissionRequest
          before=$(count "$ev")
          tmux -L "$SCN_SOCK" send-keys -t scn Enter
          t0=$(now_ms)
          n=0
          while [ "$(count "$ev")" -le "$before" ] && [ "$n" -lt 1200 ]; do
            sleep 0.05
            n=$((n + 1))
          done
          shown=no
          screen | grep -q 'Do you want' && shown=yes
          t1=$(now_ms)
          tmux -L "$SCN_SOCK" send-keys -t scn 1
          # send-keys returns after it wrote the key to the pane. A dialog
          # that is not drawn now draws after the key reached the pane.
          after=no
          screen | grep -q 'Do you want' && after=yes
          note "trial $i: $ev after $((t1 - t0)) ms, dialog drawn: $shown, drawn after the key: $after"
          ;;
        *)
          tmux -L "$SCN_SOCK" send-keys -t scn Enter
          t0=$(now_ms)
          sleep "$(awk "BEGIN { print $d / 1000 }")"
          t1=$(now_ms)
          tmux -L "$SCN_SOCK" send-keys -t scn 1
          ;;
      esac
      gap=$((t1 - t0))
      result=none
      n=0
      while [ "$n" -lt 180 ]; do
        if [ -d "$SCN_WORK/$dir" ]; then result=answered; break; fi
        if screen | grep -q 'Do you want'; then
          # Wait 3 s more: a key in a buffer can answer the dialog late.
          sleep 3
          if [ -d "$SCN_WORK/$dir" ]; then result=answered; break; fi
          result=waits
          break
        fi
        [ "$(count Stop)" -gt "$stops" ] && { result=no-dialog; break; }
        # No submission after 15 s: the Enter did not send the message.
        if [ "$n" -ge 30 ] && [ "$(count UserPromptSubmit)" -le "$subs" ]; then
          result=not-sent
          break
        fi
        sleep 0.5
        n=$((n + 1))
      done
      capture "trial-$i-a"
      if [ "$result" = waits ]; then
        # Close the dialog with Esc, then read the input box.
        send_key Escape
        wait_gone 'Do you want' 20 || { send_key Escape; wait_gone 'Do you want' 20; } ||
          note "trial $i: the dialog stays after two Esc"
        sleep 1
        if [ -d "$SCN_WORK/$dir" ]; then result=answered-after-esc; fi
      elif [ "$result" = answered ]; then
        # Wait for the end of the turn, then read the input box.
        n=0
        while [ "$(count Stop)" -le "$stops" ] && [ "$n" -lt 120 ]; do
          sleep 0.5
          n=$((n + 1))
        done
        sleep 1
      fi
      capture "trial-$i-b"
      box=$(box_state)
      echo "$i $d $gap $result $box $(($(count PermissionRequest) - perms)) $lost" | tee -a "$SCN_OUT/results.txt"
      # Empty the box for the next trial. One C-c empties a box with text.
      if [ "$box" != empty ]; then
        send_key C-c
        sleep 3
      fi
      sleep 2
    done
    t=$((t + 1))
  done
  stop_agent
fi

if [ "$PART" = clear ]; then
  MSG="Reply with the word ok."
  # clear_box_state: "text" (the box holds the message), "empty" (the box
  # holds nothing, or only its hint), or "other".
  clear_box_state() {
    screen | python3 -c '
import sys
rows = [r for r in sys.stdin.read().splitlines() if r.startswith("\u276f")]
b = rows[-1][1:].replace("\u00a0", " ").strip() if rows else ""
m = sys.argv[1]
print("text" if b == m else "empty" if b == "" or b.startswith("Try ") else "other")
' "$MSG"
  }
  # The first start accepts the trust dialog. Each trial starts a new
  # process, because only the first message of a process showed the
  # invisible character in fact 9.
  start_agent
  trust
  wait_for "$BOX" 60 || note "no input box seen"
  sleep 2
  stop_agent
  echo "trial wait_s since_box_ms first_enter notice box second_enter" >"$SCN_OUT/results.txt"
  k=0
  while [ "$k" -lt "$TRIALS" ]; do
    k=$((k + 1))
    w=$(((k - 1) % 16))
    start_agent
    n=0
    tb=
    while [ "$n" -lt 600 ]; do
      if screen | grep -Eq -- "$BOX"; then tb=$(now_ms); break; fi
      sleep 0.1
      n=$((n + 1))
    done
    if [ -z "$tb" ]; then
      note "trial $k: no input box"
      stop_agent
      continue
    fi
    sleep "$w"
    subs=$(count UserPromptSubmit)
    ts=$(now_ms)
    send_key C-u
    sleep 0.02
    tmux -L "$SCN_SOCK" send-keys -t scn -l -- "$MSG"
    sleep 0.3
    send_key Enter
    # The hook can fire some seconds after the Enter on a loaded machine.
    first=no
    notice=no
    n=0
    while [ "$n" -lt 40 ]; do
      [ "$(count UserPromptSubmit)" -gt "$subs" ] && { first=yes; break; }
      screen | grep -q 'invisible character' && notice=yes
      [ "$notice" = yes ] && [ "$n" -ge 10 ] && break
      sleep 0.5
      n=$((n + 1))
    done
    capture "trial-$k"
    box=-
    second=-
    if [ "$first" = no ]; then
      box=$(clear_box_state)
      send_key Enter
      second=no
      n=0
      while [ "$n" -lt 40 ]; do
        [ "$(count UserPromptSubmit)" -gt "$subs" ] && { second=yes; break; }
        sleep 0.5
        n=$((n + 1))
      done
      capture "trial-$k-second"
    fi
    echo "$k $w $((ts - tb)) $first $notice $box $second" | tee -a "$SCN_OUT/results.txt"
    stop_agent
  done
fi
echo "done: $SCN_OUT"
