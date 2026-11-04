#!/bin/sh
# kit session: start and drive a test session of one agent.
#
#   kit session start NAME AGENT --via tmux|pty [--cmd CMD] [--home real|throwaway]
#   kit session send NAME TEXT
#   kit session key NAME KEY...
#   kit session screen NAME
#   kit session wait NAME REGEX SECONDS
#   kit session stop NAME
#   kit session stop --all
#
# CMD is one simple command, for example "env NAME=VALUE prog arg". The
# agent starts as "exec CMD", so that its pid is the pid of the pane or of
# the pty.
#
# The tmux backend uses a private tmux server. The pty backend uses
# ptydrive.py: a plain pty with no multiplexer. The agent starts in a new
# work folder with a clean environment: only HOME, PATH, TERM, LANG and
# USER. With --home throwaway (the default), HOME is a new empty folder.
# With --home real, HOME is the real home. The kit copies no login.
#
# All state is in RUN/sessions/NAME/, so each command can run in a new
# shell:
#   backend    tmux or pty
#   agent      the agent name
#   home-mode  real or throwaway
#   work       the path of the work folder of the agent, RUN/work/NAME
#   socket     the path of the socket of the server
#   pid        the pid of the agent
#   pids       the pids of the session: lines "PID LABEL<tab>START"
#   last.screen  the last screen that "wait" read
#   stopped    the session has stopped
# A throwaway home is RUN/home/NAME.
# A socket path has a limit of about 104 bytes on macOS, so the socket is
# in a new short folder below /tmp, not in the run folder.
#
# Each started pid is also in RUN/pids/, with the label "session NAME
# ROLE". "stop" stops only these pids, never a process found by its name.
set -u
. "$(dirname "$0")/lib.sh"

COLS=120
ROWS=40
# The versions that the workflows pin.
PYTE="--with pyte==0.8.2 --with wcwidth==0.9.4"

usage() {
  sed -n 's/^#   kit session/usage: kit session/p' "$0" >&2
  exit 2
}

run=$(kit_run_dir) || exit $?

check_name() {
  case $1 in
    '' | *[!A-Za-z0-9_-]*) kit_die 2 "bad session name: $1" ;;
  esac
  [ "${#1}" -le 40 ] || kit_die 2 "the session name is too long: $1"
}

# open NAME: set sdir, backend and sock for a session that exists.
open_session() {
  check_name "$1"
  name=$1
  sdir=$run/sessions/$name
  [ -f "$sdir/backend" ] || kit_die 2 "no session: $name"
  backend=$(cat "$sdir/backend")
  sock=$(cat "$sdir/socket" 2>/dev/null || true)
}

# need_running: refuse a session that has stopped.
need_running() {
  [ ! -f "$sdir/stopped" ] || kit_die 1 "the session has stopped: $name"
}

# client ARGS: run the client of ptydrive.py. It needs no pyte.
client() {
  if command -v python3 >/dev/null 2>&1; then
    python3 "$KIT_DIR/ptydrive.py" "$sock" "$@"
  else
    uv run --no-project python "$KIT_DIR/ptydrive.py" "$sock" "$@"
  fi
}

tm() { tmux -S "$sock" "$@"; }

# add_pid PID LABEL: record a pid of the session in RUN/pids/ and in the
# pids file of the session.
add_pid() {
  kit_add_pid "$run" "$1" "$2"
  printf '%s %s\n' "$1" "$(cat "$run/pids/$1")" >>"$sdir/pids"
}

# label PIDFILE: the label of a pid file.
label() { awk -F '	' 'NR == 1 { print $1 }' "$1" 2>/dev/null; }

