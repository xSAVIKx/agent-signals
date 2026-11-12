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
# "stop --all" stops each session and each pid of RUN/pids/. Then, when a
# "kit trace" that does not run left RUN/.trace, it removes that folder and
# the folder of the file watcher of that trace (kit_trace_leftover).
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
#   work       the path of the work folder of the agent: ROOT/NAME, where
#              ROOT is RUN/work or a folder outside the temp folders
#              (kit_work_root in lib.sh)
#   conditions the conditions of the start: the command, the names of the
#              variables of the environment, and the settings files of
#              settings-files.tsv. Written before the agent starts.
#   socket     the path of the socket of the server
#   pid        the pid of the agent
#   pids       the pids of the session: lines "PID LABEL<tab>START"
#   last.screen  the last screen that "wait" read
#   stopped    the session has stopped
#   trace      the trace folder (KIT_TRACE) of a recorded tmux session
#   recorder.pid  the pid of the recorder (trace-cast.py)
#   recorder.start  the start time of the recorder, as ps prints it
# A throwaway home is RUN/home/NAME.
# A socket path has a limit of about 104 bytes on macOS, so the socket is
# in a new short folder below /tmp, not in the run folder.
#
# With KIT_TRACE set (kit trace), "start" also appends the line
# NAME<tab>HOME<tab>WORK<tab>AGENT_PID<tab>SOCKDIR to $KIT_TRACE/sessions.tsv
# (SOCKDIR is the folder of the socket), and it writes the states "start"
# and "stop" with kit_trace_state (lib.sh). A start again of the same
# session (resume) adds a second line. The fake model then gets --log-times
# and writes its log to $KIT_TRACE/model-NAME.log.
#
# The network check: with KIT_TRACE set, KIT_TRACE_CHECKS empty or holding
# "network", and the file $KIT_TRACE/proxy.port present, "start" adds the
# proxy variables (HTTPS_PROXY and the others) to the environment of the
# agent. The names go into the conditions file.
#
# The terminal check: with KIT_TRACE set, and KIT_TRACE_CHECKS empty or a
# comma list that has the word "terminal", the tmux backend records the
# output of the pane as asciicast v2 in $KIT_TRACE/terminal.cast. The pane
# command first waits for the file "gate" in the state folder (a loop of
# sleep 0.05, 10 seconds at most; KIT_TRACE_GATE_TURNS sets the number of
# turns, 200 by default). When the gate wait ends with no gate, the pane
# exits with 125 and does not run the agent, and "start" fails. When
# pipe-pane fails, "start" stops the server and fails. "start" runs
# "tmux pipe-pane" with trace-cast.py (option --ready FILE). It waits for
# the file "ready" in the state folder, which the recorder makes after it
# opened the cast and wrote the header. The wait has the same limit as the
# gate (KIT_TRACE_GATE_TURNS). When the file does not come, "start" stops
# the server and fails. Then it makes the gate. So the recording has the first
# byte of the agent, and the pid of the agent is still the pid of the
# pane. A start again of the same session continues the same cast file.
# When a write to the cast fails after the start, the recorder makes the
# file "recorder-failed" in the state folder and ends. The agent continues
# to run. "stop" then appends "terminal<tab>recorder-failed" to
# skipped.tsv in the trace folder, so that the trace shows that the
# terminal check failed. "start" writes the trace folder (KIT_TRACE) to the
# file "trace" in the state folder, and "stop" reads it from there, so a
# stop with no KIT_TRACE also writes the line. The recorder writes its pid
# to "recorder.pid" (option --pid-file), and "start" writes its start time
# to "recorder.start". "start" also records the pid in RUN/pids/ with the
# label "recorder NAME", so that "stop --all" and the checks of the run
# see it. "stop" waits for this pid (5 s at most) before it reads
# "recorder-failed", then sends TERM to it, and removes its pid file. The
# pipe-pane command holds each path in single quotes, with each single
# quote of a path escaped and each "#" doubled (tmux reads "#" as the start
# of a format). So a path can hold spaces, quotes and "#".
# The pty backend has no recording yet: "start" writes the line
# "terminal<tab>pty-not-yet" to $KIT_TRACE/skipped.tsv.
#
# The file check: with KIT_TRACE set, and KIT_TRACE_CHECKS empty or a comma
# list that has "files", the kit marks its own file work, so that
# trace-build.py does not show it as work of the agent. A mark is the file
# WORKROOT/.kit-trace-mark.NAME.begin or .end (WORKROOT is the work root,
# kit_work_root in lib.sh), which the kit makes and deletes at once. The
# file watcher sees it, because it watches the work root from the start.
# "start" marks "begin" before it makes the work folder and the home, and
# "end" just before the agent starts. So the settings files of the fake
# model, also on a start again, are between the two marks. "start" writes
# the file "trace-files" in the state folder. When that file exists,
# "stop" marks "begin" after the agent and its daemons are stopped, and
# "end" after it deleted the work folder and the home.
#
# The ebpf check: with KIT_TRACE set, and KIT_TRACE_CHECKS a comma list
# that has "ebpf" (an empty list does not select it), "stop" waits after
# the hang-up of the server (tmux kill-server, pty "client stop") until the
# agent pid ends, 3 s at most, then 0.5 s more. Then it appends
# MS<tab>NAME to $KIT_TRACE/hangup.tsv, and stops the pids as before. The
# build reads the processes that stay after that time as processes that
# the agent left.
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

