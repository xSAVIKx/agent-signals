#!/bin/sh
# kit session: start and drive a test session of one agent.
#
#   kit session start NAME AGENT --via tmux|pty [--cmd CMD] [--args ARGS] [--home real|throwaway|fixture]
#   kit session send NAME TEXT
#   kit session key NAME KEY...
#   kit session screen NAME
#   kit session wait NAME REGEX SECONDS
#   kit session stop NAME
#   kit session stop NAME --keep   the work folder and the home stay
#   kit session stop --all
#
# CMD is one simple command, for example "env NAME=VALUE prog arg". The
# agent starts as "exec CMD", so that its pid is the pid of the pane or of
# the pty. ARGS is a list of words, separated by spaces: the NAME=VALUE
# words at its start go into the environment of the agent, and the other
# words go after CMD. The column "args" of steps.tsv gives ARGS, for
# example "CLAUDE_CODE_AUTO_MODE_SERVER=0 --permission-mode auto".
#
# The tmux backend uses a private tmux server. The pty backend uses
# ptydrive.py: a plain pty with no multiplexer. The agent starts in a new
# work folder with a clean environment: only HOME, PATH, TERM, LANG and
# USER. With --home throwaway, HOME is a new empty folder. With --home
# real, HOME is the real home. The default comes from KIT_HOME, else from
# the manifest of the run, else throwaway. The kit copies no login.
#
# All state is in RUN/sessions/NAME/, so each command can run in a new
# shell:
#   backend    tmux or pty
#   agent      the agent name
#   home-mode  real, throwaway or fixture
#   work       the path of the work folder of the agent, RUN/work/NAME
#   conditions the conditions of the start: the command, the names of the
#              variables of the environment, and the settings files of
#              settings-files.tsv. Written before the agent starts.
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

# start_fake_model AGENT HOME: start fake-model.py for AGENT, and wait for
# the file of variables that it writes after the settings files in HOME.
start_fake_model() {
  command -v python3 >/dev/null 2>&1 || kit_die 3 "needs python3"
  rm -f "$sdir/fake-model.env"
  python3 "$KIT_DIR/fake-model.py" --agent "$1" --home "$2" --env-file "$sdir/fake-model.env" \
    --log "$sdir/fake-model.log" \
    </dev/null >/dev/null 2>&1 3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&- &
  add_pid "$!" "session $name fake model"
  _n=0
  while [ ! -f "$sdir/fake-model.env" ]; do
    [ "$_n" -lt 300 ] || kit_die 1 "the fake model did not start"
    _n=$((_n + 1))
    sleep 0.1
  done
}

# json_keys FILE: the top-level keys of the JSON object in FILE, separated
# by ", ". Empty when FILE is not a JSON object or python3 is missing.
json_keys() {
  command -v python3 >/dev/null 2>&1 || return 0
  python3 -I -c 'import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    sys.exit(0)
if isinstance(d, dict):
    print(", ".join(sorted(d)))' "$1" 2>/dev/null
}

# file_facts FILE: the start of the SHA-256, the size and the JSON keys of
# FILE, or
# "a folder" for a folder.
file_facts() {
  if [ -d "$1" ]; then
    echo "a folder"
    return 0
  fi
  _k=$(json_keys "$1")
  # 12 hex characters: the scrub of the kit changes a run of 16 or more.
  printf 'sha256 %s, %s bytes%s\n' "$(kit_sha256 "$1" | cut -c1-12)" "$(wc -c <"$1" | tr -d ' ')" "${_k:+, keys: $_k}"
}

