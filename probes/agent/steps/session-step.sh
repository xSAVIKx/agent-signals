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
#      (REGEX=>KEYS;;...). Each pair is used one time at most. Wait for the
#      idle screen (60 s). The screen is idle when a line matches
#      KIT_IDLE_REGEX, and no line matches KIT_BUSY_REGEX or
#      KIT_DIALOG_REGEX.
#   3. Start the guided watch of probes/run.sh in the background, on the
#      pids of the run (RUN/pids/) only, for 90 s. Wait for its line
#      "kit: watch starts".
#   4. Do the action of the kind:
#      permission  send the prompt and Enter, wait for KIT_WAIT_REGEX (the
#                  dialog, 90 s), send KIT_ANSWER, wait for idle (10 s).
#      new-chat    send the prompt (/clear) and Enter, wait for idle.
#      interrupt   send the prompt and Enter, wait for KIT_WAIT_REGEX (the
#                  busy screen), then send each key of KIT_ANSWER, 2 s
#                  apart.
#      resume      send a short prompt and Enter, wait for idle, stop the
#                  session, start it again in the same work folder with
#                  the arguments KIT_PROMPT, wait for idle.
#   5. Stop the session, and wait until the watch ends.
# The output file holds the guided-step output, the screens (idle, dialog
# and after for permission) and a log of the step with the time of each
# stage.
#
# No dialog (or no busy screen) in the time limit gives "ok" with the
# reason "no-dialog" (or "no-busy"), and the file keeps the last screen.
# No idle screen gives "fail" with the reason "no-idle".
#
# The step prints a "kit: " line on stderr at each stage. A whole step
# takes less than about 4 minutes, so that it fits in the time limit of
# the shell tool of an agent. With AGENT_SIGNALS_WATCH set (the tests), the
# watch and each wait take that number of seconds at most.
set -u
: "${KIT_RUN:?}" "${KIT_ROOT:?}" "${KIT_DIR:?}" "${KIT_OUT:?}" "${KIT_STEP:?}" "${KIT_KIND:?}"
: "${KIT_AGENT:?}" "${KIT_BACKEND:?}"
. "$KIT_DIR/lib.sh"

AGENT_SIGNALS_RUN=$KIT_RUN
export AGENT_SIGNALS_RUN

# lim SECONDS: a time limit. AGENT_SIGNALS_WATCH makes it shorter.
lim() {
  if [ -n "${AGENT_SIGNALS_WATCH:-}" ] && [ "$AGENT_SIGNALS_WATCH" -lt "$1" ]; then
    echo "$AGENT_SIGNALS_WATCH"
  else
    echo "$1"
  fi
}
IDLE_S=$(lim 60)
WAIT_S=$(lim 90)
WATCH_S=$(lim 90)
AFTER_S=$(lim 10)

say() { echo "kit: $KIT_STEP@$KIT_BACKEND: $*" >&2; echo "$(date -u +%H:%M:%S) $*" >>"$tmp/log"; }
reason() { echo "$1" >"$KIT_OUT.reason"; }

case $KIT_BACKEND in
  tmux | pty) ;;
  *)
    reason "no-backend-$KIT_BACKEND"
    exit 3
    ;;
esac
cmd=$(kit_agent_command "$KIT_AGENT")
if [ -z "$cmd" ]; then
  reason not-installed
  exit 3
fi

tmp=$(mktemp -d "$(dirname "$KIT_OUT")/session.XXXXXX") || exit 1
# The session name: letters, digits and "-", 40 characters at most.
sess=$(printf '%s' "$KIT_STEP" | cut -c1-30)-$KIT_BACKEND
watch=
# dash runs no EXIT trap on a signal, so a signal exits first.
trap 'exit 130' INT TERM
trap 'cleanup' EXIT
cleanup() {
  [ -n "$watch" ] && kill "$watch" 2>/dev/null
  sh "$KIT_DIR/session.sh" stop "$sess" >/dev/null 2>&1
  rm -rf "$tmp"
}

ses() { sh "$KIT_DIR/session.sh" "$@"; }

# screen FILE: the screen of the session now.
screen() { ses screen "$sess" >"$1" 2>/dev/null; }

# has RE FILE: true when RE is not empty and a line of FILE matches it.
has() { [ -n "$1" ] && grep -Eq -- "$1" "$2"; }