# trace_terminal: true when the terminal check is on: KIT_TRACE is set, and
# KIT_TRACE_CHECKS is empty or a comma list that has "terminal".
trace_terminal() {
  [ -n "${KIT_TRACE:-}" ] || return 1
  case ",${KIT_TRACE_CHECKS:-}," in
    ,, | *,terminal,*) return 0 ;;
  esac
  return 1
}

# trace_network: true when the network check is on: KIT_TRACE is set, and
# KIT_TRACE_CHECKS is empty or a comma list that has "network".
trace_network() {
  [ -n "${KIT_TRACE:-}" ] || return 1
  case ",${KIT_TRACE_CHECKS:-}," in
    ,, | *,network,*) return 0 ;;
  esac
  return 1
}

# trace_files: true when the file check is on: KIT_TRACE is set, and
# KIT_TRACE_CHECKS is empty or a comma list that has "files".
trace_files() {
  [ -n "${KIT_TRACE:-}" ] || return 1
  case ",${KIT_TRACE_CHECKS:-}," in
    ,, | *,files,*) return 0 ;;
  esac
  return 1
}

# trace_ebpf: true when the ebpf check is on: KIT_TRACE is set, and
# KIT_TRACE_CHECKS is a comma list that has "ebpf". An empty list does not
# select ebpf.
trace_ebpf() {
  [ -n "${KIT_TRACE:-}" ] || return 1
  case ",${KIT_TRACE_CHECKS:-}," in
    *,ebpf,*) return 0 ;;
  esac
  return 1
}

# shq TEXT: TEXT in single quotes for sh, with each single quote escaped.
shq() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

# trace_mark WHAT: make and delete the mark file of the kit for this
# session in the work root (read the header). WHAT is begin or end. It
# does nothing when the work root does not exist. A "begin" sets a trap:
# when the command exits (also with kit_die, or on HUP, INT, QUIT or TERM)
# before its "end", the trap makes the "end" mark. So an unmatched
# "begin" holds only until the end of this kit command. A KILL of the
# command runs no trap.
mark_open=
trace_mark() {
  case $1 in
    begin)
      mark_open=1
      trap 'trace_mark_close' EXIT
      trap 'trace_mark_close; trap - HUP; kill -HUP $$' HUP
      trap 'trace_mark_close; trap - INT; kill -INT $$' INT
      trap 'trace_mark_close; trap - TERM; kill -TERM $$' TERM
      trap 'trace_mark_close; trap - QUIT; kill -QUIT $$' QUIT
      ;;
    end) mark_open= ;;
  esac
  _mr=$(kit_work_root "$run")
  [ -d "$_mr" ] || return 0
  _mf=$_mr/.kit-trace-mark.$name.$1
  : >"$_mf" 2>/dev/null && rm -f "$_mf"
  return 0
}

# trace_mark_close: make the "end" mark when a "begin" has no "end".
trace_mark_close() {
  [ -n "$mark_open" ] && trace_mark end
  return 0
}

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
  _log=$sdir/fake-model.log
  _times=
  if [ -n "${KIT_TRACE:-}" ]; then
    _log=$KIT_TRACE/model-$name.log
    _times=--log-times
  fi
  # shellcheck disable=SC2086
  python3 "$KIT_DIR/fake-model.py" --agent "$1" --home "$2" --env-file "$sdir/fake-model.env" \
    --log "$_log" $_times \
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
            # At the home folder, a path that is also a home path is a
            # home file, not a project file.
            if [ -e "$_d/$_p" ] && ! { [ "$_d" = "$h" ] && grep -qxF "home	$_p" "$sdir/settings.list"; }; then
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