# track: add the agent, its descendants and the members of its process
# group to RUN/pids/ and to the pids file of the session. A daemon that leaves its parent
# (the Codex app-server, fact 067) stays in the group, or is found while
# its parent still runs.
track() {
  [ -f "$sdir/pid" ] || return 0
  a=$(cat "$sdir/pid")
  kit_pid_runs "$a" || return 0
  ps -A -o pid= -o ppid= -o pgid= 2>/dev/null | awk -v a="$a" '
    { pid[NR] = $1; ppid[NR] = $2; pgid[NR] = $3; n = NR }
    END {
      want[a] = 1
      for (i = 1; i <= n; i++) if (pgid[i] == a) want[pid[i]] = 1
      do {
        more = 0
        for (i = 1; i <= n; i++)
          if ((ppid[i] in want) && !(pid[i] in want)) { want[pid[i]] = 1; more = 1 }
      } while (more)
      for (p in want) print p
    }' | sort -n >"$sdir/track.tmp"
  while read -r p; do
    [ -n "$p" ] || continue
    [ -f "$run/pids/$p" ] || add_pid "$p" "session $name child"
  done <"$sdir/track.tmp"
  rm -f "$sdir/track.tmp"
  # A child that has ended (a short command of the agent) leaves the list.
  for f in "$run"/pids/*; do
    [ -f "$f" ] || continue
    case $(label "$f") in
      "session $name child")
        p=${f##*/}
        if ! kit_pid_ours "$run" "$p"; then
          rm -f "$f"
          awk -v p="$p" '$1 != p' "$sdir/pids" >"$sdir/pids.tmp" && mv "$sdir/pids.tmp" "$sdir/pids"
        fi
        ;;
    esac
  done
}

# grab: print the screen of the session. The format is that of
# tmux capture-pane -p -J, with no trailing spaces: a long path that the
# agent wraps stays on one line, so that the scrub finds it.
grab() {
  case $backend in
    tmux) tm capture-pane -p -J -t kit 2>/dev/null | sed 's/  *$//' ;;
    pty) client screen 2>/dev/null ;;
  esac
}

# pty_python: set serve_cmd to the path of a Python with pyte, or to "uv",
# or exit 3. The order: AGENT_SIGNALS_PYTHON, then RUN/.kit/python (the
# --python option of kit start), then uv, then python3. uv gives pyte in
# a temporary environment: no pip install changes the system Python.
# shellcheck disable=SC2086
pty_python() {
  serve_cmd=${AGENT_SIGNALS_PYTHON:-}
  if [ -z "$serve_cmd" ] && [ -r "$run/.kit/python" ]; then
    serve_cmd=$(head -n 1 "$run/.kit/python")
  fi
  if [ -n "$serve_cmd" ]; then
    "$serve_cmd" -c 'import pyte, wcwidth' </dev/null >/dev/null 2>&1 ||
      kit_die 3 "needs pyte: $serve_cmd has no pyte"
    return 0
  fi
  if command -v uv >/dev/null 2>&1 &&
    uv run --no-project $PYTE python -c 'import pyte' </dev/null >/dev/null 2>&1; then
    serve_cmd=uv
  elif command -v python3 >/dev/null 2>&1 &&
    python3 -c 'import pyte, wcwidth' </dev/null >/dev/null 2>&1; then
    serve_cmd=python3
  else
    kit_die 3 "needs pyte"
  fi
}

