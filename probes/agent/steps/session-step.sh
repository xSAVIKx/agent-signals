#!/bin/sh
# The test-session steps: permission, new-chat, resume and interrupt. The
# files steps/<kind>.sh run this script. It reads the step from the
# variables of "kit step" (probes/agent/step.sh): KIT_KIND, KIT_AGENT,
# KIT_BACKEND (tmux or pty), KIT_PROMPT, KIT_WAIT_REGEX, KIT_ANSWER,
# KIT_PRE, KIT_IDLE_REGEX, KIT_BUSY_REGEX and KIT_DIALOG_REGEX.
#
# The steps of the script:
#   1. Start a session of the agent with "kit session start" in a new work
#      folder.
#   2. Answer the screens before the idle screen with the KIT_PRE pairs
#      (REGEX=>KEYS;;...). A pair is used again only while its REGEX still
#      matches, 2 s after the last use, 3 times at most. Wait for the
#      idle screen (60 s). The screen is idle when a line matches
#      KIT_IDLE_REGEX, and no line matches KIT_BUSY_REGEX or
#      KIT_DIALOG_REGEX.
#   3. Start the guided watch of probes/run.sh in the background, on the
#      pids of the run (RUN/pids/) only. Wait for its line
#      "kit: watch starts".
#   4. Do the action of the kind:
#      permission  send the prompt and Enter, wait for KIT_WAIT_REGEX (the
#                  dialog, 90 s), hold the dialog for 30 s so that the
#                  watch sees it, send KIT_ANSWER, wait for idle (10 s).
#      new-chat    send the prompt (/clear) and Enter, wait for an idle
#                  screen that does not show the prompt text.
#      interrupt   send the prompt and Enter, wait for KIT_WAIT_REGEX (the
#                  busy screen), then send each key of KIT_ANSWER, 2 s
#                  apart.
#      resume      send a short prompt and Enter, wait for idle, stop the
#                  session, start it again in the same work folder with
#                  the arguments KIT_PROMPT, wait for idle.
#   5. Make the stop file of the watch, and wait for the end of the watch,
#      so that the "after" snapshot sees the session. Then stop the
#      session.
# The output file holds the guided-step output, the screens (idle, dialog
# and after for permission) and a log of the step with the time of each
# stage.
#
# Results and reasons:
#   ok                       the step did its action, and the watch saw a
#                            file or a record.
#   ok no-records            the watch saw no changed file and no record.
#   ok no-dialog             permission only: no dialog in the time limit.
#                            The file keeps the last screen.
#   ok dialog-after-watch    the dialog came after the end of the watch.
#   ok no-idle-after         no idle screen after the answer.
#   ok no-idle-before-stop   resume: no idle screen before the stop.
#   ok restart-outside-watch resume: the watch ended before the new start.
#   fail no-idle, no-busy, prompt-on-screen, agent-ended, screen-failed,
#        send-failed, no-watch, watch-exit-N, watch-timeout, no-guided
#   skip unmeasured          the step list has no idle regex for the agent,
#                            because the corpus has no screen of it (Cursor).
#
# Caution: a real screen of Claude Code can show a display name or an
# organisation in its welcome box. The step blanks these lines before it
# saves a screen, and the file says so. No real screen was measured.
#
# The step prints a "kit: " line on stderr at each stage. One deadline
# holds for the whole step (225 s), so that it fits in the time limit of
# the shell tool of an agent. With AGENT_SIGNALS_WATCH set (the tests), each
# wait and the hold take that number of seconds at most.
set -u
: "${KIT_RUN:?}" "${KIT_ROOT:?}" "${KIT_DIR:?}" "${KIT_OUT:?}" "${KIT_STEP:?}" "${KIT_KIND:?}"
: "${KIT_AGENT:?}" "${KIT_BACKEND:?}"
. "$KIT_DIR/lib.sh"

AGENT_SIGNALS_RUN=$KIT_RUN
export AGENT_SIGNALS_RUN

DEADLINE=$(($(date +%s) + 225))
# The time that the end of the step needs after the last wait.
RESERVE=25

# lim SECONDS: a time limit. AGENT_SIGNALS_WATCH makes it shorter.
lim() {
  if [ -n "${AGENT_SIGNALS_WATCH:-}" ] && [ "$AGENT_SIGNALS_WATCH" -lt "$1" ]; then
    echo "$AGENT_SIGNALS_WATCH"
  else
    echo "$1"
  fi
}