# write_conditions VAR=VALUE...: write $sdir/conditions. It reads cmd,
# mode, h, work, agent and step_env. The values of the variables stay out:
# a real environment can hold a token.
write_conditions() {
  {
    echo "command: $cmd"
    printf 'environment:'
    for kv in "$@"; do echo "${kv%%=*}"; done | awk '!seen[$0]++ { printf " %s", $0 }'
    echo
    [ -z "$step_env" ] || echo "environment from the step: $step_env"
    case $mode in
      fixture) echo "home: fixture, made by the kit, with the fake model of the kit" ;;
      throwaway) echo "home: throwaway, made by the kit, with no login" ;;
      real) echo "home: real, the home of the operator" ;;
    esac
    _os=$(kit_os)
    awk -F '\t' -v a="$agent" -v o="$_os" '!/^#/ && NF == 4 && $1 == a && ($3 == "all" || $3 == o) { print $2 "\t" $4 }' \
      "$KIT_DIR/settings-files.tsv" >"$sdir/settings.list"
    _home=0 _proj=0
    while IFS='	' read -r _scope _p; do
      case $_scope in
        home)
          [ -e "$h/$_p" ] || continue
          _home=$((_home + 1))
          echo "home file: $_p, $(file_facts "$h/$_p")"
          if [ "$mode" != real ] && [ -f "$h/$_p" ]; then
            sed -n '1,200s/^/  | /p' "$h/$_p"
          fi
          ;;
        project)
          _d=$work _n=0
          while :; do
            if [ -e "$_d/$_p" ]; then
              _proj=$((_proj + 1))
              echo "project file: $_p, $_n folders above the work folder, $(file_facts "$_d/$_p")"
            fi
            [ "$_d" != / ] && [ -n "$_d" ] || break
            _d=$(dirname "$_d")
            _n=$((_n + 1))
          done
          ;;
        machine)
          if [ -e "$_p" ]; then
            echo "machine file: $_p, $(file_facts "$_p")"
          else
            echo "machine file: $_p, absent"
          fi
          ;;
      esac
    done <"$sdir/settings.list"
    rm -f "$sdir/settings.list"
    # An agent can give access to temp folders with no question (the
    # default preset of agy). A work folder or an outside folder in a temp
    # folder changes the result of a write step.
    echo "work folder in a temp folder: $(kit_temp_place "$work")"
    [ "$_home" -gt 0 ] || echo "home file: none"
    [ "$_proj" -gt 0 ] || echo "project file: none"
    # The sandbox of Codex runs its commands and its file edits. When the
    # host does not let it start (bwrap with no user namespaces), Codex
    # asks to run them with no sandbox, in each approval mode.
    if [ "$agent" = codex ]; then
      _c=$(kit_agent_command codex)
      if [ -n "$_c" ]; then
        # A time limit of 10 s: a program that does not know the command
        # can wait for input. It stops by its pid.
        (cd "$work" && exec env -i "$@" "$_c" sandbox -- true) </dev/null >"$sdir/sandbox.out" 2>&1 &
        _p=$!
        _n=0
        while kill -0 "$_p" 2>/dev/null && [ "$_n" -lt 50 ]; do
          sleep 0.2
          _n=$((_n + 1))
        done
        if kill -0 "$_p" 2>/dev/null; then
          kill "$_p" 2>/dev/null
          sleep 0.5
          kill -9 "$_p" 2>/dev/null
          wait "$_p" 2>/dev/null
          echo "codex sandbox: not known ('codex sandbox -- true' did not end in 10 s)"
        else
          wait "$_p"
          _rc=$?
          if [ "$_rc" -eq 0 ]; then
            echo "codex sandbox: works ('codex sandbox -- true' exits 0)"
          else
            echo "codex sandbox: fails ('codex sandbox -- true' exits $_rc): $(grep -v '^WARNING' "$sdir/sandbox.out" | head -n 1 | cut -c1-160)"
          fi
        fi
        rm -f "$sdir/sandbox.out"
      fi
    fi
  } >"$sdir/conditions"
}

# label PIDFILE: the label of a pid file.
label() { awk -F '	' 'NR == 1 { print $1 }' "$1" 2>/dev/null; }

# track: add the agent, its descendants and the members of its process
# group to RUN/pids/ and to the pids file of the session. A daemon that
# leaves its parent (the Codex app-server, fact 067) stays in the group, or
# is found while its parent still runs.
track() {
  [ -f "$sdir/pid" ] || return 0
  a=$(cat "$sdir/pid")
  kit_pid_ours "$run" "$a" || return 0
  trk_f=$(mktemp "$sdir/track.XXXXXX") || return 0
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
    }' | sort -n >"$trk_f"
  while read -r p; do
    [ -n "$p" ] || continue
    [ -f "$run/pids/$p" ] || add_pid "$p" "session $name child"
  done <"$trk_f"
  rm -f "$trk_f"
  # A child that has ended (a short command of the agent) leaves the list.
  for f in "$run"/pids/*; do
    [ -f "$f" ] || continue
    case $(label "$f") in
      "session $name child")
        p=${f##*/}
        if ! kit_pid_ours "$run" "$p"; then
          rm -f "$f"
          trk_f=$(mktemp "$sdir/pids.XXXXXX") &&
            awk -v p="$p" '$1 != p' "$sdir/pids" >"$trk_f" && mv "$trk_f" "$sdir/pids"
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