# start_die CODE TEXT: a start that fails after the socket folder exists
# stops the pids of the session that still run (for example the fake
# model), deletes the socket folder, then ends like kit_die.
start_die() {
  # shellcheck disable=SC2046
  end_pids $(session_pids) $(recorder_pids) >/dev/null
  [ -n "${sockdir:-}" ] && rm -rf "$sockdir"
  kit_die "$@"
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
  # A trace folder that does not exist: fail before any change.
  if [ -n "${KIT_TRACE:-}" ] && [ ! -d "$KIT_TRACE" ]; then
    kit_die 2 "KIT_TRACE is not a folder: $KIT_TRACE"
  fi
  sdir=$run/sessions/$name
  if [ -d "$sdir" ]; then
    [ -f "$sdir/stopped" ] || kit_die 2 "the session exists: $name"
    rm -rf "$sdir"
  fi
  work=$(kit_work_root "$run")/$name
  trace_files && trace_mark begin
  # --keep: the resume step starts a session again. The new start needs the
  # work folder and the home of the old session.
  [ -n "$keep" ] || rm -rf "$work"
  mkdir -p "$sdir" "$work" || kit_die 1 "cannot make $sdir"
  chmod 700 "$sdir"
  rm -f "$sdir/trace-files"
  trace_files && : >"$sdir/trace-files"
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
  # The network check: "kit trace" starts trace-proxy.py and the proxy
  # writes its port to $KIT_TRACE/proxy.port. "start" only reads that file.
  if trace_network && [ -s "$KIT_TRACE/proxy.port" ]; then
    _pp=$(cat "$KIT_TRACE/proxy.port")
    case $_pp in
      '' | *[!0-9]*) ;;
      *)
        for v in HTTPS_PROXY HTTP_PROXY ALL_PROXY https_proxy http_proxy all_proxy; do
          set -- "$@" "$v=http://127.0.0.1:$_pp"
        done
        set -- "$@" NO_PROXY=127.0.0.1,localhost no_proxy=127.0.0.1,localhost
        ;;
    esac
  fi
  write_conditions "$@"
  trace_term=
  trace_terminal && trace_term=1
  # The kit writes no more in the work folder or the home before the agent
  # starts.
  [ -f "$sdir/trace-files" ] && trace_mark end
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
      # With the terminal check, the pane waits for the gate file first.
      rm -f "$sdir/gate" "$sdir/ready" "$sdir/recorder-failed" \
        "$sdir/recorder.pid" "$sdir/recorder.start" "$sdir/trace"
      # "stop" reads the trace folder from this file, not from the
      # KIT_TRACE of its caller.
      [ -n "$trace_term" ] && printf '%s\n' "$KIT_TRACE" >"$sdir/trace"
      gate_wait=
      gate_arg=
      gate_turns=
      [ -n "$trace_term" ] && gate_arg=$sdir/gate && gate_turns=${KIT_TRACE_GATE_TURNS:-200} && gate_wait='i=0; while [ ! -e "$1" ] && [ "$i" -lt "$2" ]; do sleep 0.05; i=$((i+1)); done; [ -e "$1" ] || exit 125; '
      env -i "$@" \
        tmux -S "$sock" -f "$sdir/tmux.conf" new-session -d -s kit \
        -x "$COLS" -y "$ROWS" -c "$work" \
        sh -c "${gate_wait}"'eval "exec $0"' "$cmd" ${gate_arg:+"$gate_arg"} ${gate_turns:+"$gate_turns"} </dev/null >"$sdir/server.log" 2>&1 \
        3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&- ||
        start_die 1 "tmux did not start: $(cat "$sdir/server.log")"
      server=$(tm display -p -t kit '#{pid}' 2>/dev/null)
      a=$(tm display -p -t kit '#{pane_pid}' 2>/dev/null)
      [ -n "$server" ] && add_pid "$server" "session $name server"
      if [ -n "$trace_term" ]; then
        # No recorder: stop the server, so that the pane never runs the
        # agent unrecorded and no process stays.
        _pc="exec python3 -I $(shq "$KIT_DIR/trace-cast.py") --t0 $(shq "$KIT_TRACE/t0") --out $(shq "$KIT_TRACE/terminal.cast") --ready $(shq "$sdir/ready") --failed $(shq "$sdir/recorder-failed") --pid-file $(shq "$sdir/recorder.pid") --width $COLS --height $ROWS"
        # tmux expands formats in the command: "##" gives one "#".
        _pc=$(printf '%s' "$_pc" | sed 's/#/##/g')
        if ! tm pipe-pane -t kit -O "$_pc"; then
          _why="pipe-pane failed: the terminal is not recorded"
          [ "$(tm display -p -t kit '#{pane_dead_status}' 2>/dev/null)" = 125 ] &&
            _why="the gate wait ended before the recorder started: the agent did not run"
          tm kill-server >/dev/null 2>&1
          [ -n "$server" ] && rm -f "$run/pids/$server"
          start_die 1 "$_why"
        fi
        # The recorder makes "ready" after it opened the cast.
        _n=0
        while [ ! -e "$sdir/ready" ] && [ "$_n" -lt "${KIT_TRACE_GATE_TURNS:-200}" ]; do
          sleep 0.05
          _n=$((_n + 1))
        done
        if [ ! -e "$sdir/ready" ]; then
          # The kit makes no gate now, so the agent does not run. The
          # reason comes from the recorder, not from the pane: the pane can
          # still be in its gate wait at this time. The recorder writes its
          # pid file first, before it opens the cast.
          if [ -s "$sdir/recorder.pid" ]; then
            _why="the recorder did not start: the terminal is not recorded"
          else
            _why="the gate wait ended before the recorder started: the agent did not run"
          fi
          tm kill-server >/dev/null 2>&1
          [ -n "$server" ] && rm -f "$run/pids/$server"
          start_die 1 "$_why"
        fi
        # The start time of the recorder, so that "stop" does not wait for
        # a new process that got the same pid.
        _rp=$(cat "$sdir/recorder.pid" 2>/dev/null)
        case $_rp in
          '' | *[!0-9]*) ;;
          *)
            kit_pid_start "$_rp" >"$sdir/recorder.start"
            kit_add_pid "$run" "$_rp" "recorder $name"
            ;;
        esac
        : >"$sdir/gate"
        # A pane that ended with 125 gave up at the gate (10 s at most).
        if [ "$(tm display -p -t kit '#{pane_dead_status}' 2>/dev/null)" = 125 ]; then
          tm kill-server >/dev/null 2>&1
          [ -n "$server" ] && rm -f "$run/pids/$server"
          start_die 1 "the gate wait ended before the recorder started: the agent did not run"
        fi
      fi
      ;;
    pty)
      sock=$sockdir/pty.sock
      echo "$sock" >"$sdir/socket"
      start_f=$(mktemp "$sdir/pids.XXXXXX") || start_die 1 "mktemp failed"
      pty_serve "$@" </dev/null >"$sdir/server.log" 2>&1 \
        3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&- || {
        rm -f "$start_f"
        start_die 1 "ptydrive did not start: $(cat "$sdir/server.log")"
      }
      client pids >"$start_f" 2>/dev/null
      server=$(awk '$1 == "driver" { print $2 }' "$start_f")
      a=$(awk '$1 == "agent" { print $2 }' "$start_f")
      rm -f "$start_f"
      [ -n "$server" ] && add_pid "$server" "session $name driver"
      [ -n "$trace_term" ] && printf 'terminal\tpty-not-yet\n' >>"$KIT_TRACE/skipped.tsv"
      ;;
  esac
  [ -n "${a:-}" ] || kit_die 1 "no agent pid"
  echo "$a" >"$sdir/pid"
  add_pid "$a" "session $name agent"
  if [ -n "${KIT_TRACE:-}" ]; then
    printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$h" "$work" "$a" "$sockdir" >>"$KIT_TRACE/sessions.tsv"
    kit_trace_state start
  fi
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