# clip SECONDS: SECONDS, or the time to the deadline when that is less. The
# value is 1 at least.
clip() {
  _l=$((DEADLINE - RESERVE - $(date +%s)))
  [ "$_l" -ge 1 ] || _l=1
  [ "$1" -le "$_l" ] && _l=$1
  echo "$_l"
}

IDLE_S=$(lim 60)
WAIT_S=$(lim 90)
HOLD_S=$(lim 30)
AFTER_S=$(lim 10)
# The watch must hold each action. The stop file ends it early.
WATCH_S=$((IDLE_S + WAIT_S + HOLD_S + AFTER_S))
# The limit for the "after" snapshot, after the stop file.
END_S=$(lim 30)
[ "$END_S" -ge 10 ] || END_S=10

say() { echo "kit: $KIT_STEP@$KIT_BACKEND: $*" >&2; echo "$(date -u +%H:%M:%S) $*" >>"$tmp/log"; }
reason() { echo "$1" >"$KIT_OUT.reason"; }

case $KIT_BACKEND in
  tmux | pty) ;;
  *)
    reason "no-backend-$KIT_BACKEND"
    exit 3
    ;;
esac
if [ -z "${KIT_IDLE_REGEX:-}" ]; then
  reason unmeasured
  exit 3
fi
cmd=$(kit_agent_command "$KIT_AGENT")
if [ -z "$cmd" ]; then
  reason not-installed
  exit 3
fi

tmp=$(mktemp -d "$(dirname "$KIT_OUT")/session.XXXXXX") || exit 1
# The session name: letters, digits and "-", 40 characters at most.
sess=$(printf '%s' "$KIT_STEP" | cut -c1-30)-$KIT_BACKEND
watch=
watched=
# dash runs no EXIT trap on a signal, so a signal exits first.
trap 'exit 130' INT TERM
trap 'cleanup' EXIT
cleanup() {
  [ -n "$watch" ] && kill "$watch" 2>/dev/null
  sh "$KIT_DIR/session.sh" stop "$sess" >/dev/null 2>&1
  rm -rf "$tmp"
}

ses() { sh "$KIT_DIR/session.sh" "$@"; }

# screen FILE: the screen of the session now. It fails when it reads no
# screen.
screen() { ses screen "$sess" >"$1" 2>/dev/null && [ -s "$1" ]; }

# has RE FILE: true when RE is not empty and a line of FILE matches it.
has() { [ -n "$1" ] && grep -Eq -- "$1" "$2"; }

# is_idle FILE: the idle rule of steps.tsv.
is_idle() {
  has "$KIT_IDLE_REGEX" "$1" || return 1
  has "${KIT_BUSY_REGEX:-}" "$1" && return 1
  has "${KIT_DIALOG_REGEX:-}" "$1" && return 1
  return 0
}

# alive: true when the agent of the session runs.
alive() {
  _a=$(cat "$KIT_RUN/sessions/$sess/pid" 2>/dev/null)
  [ -n "$_a" ] && kit_pid_runs "$_a" || return 1
  case $(ps -o stat= -p "$_a" 2>/dev/null) in Z*) return 1 ;; esac
  return 0
}

# watching: true when the watch runs.
watching() { [ -n "$watch" ] && kill -0 "$watch" 2>/dev/null; }

# The wait functions return 0 for a match, 1 at the time limit, 2 when the
# agent ended and 3 when no screen came. "bad" ends the step for 2 and 3.