do_start() {
  [ "$#" -ge 2 ] || usage
  check_name "$1"
  name=$1
  agent=$2
  shift 2
  case $agent in
    '' | *[!A-Za-z0-9._-]*) kit_die 2 "bad agent name: $agent" ;;
  esac
  via='' cmd='' mode=${KIT_HOME:-throwaway}
  while [ "$#" -gt 0 ]; do
    case $1 in
      --via) [ "$#" -ge 2 ] || usage; via=$2; shift 2 ;;
      --cmd) [ "$#" -ge 2 ] || usage; cmd=$2; shift 2 ;;
      --home) [ "$#" -ge 2 ] || usage; mode=$2; shift 2 ;;
      *) usage ;;
    esac
  done
  case $via in
    tmux | pty) ;;
    '') kit_die 2 "give --via tmux or --via pty" ;;
    *) kit_die 2 "unknown backend: $via" ;;
  esac
  case $mode in
    real | throwaway) ;;
    *) kit_die 2 "--home is real or throwaway: $mode" ;;
  esac
  if [ -z "$cmd" ]; then
    command -v "$agent" >/dev/null 2>&1 || kit_die 3 "not installed: $agent"
    cmd=$agent
  fi
  case $via in
    tmux) command -v tmux >/dev/null 2>&1 || kit_die 3 "needs tmux" ;;
    pty) pty_python ;;
  esac
  sdir=$run/sessions/$name
  if [ -d "$sdir" ]; then
    [ -f "$sdir/stopped" ] || kit_die 2 "the session exists: $name"
    rm -rf "$sdir"
  fi
  work=$run/work/$name
  rm -rf "$work"
  mkdir -p "$sdir" "$work" || kit_die 1 "cannot make $sdir"
  chmod 700 "$sdir"
  backend=$via
  echo "$via" >"$sdir/backend"
  echo "$agent" >"$sdir/agent"
  echo "$mode" >"$sdir/home-mode"
  echo "$work" >"$sdir/work"
  : >"$sdir/pids"
  if [ "$mode" = real ]; then
    h=$HOME
    u=${USER:-$(id -un)}
  else
    h=$run/home/$name
    u=dev
    rm -rf "$h"
    mkdir -p "$h"
  fi
  sockdir=$(mktemp -d /tmp/as.XXXXXX) || kit_die 1 "mktemp failed"
  chmod 700 "$sockdir"
  # The agent starts with "exec", so that its pid is the pid of the pane
  # or of the pty.
  case $via in
    tmux)
      sock=$sockdir/tmux.sock
      echo "$sock" >"$sdir/socket"
      # remain-on-exit keeps the last screen after the agent ends.
      echo 'set -g remain-on-exit on' >"$sdir/tmux.conf"
      env -i HOME="$h" PATH="$PATH" TERM=xterm-256color LANG="${LANG:-C.UTF-8}" USER="$u" \
        tmux -S "$sock" -f "$sdir/tmux.conf" new-session -d -s kit \
        -x "$COLS" -y "$ROWS" -c "$work" \
        sh -c 'eval "exec $0"' "$cmd" </dev/null >"$sdir/server.log" 2>&1 ||
        kit_die 1 "tmux did not start: $(cat "$sdir/server.log")"
      server=$(tm display -p -t kit '#{pid}' 2>/dev/null)
      a=$(tm display -p -t kit '#{pane_pid}' 2>/dev/null)
      [ -n "$server" ] && add_pid "$server" "session $name server"
      ;;
    pty)
      sock=$sockdir/pty.sock
      echo "$sock" >"$sdir/socket"
      # serve_cmd is one path, or "uv" for the uv command line.
      if [ "$serve_cmd" = uv ]; then
        # shellcheck disable=SC2086
        set -- uv run --no-project $PYTE python
      else
        set -- "$serve_cmd"
      fi
      "$@" "$KIT_DIR/ptydrive.py" serve "$sock" "$COLS" "$ROWS" -- \
        env -i HOME="$h" PATH="$PATH" TERM=xterm-256color LANG="${LANG:-C.UTF-8}" USER="$u" \
        sh -c 'cd "$1" && eval "exec $0"' "$cmd" "$work" \
        </dev/null >"$sdir/server.log" 2>&1 ||
        kit_die 1 "ptydrive did not start: $(cat "$sdir/server.log")"
      client pids >"$sdir/pids.tmp" 2>/dev/null
      server=$(awk '$1 == "driver" { print $2 }' "$sdir/pids.tmp")
      a=$(awk '$1 == "agent" { print $2 }' "$sdir/pids.tmp")
      rm -f "$sdir/pids.tmp"
      [ -n "$server" ] && add_pid "$server" "session $name driver"
      ;;
  esac
  [ -n "${a:-}" ] || kit_die 1 "no agent pid"
  echo "$a" >"$sdir/pid"
  add_pid "$a" "session $name agent"
  track
  echo "session: $name $via $work"
}

do_send() {
  [ "$#" -eq 2 ] || usage
  open_session "$1"
  need_running
  case $backend in
    tmux) tm send-keys -t kit -l -- "$2" ;;
    pty) client send "$2" ;;
  esac || kit_die 1 "send failed"
  track
}

valid_key() {
  case $1 in
    Enter | Escape | Tab | BSpace | Space | Up | Down | Left | Right) return 0 ;;
    C-[a-z] | [0-9A-Za-z]) return 0 ;;
  esac
  return 1
}

do_key() {
  [ "$#" -ge 2 ] || usage
  open_session "$1"
  shift
  need_running
  for k in "$@"; do
    valid_key "$k" || kit_die 2 "unknown key: $k"
  done
  case $backend in
    tmux) tm send-keys -t kit "$@" ;;
    pty) client key "$@" ;;
  esac || kit_die 1 "key failed"
  track
}