# recorder_pids: the pids of RUN/pids/ with the label "recorder NAME".
recorder_pids() {
  for f in "$run"/pids/*; do
    [ -f "$f" ] || continue
    [ "$(label "$f")" = "recorder $name" ] && echo "${f##*/}"
  done
  return 0
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
#
# The daemon puts its control socket in a folder codex-daemon-UID in the
# temp folder, and HOME/.codex/app-server-control/app-server-control.sock
# is a link to it (fact 088). The daemon does not delete the socket and its
# .lock file when it stops, so this deletes them.
end_home_daemons() {
  hd=${run:?}/home/$name/
  [ -d "$hd" ] || return 0
  hp=$(ps -A -o pid= -o args= 2>/dev/null | awk -v h="$hd" 'index($0, h) { print $1 }')
  for p in $hp; do
    echo "stop: $p daemon"
    kill "$p" 2>/dev/null
  done
  if [ -n "$hp" ]; then
    sleep 1
    for p in $hp; do kill -9 "$p" 2>/dev/null; done
  fi
  link=${hd}.codex/app-server-control/app-server-control.sock
  if [ -L "$link" ]; then
    # Not "sock": stop_session deletes the folder of $sock after this.
    csock=$(readlink "$link")
    case ${csock%/*} in
      */codex-daemon-*) rm -f "$csock" "$csock.lock" ;;
    esac
  fi
  return 0
}