# pre_answer FILE: send the keys of the first KIT_PRE pair that matches a
# line of FILE. A key that comes before the agent reads keys is lost (Claude
# Code 2.1.318 on ubuntu-26.04 in CI). So a pair gets its keys again, 3 times
# at most, when it still matches 3 s after its keys and the screen is the
# same as at the last send. A key that worked changes the screen, so a slow
# redraw does not get a second Down. It fails when no pair can send keys.
used=
pre_answer() {
  [ -n "${KIT_PRE:-}" ] || return 1
  _n=0
  _rest=$KIT_PRE
  while [ -n "$_rest" ]; do
    _pair=${_rest%%;;*}
    case $_rest in *';;'*) _rest=${_rest#*;;} ;; *) _rest= ;; esac
    _n=$((_n + 1))
    _c=$(printf '%s\n' $used | grep -c "^$_n:")
    [ "$_c" -lt 3 ] || continue
    _now=$(date +%s)
    _sum=$(cksum <"$1" | tr ' ' _)
    _last=$(printf '%s\n' $used | grep "^$_n:" | tail -n 1)
    if [ -n "$_last" ]; then
      _t=${_last#*:}
      [ $((_now - ${_t%%:*})) -ge 3 ] && [ "${_t#*:}" = "$_sum" ] || continue
    fi
    _k=${_pair#*=>}
    if has "${_pair%%=>*}" "$1"; then
      say "pre answer $_n: $_k"
      used="$used $_n:$_now:$_sum"
      keys "$_k"
      return 0
    fi
  done
  return 1
}

# in_box FILE TEXT: TEXT is at the end of the box line, the last line that
# starts with a prompt mark (❯, ›, → or >). With no such line, at the end
# of any line. Claude Code 2.1.318 shows a sent "/clear" on a line above the
# box, and the path of the work folder of a new-chat step holds "/new" too.
in_box() {
  _re="(^|[[:space:]]|$(printf '\302\240'))$(kit_text_re "$2")[[:space:]]*\$"
  _box=$(grep -E '^[[:space:]]*(❯|›|→|>)' "$1" | tail -n 1)
  if [ -n "$_box" ]; then
    printf '%s\n' "$_box" | grep -Eq -- "$_re"
  else
    grep -Eq -- "$_re" "$1"
  fi
}

# wait_idle SECONDS FILE [TEXT]: answer the KIT_PRE pairs and wait for the
# idle screen. With TEXT, the box line must not show TEXT (in_box). FILE
# gets the last screen.
wait_idle() {
  _end=$(($(date +%s) + $(clip "$1")))
  while :; do
    alive || { screen "$2"; return 2; }
    screen "$2" || return 3
    if ! pre_answer "$2" && is_idle "$2"; then
      [ -n "${3:-}" ] && in_box "$2" "$3" || return 0
    fi
    [ "$(date +%s)" -lt "$_end" ] || return 1
    sleep 1
  done
}

# wait_re RE SECONDS FILE: wait until a line of the screen matches RE.
wait_re() {
  _end=$(($(date +%s) + $(clip "$2")))
  while :; do
    alive || { screen "$3"; return 2; }
    screen "$3" || return 3
    has "$1" "$3" && return 0
    [ "$(date +%s)" -lt "$_end" ] || return 1
    sleep 0.5
  done
}

# start_session [ARGS]: start the session with the agent command and ARGS.
keep=
start_session() {
  # shellcheck disable=SC2086
  ses start "$sess" "$KIT_AGENT" --via "$KIT_BACKEND" --cmd "$cmd${1:+ $1}" $keep >"$tmp/start" 2>&1
  _c=$?
  if [ "$_c" -ne 0 ]; then
    say "the session did not start: $(tail -n 1 "$tmp/start")"
    case $(tail -n 1 "$tmp/start") in
      *"needs pyte"*) reason needs-pyte ;;
      *"needs tmux"*) reason needs-tmux ;;
      *) reason session-start ;;
    esac
    [ "$_c" = 3 ] && exit 3
    exit 1
  fi
}

# The values of the login that a welcome box can show. They stay in this
# process. The step never writes them.
login_value() {
  for _f in "$home_dir/.claude.json" "$home_dir/.claude/.claude.json"; do
    [ -r "$_f" ] && sed -n "s/.*\"$1\": *\"\\([^\"]*\\)\".*/\\1/p" "$_f" | head -n 1
  done | head -n 1
}

# blank FILE: print FILE with each line of the Claude welcome box that can
# show a display name or an organisation changed to <blanked by the kit>.
blank() {
  KIT_BLANK_1=$(login_value displayName) KIT_BLANK_2=$(login_value organizationName) awk '
    BEGIN { a = ENVIRON["KIT_BLANK_1"]; b = ENVIRON["KIT_BLANK_2"]; x = "<blanked by the kit>" }
    /Welcome back|Organi[sz]ation/ || (length(a) > 2 && index($0, a)) || (length(b) > 2 && index($0, b)) { print x; next }
    match($0, / · Claude [A-Z][A-Za-z]*( [A-Za-z]+)? · /) { print substr($0, 1, RSTART + RLENGTH - 1) x; next }
    { print }' "$1"
}