# is_idle FILE: the idle rule of steps.tsv. With no idle regex (the Cursor
# CLI), a screen with text and no busy or dialog line is idle.
is_idle() {
  if [ -n "${KIT_IDLE_REGEX:-}" ]; then
    has "$KIT_IDLE_REGEX" "$1" || return 1
  else
    grep -q '[^[:space:]]' "$1" || return 1
  fi
  has "${KIT_BUSY_REGEX:-}" "$1" && return 1
  has "${KIT_DIALOG_REGEX:-}" "$1" && return 1
  return 0
}

# keys KEYS: send the keys of a space list, as tmux names them.
keys() {
  # shellcheck disable=SC2086
  [ -n "$1" ] && ses key "$sess" $1 >/dev/null
}

# wait_idle SECONDS FILE: answer the KIT_PRE pairs and wait for the idle
# screen. FILE gets the last screen.
used=
wait_idle() {
  _end=$(($(date +%s) + $1))
  while :; do
    screen "$2"
    _sent=
    if [ -n "${KIT_PRE:-}" ]; then
      _n=0
      _rest=$KIT_PRE
      while [ -n "$_rest" ]; do
        _pair=${_rest%%;;*}
        case $_rest in *';;'*) _rest=${_rest#*;;} ;; *) _rest= ;; esac
        _n=$((_n + 1))
        case " $used " in *" $_n "*) continue ;; esac
        _re=${_pair%%=>*}
        _k=${_pair#*=>}
        if has "$_re" "$2"; then
          say "pre answer $_n: $_k"
          used="$used $_n"
          keys "$_k"
          _sent=1
          break
        fi
      done
    fi
    if [ -z "$_sent" ] && is_idle "$2"; then
      return 0
    fi
    [ "$(date +%s)" -lt "$_end" ] || return 1
    sleep 1
  done
}

# wait_re RE SECONDS FILE: wait until a line of the screen matches RE.
wait_re() {
  _end=$(($(date +%s) + $2))
  while :; do
    screen "$3"
    has "$1" "$3" && return 0
    [ "$(date +%s)" -lt "$_end" ] || return 1
    sleep 0.5
  done
}