# pty_serve VAR=VALUE...: start ptydrive.py serve with the agent command
# in a clean environment that holds only the VAR=VALUE pairs. It reads
# serve_cmd (a path, or "uv"), sock, cmd and work.
pty_serve() {
  if [ "$serve_cmd" = uv ]; then
    # shellcheck disable=SC2086
    uv run --no-project $PYTE python "$KIT_DIR/ptydrive.py" serve "$sock" "$COLS" "$ROWS" -- \
      env -i "$@" sh -c 'cd "$1" && eval "exec $0"' "$cmd" "$work"
  else
    "$serve_cmd" "$KIT_DIR/ptydrive.py" serve "$sock" "$COLS" "$ROWS" -- \
      env -i "$@" sh -c 'cd "$1" && eval "exec $0"' "$cmd" "$work"
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
  # The home mode: --home, else KIT_HOME, else the line "meta home MODE"
  # that kit start writes to the manifest, else throwaway.
  via='' cmd='' keep='' args='' mode=${KIT_HOME:-}
  if [ -z "$mode" ] && [ -r "$run/manifest.tsv" ]; then
    mode=$(awk -F '\t' '$1 == "meta" && $2 == "home" { m = $3 } END { print m }' "$run/manifest.tsv")
  fi
  mode=${mode:-throwaway}
  while [ "$#" -gt 0 ]; do
    case $1 in
      --via) [ "$#" -ge 2 ] || usage; via=$2; shift 2 ;;
      --cmd) [ "$#" -ge 2 ] || usage; cmd=$2; shift 2 ;;
      --args) [ "$#" -ge 2 ] || usage; args=$2; shift 2 ;;
      --home) [ "$#" -ge 2 ] || usage; mode=$2; shift 2 ;;
      --keep) keep=yes; shift ;;
      *) usage ;;
    esac
  done
  case $via in
    tmux | pty) ;;
    '') kit_die 2 "give --via tmux or --via pty" ;;
    *) kit_die 2 "unknown backend: $via" ;;
  esac
  case $mode in
    real | throwaway | fixture) ;;
    *) kit_die 2 "--home is real, throwaway or fixture: $mode" ;;
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
  # --keep: the resume step starts a session again. The new start needs the
  # work folder and the home of the old session.
  [ -n "$keep" ] || rm -rf "$work"
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
    [ -n "$keep" ] || rm -rf "$h"
    mkdir -p "$h"
  fi
  # The environment of the agent. LC_ALL and LC_CTYPE pass only when they
  # name UTF-8.
  term=xterm-256color
  echo "$term" >"$sdir/term"
  lang=${LANG:-}
  set -- HOME="$h" PATH="$PATH" TERM="$term" USER="$u"
  for v in LC_ALL LC_CTYPE; do
    x=
    eval "x=\${$v:-}"
    case $x in
      *[Uu][Tt][Ff]-8* | *[Uu][Tt][Ff]8*)
        set -- "$@" "$v=$x"
        [ -n "$lang" ] || lang=$x
        ;;
    esac
  done
  set -- "$@" LANG="${lang:-C.UTF-8}"
  # Claude Code keeps its settings in CLAUDE_CONFIG_DIR. On macOS its login
  # is in the Keychain, which a throwaway home does not isolate.
  [ "$mode" = real ] || set -- "$@" CLAUDE_CONFIG_DIR="$h/.claude"
  if [ "$mode" = fixture ] && [ -z "$(kit_login_skip fixture login "$agent")" ]; then
    start_fake_model "$agent" "$h"
    while IFS= read -r kv; do
      set -- "$@" "$kv"
    done <"$sdir/fake-model.env"
  fi
  # The words of --args: NAME=VALUE words at the start go into the
  # environment, the others after the command. Each word goes in single
  # quotes, because the start runs the command with eval: a JSON value such
  # as {"permissions":{"ask":["write_file(*)"]}} must stay one word.
  step_env=
  if [ -n "$args" ]; then
    set -f
    _rest=
    for w in $args; do
      case $_rest$w in
        [A-Za-z_]*=*)
          set -- "$@" "$w"
          step_env="${step_env:+$step_env }$w"
          ;;
        *) _rest="$_rest '$(printf '%s' "$w" | sed "s/'/'\\\\''/g")'" ;;
      esac
    done
    set +f
    cmd="$cmd$_rest"
  fi
  write_conditions "$@"
  sockdir=$(mktemp -d /tmp/as.XXXXXX) || kit_die 1 "mktemp failed"
  chmod 700 "$sockdir"
  # The agent starts with "exec", so that its pid is the pid of the pane
  # or of the pty. The servers get no file of the caller above fd 2: the
  # tmux server keeps each file that it gets, and an open pipe of the
  # caller would wait until the session ends. sh can close fd 3 to 9 only;
  # ptydrive.py closes all others itself.
  case $via in
    tmux)
      sock=$sockdir/tmux.sock
      echo "$sock" >"$sdir/socket"
      # remain-on-exit keeps the last screen after the agent ends. The
      # pane gets the TERM of the pty backend.
      printf 'set -g remain-on-exit on\nset -g default-terminal %s\n' "$term" >"$sdir/tmux.conf"
      env -i "$@" \
        tmux -S "$sock" -f "$sdir/tmux.conf" new-session -d -s kit \
        -x "$COLS" -y "$ROWS" -c "$work" \
        sh -c 'eval "exec $0"' "$cmd" </dev/null >"$sdir/server.log" 2>&1 \
        3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&- ||
        kit_die 1 "tmux did not start: $(cat "$sdir/server.log")"
      server=$(tm display -p -t kit '#{pid}' 2>/dev/null)
      a=$(tm display -p -t kit '#{pane_pid}' 2>/dev/null)
      [ -n "$server" ] && add_pid "$server" "session $name server"
      ;;
    pty)
      sock=$sockdir/pty.sock
      echo "$sock" >"$sdir/socket"
      pty_serve "$@" </dev/null >"$sdir/server.log" 2>&1 \
        3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&- ||
        kit_die 1 "ptydrive did not start: $(cat "$sdir/server.log")"
      start_f=$(mktemp "$sdir/pids.XXXXXX") || kit_die 1 "mktemp failed"
      client pids >"$start_f" 2>/dev/null
      server=$(awk '$1 == "driver" { print $2 }' "$start_f")
      a=$(awk '$1 == "agent" { print $2 }' "$start_f")
      rm -f "$start_f"
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
  screen_f=$(mktemp "$sdir/screen.XXXXXX") || kit_die 1 "mktemp failed"
  grab >"$screen_f" || { rm -f "$screen_f"; kit_die 1 "no screen"; }
  track
  cat "$screen_f"
  rm -f "$screen_f"
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
  wait_f=$(mktemp "$sdir/wait.XXXXXX") || kit_die 1 "mktemp failed"
  while :; do
    grab >"$wait_f" 2>/dev/null
    track
    if grep -Eq -- "$re" "$wait_f"; then
      mv "$wait_f" "$sdir/last.screen"
      return 0
    fi
    [ "$(date +%s)" -lt "$end" ] || break
    sleep 0.5
  done
  mv "$wait_f" "$sdir/last.screen"
  echo "kit: no match in $secs s: $re" >&2
  echo "$sdir/last.screen"
  exit 1
}