# save NAME FILE: keep FILE as the screen NAME.
n_screens=0
save() {
  n_screens=$((n_screens + 1))
  if [ "$KIT_AGENT" = claude ]; then
    blank "$2" >"$tmp/screen.$n_screens"
  else
    cp "$2" "$tmp/screen.$n_screens"
  fi
  echo "$1" >"$tmp/screen.$n_screens.name"
}

# end_watch: make the stop file, wait a limited time for the end of the
# watch, then kill it. It sets watch_bad to the reason of a failure.
watch_bad=
end_watch() {
  if [ -z "$watched" ]; then
    return 0
  fi
  : >"$tmp/stop"
  say "end the watch"
  _end=$(($(date +%s) + END_S))
  while watching && [ "$(date +%s)" -lt "$_end" ]; do sleep 0.2; done
  if watching; then
    watch_bad='watch-timeout'
    kill "$watch" 2>/dev/null
    _end=$(($(date +%s) + 5))
    while watching && [ "$(date +%s)" -lt "$_end" ]; do sleep 0.2; done
    watching && kill -9 "$watch" 2>/dev/null
  fi
  wait "$watch"
  _c=$?
  watch=
  say "the watch ended, exit $_c"
  if [ -z "$watch_bad" ] && [ "$_c" -ne 0 ]; then
    watch_bad="watch-exit-$_c"
  elif [ -z "$watch_bad" ] && [ ! -s "$tmp/watch.txt" ]; then
    watch_bad='no-guided'
  fi
}

# no_records: true when the guided file shows no changed file (section 1)
# and no record (section 3).
no_records() {
  awk '
    /^### 1\. / { s = 1; next }
    /^### 2\. / { s = 0; next }
    /^### 3\. / { s = 3; next }
    /^### [4-9]\. / { s = 0; next }
    s == 1 && NF { n++ }
    s == 3 && /^== / { n++ }
    END { exit n ? 1 : 0 }' "$tmp/watch.txt"
}

# finish RESULT: end the watch, stop the session, and write the output
# file. RESULT is ok or fail.
finish() {
  _r=$1
  end_watch
  say "stop the session"
  ses stop "$sess" >>"$tmp/log" 2>&1
  if [ -n "$watch_bad" ]; then
    [ "$_r" = fail ] || why=$watch_bad
    _r=fail
  fi
  if [ "$_r" = ok ] && [ -z "$why" ] && no_records; then
    why=no-records
  fi
  {
    echo "agent-signals session step: $KIT_STEP@$KIT_BACKEND, $(date -u +%Y%m%dT%H%M%SZ)"
    echo "kind: $KIT_KIND"
    echo "agent: $KIT_AGENT"
    echo "home: ${KIT_HOME:-}"
    if [ "${KIT_HOME:-}" = fixture ]; then
      echo "model: fake-model.py with fixed answers. No real model ran."
    fi
    echo "result: $_r${why:+ $why}"
    if [ "$KIT_AGENT" = claude ]; then
      echo "screens: the kit blanks each welcome box line that can show a display name or an organisation. No real screen was measured."
    fi
    echo
    echo "################ guided step"
    if [ -s "$tmp/watch.txt" ]; then
      cat "$tmp/watch.txt"
    else
      echo "no guided-step file. Its output:"
      cat "$tmp/watch.log" 2>/dev/null
    fi
    _i=1
    while [ "$_i" -le "$n_screens" ]; do
      echo
      echo "################ screen: $(cat "$tmp/screen.$_i.name")"
      # The screen with no blank lines at its end.
      awk 'NF { while (b > 0) { print ""; b-- } print; next } { b++ }' "$tmp/screen.$_i"
      _i=$((_i + 1))
    done
    echo
    echo "################ log"
    cat "$tmp/log"
  } >"$KIT_OUT"
  [ -n "$why" ] && reason "$why"
  [ "$_r" = ok ] && exit 0
  exit 1
}

# stop_now REASON: keep the last screen and end the step with "fail".
stop_now() {
  why=$1
  say "the step fails: $1"
  [ -s "$tmp/s" ] && save last "$tmp/s"
  finish fail
}