# remove_folders: delete the work folder and the home of the session in sdir.
# With the file check, the marks "begin" and "end" hold the deletes.
remove_folders() {
  [ -f "$sdir/trace-files" ] && trace_mark begin
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
  # The mark comes before the tidy, which can delete the work root.
  [ -f "$sdir/trace-files" ] && trace_mark end
  [ -n "$work" ] && kit_work_tidy "$(dirname "$work")"
  return 0
}

# recorder_runs PID: true when PID runs and has the start time in
# $sdir/recorder.start. A pid that the system gave again to a new process
# is not the recorder.
recorder_runs() {
  kit_pid_runs "$1" || return 1
  _want=$(cat "$sdir/recorder.start" 2>/dev/null)
  [ -n "$_want" ] && [ "$_want" = "$(kit_pid_start "$1")" ]
}

# end_recorder: wait for the recorder (trace-cast.py) of the session to
# end, 5 s at most. Then send TERM to its pid and wait 1 s more, then send
# KILL. The pid is in $sdir/recorder.pid.
end_recorder() {
  _rp=$(cat "$sdir/recorder.pid" 2>/dev/null)
  case $_rp in '' | *[!0-9]*) return 0 ;; esac
  _n=0
  while recorder_runs "$_rp" && [ "$_n" -lt 100 ]; do
    sleep 0.05
    _n=$((_n + 1))
  done
  if ! recorder_runs "$_rp"; then
    [ "$(label "$run/pids/$_rp")" = "recorder $name" ] && rm -f "$run/pids/$_rp"
    return 0
  fi
  echo "stop: $_rp recorder"
  kill "$_rp" 2>/dev/null
  _n=0
  while recorder_runs "$_rp" && [ "$_n" -lt 20 ]; do
    sleep 0.05
    _n=$((_n + 1))
  done
  recorder_runs "$_rp" && kill -9 "$_rp" 2>/dev/null
  [ "$(label "$run/pids/$_rp")" = "recorder $name" ] && rm -f "$run/pids/$_rp"
  return 0
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
  kit_trace_state stop
  track
  # The server hangs up the agent first, so that it can end in its own way.
  case $backend in
    tmux) [ -n "$sock" ] && tm kill-server >/dev/null 2>&1 ;;
    pty) [ -n "$sock" ] && client stop >/dev/null 2>&1 ;;
  esac
  # The ebpf check: the processes that stay after the hang-up are the
  # processes that the agent leaves. Wait for the agent pid to end (3 s at
  # most), then 0.5 s more, and write the time to hangup.tsv. Then the
  # stop of the pids comes.
  if trace_ebpf; then
    _ap=$(cat "$sdir/pid" 2>/dev/null)
    case $_ap in '' | *[!0-9]*) _ap= ;; esac
    _n=0
    while [ -n "$_ap" ] && kit_pid_live "$_ap" && [ "$_n" -lt 30 ]; do
      sleep 0.1
      _n=$((_n + 1))
    done
    sleep 0.5
    printf '%s\t%s\n' "$(kit_ms)" "$name" >>"$KIT_TRACE/hangup.tsv"
  fi
  # shellcheck disable=SC2046
  end_pids $(session_pids)
  # The server is stopped. The recorder gets the end of its input and
  # does its last flush. Its label in RUN/pids/ is not "session NAME", so
  # end_pids does not stop it before the flush. Wait for its pid here.
  end_recorder
  if [ -f "$sdir/trace" ] && [ -e "$sdir/recorder-failed" ]; then
    printf 'terminal\trecorder-failed\n' >>"$(cat "$sdir/trace")/skipped.tsv"
  fi
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
    # A "kit trace" that got KILL left RUN/.trace and the folder of its
    # file watcher. Its recorders were in RUN/pids/, so they are stopped.
    kit_trace_leftover "$run" ||
      echo "kit: a trace runs in this run, so $run/.trace stays" >&2
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