# end_pids PID...: stop the pids of RUN/pids/ in the list. It sends TERM
# to each pid that runs with its recorded start time, waits once for all of
# them (5 s), then sends KILL to the rest. It removes their pid files.
end_pids() {
  for p in "$@"; do
    if kit_pid_ours "$run" "$p"; then
      echo "stop: $p $(label "$run/pids/$p")"
      kill "$p" 2>/dev/null
    fi
  done
  n=0
  while [ "$n" -lt 50 ]; do
    left=
    for p in "$@"; do
      kit_pid_ours "$run" "$p" && left=1 && break
    done
    [ -n "$left" ] || break
    sleep 0.1
    n=$((n + 1))
  done
  for p in "$@"; do
    kit_pid_ours "$run" "$p" && kill -9 "$p" 2>/dev/null
    rm -f "$run/pids/$p"
  done
}

# session_pids: the pids of RUN/pids/ with the label "session NAME ...".
session_pids() {
  for f in "$run"/pids/*; do
    [ -f "$f" ] || continue
    case $(label "$f") in
      "session $name "*) echo "${f##*/}" ;;
    esac
  done
}

# end_home_daemons: stop each process that runs a program from the
# throwaway home of the session, $run/home/$name. Codex starts its
# app-server daemon from HOME/.codex/packages/ in its own process group
# (fact 067), so the group of the agent does not hold it. Each such process
# was started by this session: the home is new and only the session uses
# it. A real home is not in $run/home, so this never stops a daemon of the
# operator.
end_home_daemons() {
  hd=${run:?}/home/$name/
  [ -d "$hd" ] || return 0
  hp=$(ps -A -o pid= -o args= 2>/dev/null | awk -v h="$hd" 'index($0, h) { print $1 }')
  [ -n "$hp" ] || return 0
  for p in $hp; do
    echo "stop: $p daemon"
    kill "$p" 2>/dev/null
  done
  sleep 1
  for p in $hp; do kill -9 "$p" 2>/dev/null; done
  return 0
}