# bad CODE: end the step for the code 2 or 3 of a wait function.
bad() {
  case $1 in
    2) stop_now agent-ended ;;
    3) stop_now screen-failed ;;
  esac
}

# broken: end the step after a failed send or key.
broken() {
  alive || stop_now agent-ended
  stop_now send-failed
}

# send TEXT: type TEXT and push Enter. Codex can keep the text in its box and
# drop an Enter just after the first idle screen (fact 76). So the step waits
# 2 s, and looks for the text at the start of a word on the screen. A plain
# search finds "/new" in the path of the work folder. Claude Code puts a
# no-break space (C2 A0) after its box mark while the box holds text, and
# [[:space:]] does not match it in all locales. When the text is not
# there, the step clears the box with C-u and types the text again, so that a
# slow agent does not get it twice. It tries three times, then it presses
# Enter. Then, when the screen shows the text and is not idle, busy or a
# dialog, the box still holds the text: the step presses Enter again. The idle
# text of Codex shows only when its box is empty. The idle regex of Claude Code
# matches with text in the box, so this rule never fires there.
send() {
  sleep "$(clip 2)"
  _want="(^|[[:space:]]|$(printf '\302\240'))$(kit_text_re "$(printf '%s' "$1" | cut -c1-24)")"
  _try=0
  _seen=
  while [ "$_try" -lt 3 ] && [ -z "$_seen" ]; do
    if [ "$_try" -gt 0 ]; then
      say "the prompt is not on the screen. Clear the box and type it again"
      ses key "$sess" C-u >/dev/null || broken
      sleep 0.3
    fi
    _try=$((_try + 1))
    ses send "$sess" "$1" >/dev/null || broken
    _n=0
    while [ "$_n" -lt 6 ] && [ -z "$_seen" ]; do
      screen "$tmp/box" || broken
      grep -Eq -- "$_want" "$tmp/box" && _seen=yes
      [ -n "$_seen" ] || sleep 0.5
      _n=$((_n + 1))
    done
  done
  [ -n "$_seen" ] || say "the prompt did not show on the screen in $_try tries"
  ses key "$sess" Enter >/dev/null || broken
  _n=0
  while [ "$_n" -lt 3 ]; do
    _n=$((_n + 1))
    sleep 1
    screen "$tmp/box" || broken
    grep -Eq -- "$_want" "$tmp/box" || break
    has "$KIT_IDLE_REGEX" "$tmp/box" && break
    has "${KIT_BUSY_REGEX:-}" "$tmp/box" && break
    has "${KIT_DIALOG_REGEX:-}" "$tmp/box" && break
    has "${KIT_WAIT_REGEX:-}" "$tmp/box" && break
    say "the box still holds the prompt. Press Enter again"
    ses key "$sess" Enter >/dev/null || broken
  done
}

# keys KEYS: send the keys of a space list, as tmux names them.
keys() {
  [ -n "$1" ] || return 0
  # shellcheck disable=SC2086
  ses key "$sess" $1 >/dev/null || broken
}

why=
: >"$tmp/log"
: >"$tmp/s"
say "start a session of $KIT_AGENT on $KIT_BACKEND"
start_session
work=$(cat "$KIT_RUN/sessions/$sess/work")
mode=$(cat "$KIT_RUN/sessions/$sess/home-mode" 2>/dev/null)
home_dir=$HOME
[ "$mode" = real ] || home_dir=$KIT_RUN/home/$sess
say "wait for the idle screen ($IDLE_S s)"
wait_idle "$IDLE_S" "$tmp/s"
rc=$?
bad "$rc"
if [ "$rc" -ne 0 ]; then
  stop_now no-idle
fi
save idle "$tmp/s"

# The scope of the watch: the work folder, the throwaway home, and the
# project folder of the agent for the work folder. Claude Code can make
# that folder after the first prompt, so it need not exist now. It names
# the folder by the path with each character that is not a letter or a
# digit changed to "-".
set -- --scope "$work"
[ "$mode" != real ] && [ -d "$home_dir" ] && set -- "$@" --scope "$home_dir"
if [ "$KIT_AGENT" = claude ]; then
  for w in "$work" "$(cd "$work" && pwd -P)"; do
    set -- "$@" --scope-new "$home_dir/.claude/projects/$(printf '%s' "$w" | tr -c 'A-Za-z0-9' '-')"
  done