do_screen() {
  [ "$#" -eq 1 ] || usage
  open_session "$1"
  need_running
  grab >"$sdir/screen.tmp" || { rm -f "$sdir/screen.tmp"; kit_die 1 "no screen"; }
  track
  cat "$sdir/screen.tmp"
  rm -f "$sdir/screen.tmp"
}

do_wait() {
  [ "$#" -eq 3 ] || usage
  open_session "$1"
  re=$2
  secs=$3
  case $secs in
    '' | *[!0-9]*) kit_die 2 "SECONDS is a number: $secs" ;;
  esac
  [ "$secs" -ge 1 ] && [ "$secs" -le 3600 ] || kit_die 2 "SECONDS is 1 to 3600: $secs"
  echo | grep -Eq -- "$re" 2>/dev/null
  [ "$?" -ne 2 ] || kit_die 2 "bad REGEX: $re"
  need_running
  end=$(($(date +%s) + secs))
  while :; do
    grab >"$sdir/wait.tmp" 2>/dev/null
    track
    if grep -Eq -- "$re" "$sdir/wait.tmp"; then
      mv "$sdir/wait.tmp" "$sdir/last.screen"
      return 0
    fi
    [ "$(date +%s)" -lt "$end" ] || break
    sleep 0.5
  done
  mv "$sdir/wait.tmp" "$sdir/last.screen"
  echo "kit: no match in $secs s: $re" >&2
  echo "$sdir/last.screen"
  exit 1
}

# end_pid PID WAIT: wait up to WAIT seconds for PID to end, then stop it.
# It sends a signal only to a pid of RUN/pids/ with its start time. It
# removes the pid file.
end_pid() {
  n=0
  while kit_pid_ours "$run" "$1" && [ "$n" -lt "$(($2 * 10))" ]; do
    sleep 0.1
    n=$((n + 1))
  done
  if kit_pid_ours "$run" "$1"; then
    echo "stop: $1 $(label "$run/pids/$1")"
    kill "$1" 2>/dev/null
    n=0
    while kit_pid_ours "$run" "$1" && [ "$n" -lt 20 ]; do
      sleep 0.1
      n=$((n + 1))
    done
    kit_pid_ours "$run" "$1" && kill -9 "$1" 2>/dev/null
  fi
  rm -f "$run/pids/$1"
}

# stop_session: stop the session in sdir.
stop_session() {
  [ -f "$sdir/stopped" ] && return 0
  track
  case $backend in
    tmux) [ -n "$sock" ] && tm kill-server >/dev/null 2>&1 ;;
    pty) [ -n "$sock" ] && client stop >/dev/null 2>&1 ;;
  esac
  # The agent can still write files for a short time after the hangup.
  for f in "$run"/pids/*; do
    [ -f "$f" ] || continue
    case $(label "$f") in
      "session $name "*) end_pid "$(basename "$f")" 5 ;;
    esac
  done
  [ -n "$sock" ] && rm -rf "$(dirname "$sock")"
  # Claude Code keeps task output outside HOME, in
  # /tmp/claude-<uid>/<key>/. The key is the work folder path with each
  # character that is not a letter or a digit changed to "-".
  work=$(cat "$sdir/work" 2>/dev/null || true)
  k=$(printf '%s' "$work" | tr -c 'A-Za-z0-9' '-')
  for t in /tmp "${TMPDIR:-/tmp}"; do
    t=${t%/}/claude-$(id -u)/$k
    [ -d "$t" ] && rm -rf "$t"
  done
  [ -n "$work" ] && rm -rf "$work"
  rm -rf "${run:?}/home/$name"
  : >"$sdir/stopped"
  echo "session: $name stopped"
}

do_stop() {
  [ "$#" -eq 1 ] || usage
  if [ "$1" = --all ]; then
    for d in "$run"/sessions/*/; do
      [ -f "$d/backend" ] || continue
      open_session "$(basename "$d")"
      stop_session
    done
    for f in "$run"/pids/*; do
      [ -f "$f" ] || continue
      end_pid "$(basename "$f")" 0
    done
    return 0
  fi
  open_session "$1"
  stop_session
}

[ "$#" -ge 1 ] || usage
action=$1
shift
case $action in
  start) do_start "$@" ;;
  send) do_send "$@" ;;
  key) do_key "$@" ;;
  screen) do_screen "$@" ;;
  wait) do_wait "$@" ;;
  stop) do_stop "$@" ;;
  *) usage ;;
esac