# remove_folders: delete the work folder and the home of the session in sdir.
remove_folders() {
  # Claude Code keeps task output outside HOME, in
  # /tmp/claude-<uid>/<key>/. The key is the work folder path with each
  # character that is not a letter or a digit changed to "-". On macOS the
  # real path (/private/var/...) can differ from the given path, so both
  # forms are removed.
  work=$(cat "$sdir/work" 2>/dev/null || true)
  if [ -n "$work" ]; then
    real=$(cd "$work" 2>/dev/null && pwd -P)
    for w in "$work" ${real:+"$real"}; do
      k=$(printf '%s' "$w" | tr -c 'A-Za-z0-9' '-')
      for t in /tmp "${TMPDIR:-/tmp}"; do
        t=${t%/}/claude-$(id -u)/$k
        [ -d "$t" ] && rm -rf "$t"
      done
    done
    rm -rf "$work"
  fi
  rm -rf "${run:?}/home/$name"
}

# stop_session [--keep]: stop the session in sdir. With --keep, the work
# folder and the home stay, and the file "kept" says so. A later stop without
# --keep deletes them.
stop_session() {
  if [ -f "$sdir/stopped" ]; then
    if [ -f "$sdir/kept" ] && [ "${1:-}" != --keep ]; then
      remove_folders
      rm -f "$sdir/kept"
    fi
    return 0
  fi
  track
  # The server hangs up the agent first, so that it can end in its own way.
  case $backend in
    tmux) [ -n "$sock" ] && tm kill-server >/dev/null 2>&1 ;;
    pty) [ -n "$sock" ] && client stop >/dev/null 2>&1 ;;
  esac
  # shellcheck disable=SC2046
  end_pids $(session_pids)
  end_home_daemons
  [ -n "$sock" ] && rm -rf "$(dirname "$sock")"
  if [ "${1:-}" = --keep ]; then
    : >"$sdir/kept"
  else
    remove_folders
  fi
  : >"$sdir/stopped"
  echo "session: $name stopped"
}

do_stop() {
  case $#:${2:-} in 1: | 2:--keep) ;; *) usage ;; esac
  if [ "$1" = --all ]; then
    for d in "$run"/sessions/*/; do
      [ -f "$d/backend" ] || continue
      open_session "$(basename "$d")"
      stop_session
    done
    set --
    for f in "$run"/pids/*; do
      [ -f "$f" ] && set -- "$@" "${f##*/}"
    done
    [ "$#" -eq 0 ] || end_pids "$@"
    return 0
  fi
  open_session "$1"
  stop_session ${2:+"$2"}
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