fi

wsecs=$(clip "$WATCH_S")
say "start the guided watch ($wsecs s at most)"
sh "$KIT_ROOT/probes/run.sh" --guided "$KIT_KIND" "$KIT_AGENT" --wait "$wsecs" \
  --pids "$KIT_RUN/pids" --files-of-pids "$@" --stop-file "$tmp/stop" --out "$tmp/watch.txt" \
  </dev/null >"$tmp/watch.log" 2>&1 &
watch=$!
watched=yes
end=$(($(date +%s) + $(clip 60)))
until grep -q '^kit: watch starts' "$tmp/watch.log"; do
  if ! watching; then
    say "the guided watch stopped before it started"
    stop_now no-watch
  fi
  if [ "$(date +%s)" -gt "$end" ]; then
    say "the guided watch did not start in time"
    stop_now no-watch
  fi
  sleep 0.2
done
say "the watch runs"

case $KIT_KIND in
  permission)
    say "send the prompt, wait for the dialog ($WAIT_S s)"
    send "$KIT_PROMPT"
    wait_re "$KIT_WAIT_REGEX" "$WAIT_S" "$tmp/s"
    rc=$?
    bad "$rc"
    if [ "$rc" -eq 0 ]; then
      watching || why=dialog-after-watch
      save dialog "$tmp/s"
      say "the dialog shows. Hold it for $HOLD_S s"
      sleep "$(clip "$HOLD_S")"
      alive || stop_now agent-ended
      say "send: $KIT_ANSWER"
    else
      save last "$tmp/s"
      why=no-dialog
      say "no dialog in $WAIT_S s. Send: $KIT_ANSWER"
    fi
    keys "${KIT_ANSWER:-}"
    sleep 1
    wait_idle "$AFTER_S" "$tmp/s"
    rc=$?
    bad "$rc"
    if [ "$rc" -ne 0 ]; then
      say "no idle screen after the answer"
      why=${why:-no-idle-after}
    fi
    save after "$tmp/s"
    ;;
  new-chat)
    say "send $KIT_PROMPT, wait for idle ($WAIT_S s)"
    send "$KIT_PROMPT"
    sleep 2
    wait_idle "$WAIT_S" "$tmp/s" "$KIT_PROMPT"
    rc=$?
    bad "$rc"
    if [ "$rc" -ne 0 ]; then
      stop_now prompt-on-screen
    fi
    save after "$tmp/s"
    ;;
  interrupt)
    say "send the prompt, wait for the busy screen ($WAIT_S s)"
    send "$KIT_PROMPT"
    wait_re "$KIT_WAIT_REGEX" "$WAIT_S" "$tmp/s"
    rc=$?
    bad "$rc"
    if [ "$rc" -ne 0 ]; then
      keys "${KIT_ANSWER%% *}"
      stop_now no-busy
    fi
    save busy "$tmp/s"
    for k in ${KIT_ANSWER:-}; do
      say "send $k"
      keys "$k"
      sleep 2
      screen "$tmp/s" || stop_now screen-failed
      save "after $k" "$tmp/s"
    done
    ;;
  resume)
    say "send a short prompt, wait for idle ($WAIT_S s)"
    send "Reply with the word ok."
    sleep 2
    wait_idle "$WAIT_S" "$tmp/s"
    rc=$?
    bad "$rc"
    if [ "$rc" -ne 0 ]; then
      say "no idle screen before the stop"
      why=no-idle-before-stop
    fi
    save "before stop" "$tmp/s"
    say "stop the session, and start it again with: $KIT_PROMPT"
    ses stop "$sess" --keep >>"$tmp/log" 2>&1
    keep=--keep
    start_session "${KIT_PROMPT:-}"
    keep=
    watching || why=${why:-restart-outside-watch}
    used=
    wait_idle "$IDLE_S" "$tmp/s"
    rc=$?
    bad "$rc"
    if [ "$rc" -ne 0 ]; then
      stop_now no-idle
    fi
    save after "$tmp/s"
    ;;
  *)
    reason "unknown-kind-$KIT_KIND"
    exit 1
    ;;
esac
finish ok