# start_session [ARGS]: start the session with the agent command and ARGS.
start_session() {
  if ! ses start "$sess" "$KIT_AGENT" --via "$KIT_BACKEND" --cmd "$cmd${1:+ $1}" >"$tmp/start" 2>&1; then
    _c=$?
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

# save NAME FILE: keep FILE as the screen NAME.
n_screens=0
save() {
  n_screens=$((n_screens + 1))
  cp "$2" "$tmp/screen.$n_screens"
  echo "$1" >"$tmp/screen.$n_screens.name"
}

# finish RESULT: stop the session, wait for the watch, and write the
# output file. RESULT is ok or fail.
finish() {
  say "stop the session"
  ses stop "$sess" >>"$tmp/log" 2>&1
  if [ -n "$watch" ]; then
    say "wait for the end of the watch"
    wait "$watch"
    wcode=$?
    watch=
    say "the watch ended, exit $wcode"
  fi
  {
    echo "agent-signals session step: $KIT_STEP@$KIT_BACKEND, $(date -u +%Y%m%dT%H%M%SZ)"
    echo "kind: $KIT_KIND"
    echo "agent: $KIT_AGENT"
    echo "result: $1${why:+ $why}"
    echo
    echo "################ guided step"
    if [ -s "$tmp/watch.txt" ]; then
      cat "$tmp/watch.txt"
    else
      echo "no guided-step file. Its output:"
      cat "$tmp/watch.log" 2>/dev/null
    fi
    i=1
    while [ "$i" -le "$n_screens" ]; do
      echo
      echo "################ screen: $(cat "$tmp/screen.$i.name")"
      # The screen with no blank lines at its end.
      awk 'NF { while (b > 0) { print ""; b-- } print; next } { b++ }' "$tmp/screen.$i"
      i=$((i + 1))
    done
    echo
    echo "################ log"
    cat "$tmp/log"
  } >"$KIT_OUT"
  [ -n "$why" ] && reason "$why"
  [ "$1" = ok ] && exit 0
  exit 1
}

why=
: >"$tmp/log"
say "start a session of $KIT_AGENT on $KIT_BACKEND"
start_session
work=$(cat "$KIT_RUN/sessions/$sess/work")
say "wait for the idle screen ($IDLE_S s)"
if ! wait_idle "$IDLE_S" "$tmp/s"; then
  save idle "$tmp/s"
  why=no-idle
  finish fail
fi
save idle "$tmp/s"

# The scope of the watch: the work folder, the throwaway home, and the
# project folder of the agent for the work folder, when it exists. Claude
# Code names the folder by the path with each character that is not a
# letter or a digit changed to "-".
set -- --scope "$work"
mode=$(cat "$KIT_RUN/sessions/$sess/home-mode" 2>/dev/null)
if [ "$mode" = throwaway ] && [ -d "$KIT_RUN/home/$sess" ]; then
  set -- "$@" --scope "$KIT_RUN/home/$sess"
  h=$KIT_RUN/home/$sess
else
  h=$HOME
fi
if [ "$KIT_AGENT" = claude ]; then
  real=$(cd "$work" && pwd -P)
  for w in "$work" "$real"; do
    p=$h/.claude/projects/$(printf '%s' "$w" | tr -c 'A-Za-z0-9' '-')
    [ -d "$p" ] && set -- "$@" --scope "$p"
  done
fi

say "start the guided watch ($WATCH_S s)"
sh "$KIT_ROOT/probes/run.sh" --guided "$KIT_KIND" "$KIT_AGENT" --wait "$WATCH_S" \
  --pids "$KIT_RUN/pids" --files-of-pids "$@" --out "$tmp/watch.txt" \
  </dev/null >"$tmp/watch.log" 2>&1 &
watch=$!
end=$(($(date +%s) + 60))
until grep -q '^kit: watch starts' "$tmp/watch.log"; do
  if ! kill -0 "$watch" 2>/dev/null; then
    wait "$watch"
    say "the guided watch stopped before it started, exit $?"
    watch=
    why=no-watch
    finish fail
  fi
  if [ "$(date +%s)" -gt "$end" ]; then
    say "the guided watch did not start in 60 s"
    why=no-watch
    finish fail
  fi
  sleep 0.2
done
say "the watch runs"

# send TEXT: type TEXT and push Enter.
send() {
  ses send "$sess" "$1" >/dev/null && ses key "$sess" Enter >/dev/null
}

case $KIT_KIND in
  permission)
    say "send the prompt, wait for the dialog ($WAIT_S s)"
    send "$KIT_PROMPT"
    if wait_re "$KIT_WAIT_REGEX" "$WAIT_S" "$tmp/s"; then
      save dialog "$tmp/s"
      say "the dialog shows. Send: $KIT_ANSWER"
    else
      save last "$tmp/s"
      why=no-dialog
      say "no dialog in $WAIT_S s. Send: $KIT_ANSWER"
    fi
    keys "${KIT_ANSWER:-}"
    sleep 1
    wait_idle "$AFTER_S" "$tmp/s" || say "no idle screen after the answer"
    save after "$tmp/s"
    ;;
  new-chat)
    say "send $KIT_PROMPT, wait for idle ($WAIT_S s)"
    send "$KIT_PROMPT"
    sleep 2
    wait_idle "$WAIT_S" "$tmp/s" || { why=no-idle; say "no idle screen"; }
    save after "$tmp/s"
    ;;
  interrupt)
    say "send the prompt, wait for the busy screen ($WAIT_S s)"
    send "$KIT_PROMPT"
    if wait_re "$KIT_WAIT_REGEX" "$WAIT_S" "$tmp/s"; then
      save busy "$tmp/s"
    else
      save last "$tmp/s"
      why=no-busy
    fi
    for k in ${KIT_ANSWER:-}; do
      say "send $k"
      keys "$k"
      sleep 2
      screen "$tmp/s"
      save "after $k" "$tmp/s"
    done
    ;;
  resume)
    say "send a short prompt, wait for idle ($WAIT_S s)"
    send "Reply with the word ok."
    sleep 2
    wait_idle "$WAIT_S" "$tmp/s" || say "no idle screen"
    save "before stop" "$tmp/s"
    say "stop the session, and start it again with: $KIT_PROMPT"
    ses stop "$sess" >>"$tmp/log" 2>&1
    start_session "${KIT_PROMPT:-}"
    used=
    if wait_idle "$IDLE_S" "$tmp/s"; then :; else why=no-idle; say "no idle screen after the new start"; fi
    save after "$tmp/s"
    ;;
  *)
    reason "unknown-kind-$KIT_KIND"
    exit 1
    ;;
esac
finish ok
