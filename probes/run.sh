#!/bin/sh
# The probe kit for Linux and macOS.
#
# Usage:
#   sh probes/run.sh            run every probe whose agent is installed
#   sh probes/run.sh --all      run every probe
#   sh probes/run.sh --guided STEP [AGENT] [OPTION ...]
#       STEP: permission | new-chat | resume | interrupt | front-tab
#       AGENT: claude | codex | agy | cursor-agent | opencode | copilot | gemini
#       (default: all). "cursor-agent" is the Cursor CLI. Its command is
#       "cursor-agent" or "agent". The kit also accepts "agent" and
#       "cursor" for it.
#   Options of a guided step:
#       --wait N         read no key: start the watch now, and watch for
#                        N seconds (1 to 600). The action occurs in the
#                        watch, also from a different process.
#       --pids FILE      count only the pids in FILE and their children.
#                        FILE holds one pid on each line, or it is a
#                        folder of files named by pid (a run's pids/),
#                        or one such file. A pids/ file must hold the
#                        start time of the process. A listed tmux or
#                        psmux process counts only its children.
#       --files-of-pids  show only the files that the counted processes
#                        hold open, and the files under a --scope folder.
#                        It needs --pids. It leaves out the agy summaries.
#                        It reads no other file of the agent folders.
#       --scope DIR      a folder that exists, for --files-of-pids. Give
#                        it again for more folders.
#       --scope-new DIR  as --scope, for a folder that can start in the
#                        watch. DIR is an absolute path.
#       --stop-file FILE end the watch early: when FILE exists, the kit
#                        takes the "after" snapshot within 2 s.
#       --out FILE       write the file to FILE.
#   Without --wait, the kit waits for Enter, and then watches for
#   AGENT_SIGNALS_WATCH seconds (default 30). When stdin is not a
#   terminal, or the kit is not in the foreground, it does not wait.
#   A shell that runs command text (sh -c TEXT) does not count as an
#   agent, also when the text holds the agent name.
#
# On macOS, AGENT_SIGNALS_TERMINALS=yes or no answers the question about
# the terminal probe. With no value and no terminal, the answer is no.
#
# The kit writes one file in the current folder (or the --out file):
# agent-signals-probe-<os>-<time>.txt. The scrub (tools/scrub.sh) has
# already changed home folders, project paths, the account name, the host
# name and IDs in it. Read the file before you send it.
#
# The kit only reads, except the "front-tab" step, which asks first.
set -u
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
# shellcheck source=probes/lib.sh
. "$here/lib.sh"

stamp=$(date -u +%Y%m%dT%H%M%SZ)
out=$PWD/agent-signals-probe-$PROBE_OS-$stamp.txt
raw=$(mktemp)
# The EXIT trap deletes the temporary files. A signal runs it too, so a
# step that a caller stops in the background leaves no file.
trap 'rm -f "$raw" "$raw".* "$out.part"' EXIT
trap 'exit 143' TERM
trap 'exit 130' INT
trap 'exit 129' HUP

agents="claude codex agy cursor-agent opencode copilot gemini"
command_of() {
  case $1 in
    cursor-agent) command -v cursor-agent >/dev/null 2>&1 && echo cursor-agent || echo agent ;;
    *) echo "$1" ;;
  esac
}

# The folders that hold the session state of each agent.
state_dirs() {
  case $1 in
    claude) echo "$HOME/.claude/sessions $HOME/.claude/projects" ;;
    codex) echo "${CODEX_HOME:-$HOME/.codex}/sessions ${CODEX_HOME:-$HOME/.codex}/thread-writer-locks" ;;
    agy) echo "$HOME/.gemini/antigravity-cli" ;;
    cursor-agent) echo "$HOME/.cursor/chats $HOME/.cursor/projects" ;;
    opencode) echo "${XDG_DATA_HOME:-$HOME/.local/share}/opencode" ;;
    copilot) echo "$HOME/.copilot/session-state" ;;
    gemini) echo "$HOME/.gemini/tmp $HOME/.gemini/history" ;;
  esac
}

# The process pattern of each agent: the first "pids '...'" call of its
# probe. One copy of each pattern, so that the guided step and the probe
# find the same processes.
pattern_of() {
  sed -n "s/.*pids '\([^']*\)'.*/\1/p" "$here/$1/unix.sh" | head -n 1
}

# can_ask: true when the kit can read a key: stdin is a terminal and the
# kit is in the foreground process group of that terminal. A background
# job or a pane that a different program drives gives false, so a read
# does not wait or stop the kit with SIGTTIN.
can_ask() {
  [ -t 0 ] || return 1
  _tp=$(ps -o tpgid= -p $$ 2>/dev/null | tr -d ' ')
  _pg=$(ps -o pgid= -p $$ 2>/dev/null | tr -d ' ')
  [ -n "$_tp" ] && [ "$_tp" = "$_pg" ]
}

# finish: scrub the raw file into $out. The scrub writes $out.part first,
# so $out never holds a part of a file. When the scrub fails, the kit
# writes no file and exits 1.
finish() {
  if ! sh "$root/tools/scrub.sh" "$raw" >"$out.part" 2>"$raw.scrub"; then
    cat "$raw.scrub" >&2
    echo "kit: the scrub failed, so the kit wrote no file"
    exit 1
  fi
  mv "$out.part" "$out"
  cat "$raw.scrub" >&2
  echo "kit: wrote $out"
  echo "kit: read the file before you send it."
}

run_all() {
  {
    echo "agent-signals probe kit, $stamp"
    for a in $agents; do
      if [ "${1:-}" = --all ] || command -v "$(command_of "$a")" >/dev/null 2>&1; then
        echo
        echo "################ $a"
        sh "$here/$a/unix.sh" 2>&1
      fi
    done
  } >"$raw"
  if [ "$PROBE_OS" = macos ]; then
    # Caution: the terminal probe can open a macOS dialog that asks for
    # Automation access to Terminal or iTerm2. You can say no.
    # AGENT_SIGNALS_TERMINALS gives the answer before the question.
    ans=${AGENT_SIGNALS_TERMINALS:-}
    if [ -z "$ans" ] && can_ask; then
      printf 'kit: run the terminal probe? It can open an Automation dialog. [y/N] '
      read -r ans
    elif [ -z "$ans" ]; then
      ans=no-tty
    fi
    case $ans in
      y | Y | yes) { echo; echo "################ terminals"; sh "$here/terminals/macos.sh" 2>&1; } >>"$raw" ;;
      no-tty) echo "################ terminals: skipped, no terminal to ask" >>"$raw" ;;
      *) echo "################ terminals: skipped by the operator" >>"$raw" ;;
    esac
  fi
  finish
}

# The options of a guided step. guided() sets them.
# pids_from: the --pids file or folder. Empty: count each agent process.
# scoped: "yes" with --files-of-pids. scope: the --scope folders, one on
# each line.
pids_from=
scoped=
scope=
# stop_file: the --stop-file file. Empty: the watch takes its full time.
stop_file=

# start_of PID: the start time of PID, in the form that kit_pid_start of
# probes/agent/lib.sh writes in a pids/ file.
start_of() {
  LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null | tr -s ' ' | sed 's/^ //; s/ $//'
}

# ours FILE PID: true when PID runs and has the start time in field 2 of
# the first line of FILE (the form "LABEL<tab>START" of a pids/ file). A
# pid that the system gave again to a new process does not count.
ours() {
  kill -0 "$2" 2>/dev/null || return 1
  _want=$(tr -d '\r' <"$1" | awk -F '\t' 'NR == 1 { print $2 }')
  [ -n "$_want" ] && [ "$_want" = "$(start_of "$2")" ]
}

# listed: the pids of the --pids file or folder, one on each line.
# - A folder holds one file for each pid, named by the pid (the pids/
#   folder of a kit run). Each file holds "LABEL<tab>START".
# - A file named by a pid whose first line holds a tab is one such file.
# - Each other file holds one pid on each line. The kit accepts CRLF line
#   ends and a last line with no line end.
listed() {
  if [ -d "$pids_from" ]; then
    for _f in "$pids_from"/*; do
      _p=${_f##*/}
      case $_p in '' | *[!0-9]*) continue ;; esac
      ours "$_f" "$_p" && echo "$_p"
    done
    return 0
  fi
  _p=${pids_from##*/}
  case $_p in
    '' | *[!0-9]*) ;;
    *)
      if head -n 1 "$pids_from" | grep -q '	'; then
        ours "$pids_from" "$_p" && echo "$_p"
        return 0
      fi
      ;;
  esac
  tr -d '\r' <"$pids_from" | awk '{ gsub(/^[ \t]+|[ \t]+$/, "") } /^[0-9]+$/'
}

# watched: the pids of the --pids file or folder, and their children. A
# listed tmux or psmux process does not count itself, only its children.
watched() {
  listed | while read -r _w; do
    if is_mux "$_w"; then
      children "$_w" | sed 1d
    else
      children "$_w"
    fi
  done
}

# agent_pids AGENT: the pids of the agent processes that the step counts:
# the processes that match the pattern of AGENT, are not a shell that runs
# command text, and, with --pids, are in the watched set.
agent_pids() {
  _set=
  [ -n "$pids_from" ] && _set=" $(watched | tr '\n' ' ') "
  pids "$(pattern_of "$1")" | while read -r _x; do
    if [ -n "$pids_from" ]; then
      case $_set in *" $_x "*) ;; *) continue ;; esac
    fi
    shell_text "$_x" && continue
    echo "$_x"
  done
}

# phys DIR: the physical path of the absolute path DIR. Lower parts that do
# not exist stay as they are.
phys() {
  _d=$1
  _t=
  until [ -d "$_d" ]; do
    _t=/${_d##*/}$_t
    _d=${_d%/*}
    [ -n "$_d" ] || _d=/
  done
  _b=$(CDPATH='' cd -P -- "$_d" && pwd -P) || return 1
  printf '%s%s\n' "${_b%/}" "$_t"
}

# add_scope PATH: add a physical path to the --scope folders, one time.
add_scope() {
  case "
$scope
" in
    *"
$1
"*) ;;
    *) scope="$scope
$1" ;;
  esac
}

# stopped: true when the --stop-file file exists.
stopped() { [ -n "$stop_file" ] && [ -e "$stop_file" ]; }

# roots AGENT: the folders that the step reads for AGENT, one on each line:
# the state folders of the agent and the --scope folders. With
# --files-of-pids, only the --scope folders: the step must not walk all of
# a large folder such as ~/.claude/projects.
roots() {
  if [ -z "$scoped" ]; then
    for _d in $(state_dirs "$1"); do echo "$_d"; done
  fi
  printf '%s\n' "$scope" | sed '/^$/d'
}

# in_scope FILE: true when the step can show FILE. With --files-of-pids,
# FILE must be under a --scope folder, or open in a counted process
# before or after the step. Else each file can show.
in_scope() {
  [ -n "$scoped" ] || return 0
  cut -d' ' -f3- "$raw.before.open" "$raw.after.open" 2>/dev/null | grep -Fqx -- "$1" && return 0
  printf '%s\n' "$scope" | {
    while read -r _d; do
      [ -n "$_d" ] || continue
      case $1 in "$_d"/*) exit 0 ;; esac
    done
    exit 1
  }
}

# snapshot NAME AGENTS: the open state files of each agent process, and the
# line count of the JSONL files. Without --files-of-pids, the line counts
# include files out of the scope, so that a file that opens during the step
# has a count before. With --files-of-pids, such a file has no count before,
# and all its lines count as new.
snapshot() {
  name=$1
  shift
  for a in "$@"; do
    for x in $(agent_pids "$a"); do
      for k in $(children "$x"); do
        open_files "$k" '\.claude|\.codex|\.gemini|\.cursor|opencode|\.copilot' | sed "s#^#$a $x #"
      done
    done
  done | sort -u >"$raw.$name.open"
  {
    for a in "$@"; do
      roots "$a" | while read -r d; do
        [ -d "$d" ] && find "$d" -name '*.jsonl' -type f 2>/dev/null
      done
    done
    cut -d' ' -f3- "$raw.$name.open" | grep '\.jsonl$'
  } | sort -u | while read -r f; do
    [ -f "$f" ] && echo "$(wc -l <"$f" | tr -d ' ') $f"
  done >"$raw.$name.lines"
}

# agy_status: status, not_fully_idle and step_count of the three newest
# rows of the agy summaries database (fact 45). It reads a copy, and no
# conversation text. It needs python3.
agy_status() {
  _db=$HOME/.gemini/antigravity-cli/conversation_summaries.db
  [ -f "$_db" ] && command -v python3 >/dev/null 2>&1 || return 0
  _t=$(mktemp -d) || return 0
  for _x in "" -wal -shm; do [ -f "$_db$_x" ] && cp "$_db$_x" "$_t/s.db$_x"; done
  python3 -I - "$_t/s.db" <<'PY' 2>/dev/null
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
q = ("select status, not_fully_idle, step_count from conversation_summaries"
     " order by last_modified_time desc limit 3")
print(" | ".join("%s %s %s" % (s or "-", n, k) for s, n, k in c.execute(q)))
PY
  rm -f "$_t/s.db" "$_t/s.db-wal" "$_t/s.db-shm"
  rmdir "$_t"
}

# claude_status: the status field of each Claude pid file (fact 23). With
# --files-of-pids, only the files named by a watched pid.
claude_status() {
  _cs=
  [ -n "$scoped" ] && _cs=" $(watched | tr '\n' ' ') "
  for f in "$HOME"/.claude/sessions/*.json; do
    [ -f "$f" ] || continue
    if [ -n "$scoped" ]; then
      case $_cs in *" $(basename "$f" .json) "*) ;; *) continue ;; esac
    fi
    s=$(sed -n 's/.*"status":"\([a-z]*\)".*/\1/p' "$f")
    echo "$(basename "$f" .json) ${s:-none}"
  done
}

# seconds NAME VALUE: exit 2 when VALUE is not a number from 1 to 600. A
# leading 0 is refused, because the shell can read 09 as a bad octal.
seconds() {
  case $2 in
    '' | 0* | *[!0-9]*) echo "kit: $1 takes a number from 1 to 600: $2"; exit 2 ;;
  esac
  if [ "$2" -lt 1 ] || [ "$2" -gt 600 ]; then
    echo "kit: $1 takes a number from 1 to 600: $2"
    exit 2
  fi
}

guided() {
  step=${1:-}
  [ "$#" -gt 0 ] && shift
  pick=
  wait_s=
  while [ "$#" -gt 0 ]; do
    case $1 in
      --wait)
        [ "$#" -ge 2 ] || { echo "kit: --wait needs a number of seconds"; exit 2; }
        seconds --wait "$2"
        wait_s=$2
        shift 2
        ;;
      --pids)
        [ "$#" -ge 2 ] || { echo "kit: --pids needs a file or a folder"; exit 2; }
        [ -r "$2" ] || { echo "kit: --pids: cannot read $2"; exit 2; }
        pids_from=$2
        shift 2
        ;;
      --files-of-pids) scoped=yes; shift ;;
      --scope)
        [ "$#" -ge 2 ] || { echo "kit: --scope needs a folder"; exit 2; }
        [ -d "$2" ] || { echo "kit: --scope: no folder $2"; exit 2; }
        # The physical path: lsof gives physical paths, for example
        # /private/var on macOS.
        _s=$(CDPATH='' cd -P -- "$2" && pwd -P) || { echo "kit: --scope: cannot read $2"; exit 2; }
        add_scope "$_s"
        shift 2
        ;;
      --scope-new)
        [ "$#" -ge 2 ] || { echo "kit: --scope-new needs a folder"; exit 2; }
        case $2 in /*) ;; *) echo "kit: --scope-new needs an absolute path: $2"; exit 2 ;; esac
        _s=$(phys "$2") || { echo "kit: --scope-new: cannot read $2"; exit 2; }
        add_scope "$_s"
        shift 2
        ;;
      --stop-file)
        [ "$#" -ge 2 ] && [ -n "$2" ] || { echo "kit: --stop-file needs a file"; exit 2; }
        stop_file=$2
        shift 2
        ;;
      --out)
        [ "$#" -ge 2 ] && [ -n "$2" ] || { echo "kit: --out needs a file"; exit 2; }
        _o=$(dirname -- "$2")
        [ -d "$_o" ] && [ -w "$_o" ] || { echo "kit: --out: cannot write in $_o"; exit 2; }
        out=$2
        shift 2
        ;;
      -*) echo "kit: unknown option: $1"; exit 2 ;;
      *)
        [ -z "$pick" ] || { echo "kit: give one agent, or none for all"; exit 2; }
        pick=$1
        shift
        ;;
    esac
  done
  if [ -n "$scoped" ] && [ -z "$pids_from" ]; then
    echo "kit: --files-of-pids needs --pids"
    exit 2
  fi
  watch_s=${AGENT_SIGNALS_WATCH:-30}
  seconds AGENT_SIGNALS_WATCH "$watch_s"
  [ -n "$wait_s" ] && watch_s=$wait_s
  which=
  for a in ${pick:-$agents}; do
    case $a in
      agent | cursor) a=cursor-agent ;;
    esac
    case " $agents " in
      *" $a "*) which="$which $a" ;;
      *) echo "kit: unknown agent: $a. Use one of: $agents"; exit 2 ;;
    esac
  done
  which=${which# }
  case $step in
    permission) action="In one agent session, ask for a file write, for example: Create a file named note.txt that holds the word hello. Wait until the permission dialog shows. Do not answer it yet." ;;
    new-chat) action="In one session, start a new chat: /new-chat in Cursor, /clear in Claude, /new in Codex." ;;
    resume) action="Exit one session. Then start it again with its resume command: cursor-agent --resume, claude --continue, codex resume --last, agy --continue." ;;
    interrupt) action="In one session, send a prompt that takes some time, then push Esc while the agent works. Then push Ctrl+C one time." ;;
    front-tab)
      [ -z "$wait_s$pids_from$scoped$scope$stop_file" ] || { echo "kit: front-tab asks questions, so it takes no other option"; exit 2; }
      front_tab
      return
      ;;
    *) echo "kit: unknown step: $step"; exit 2 ;;
  esac
  # A step measures only the sessions that run. Without one, the file
  # would be empty, so the kit stops.
  running=
  for a in $which; do
    n=$(agent_pids "$a" | wc -l | tr -d ' ')
    [ "$n" -gt 0 ] && running="$running $a=$n"
  done
  if [ -z "$running" ]; then
    echo "kit: no session of $which runs. Start a session, then run the step again."
    exit 2
  fi
  {
    echo "agent-signals guided step: $step, $stamp"
    echo "agents: $which"
    echo "watch: $watch_s s"
    echo "processes:$running"
    for a in $which; do
      for x in $(agent_pids "$a"); do echo "$a $(ps_line "$x")"; done
    done
  } >"$raw"
  # shellcheck disable=SC2086
  snapshot before $which
  marker=$raw.marker
  : >"$marker"
  # With --files-of-pids, the kit does not read the agy summaries: the
  # database holds the rows of all conversations, and a row does not give
  # the pid of its session.
  agy_sample() {
    if [ -n "$scoped" ]; then : >"$1"; else agy_status >"$1"; fi
  }
  claude_status >"$raw.status.0"
  agy_sample "$raw.agy.0"
  echo
  if [ -n "$wait_s" ]; then
    # With --wait, the watch starts now. A caller can do the action in
    # the watch, also from a different process. The "kit: watch starts"
    # line tells a background caller that the before snapshot is done.
    echo "kit: do this now. The kit watches the agent folders for $watch_s s:"
    echo "  $action"
    echo "kit: watch starts, $watch_s s"
  else
    echo "kit: do this now, then come back and push Enter:"
    echo "  $action"
    if can_ask; then
      printf 'kit: push Enter when it is done. '
      read -r _
    else
      echo "kit: no terminal to push Enter, so the watch starts now."
    fi
    echo "kit: watching the agent folders for $watch_s s. Do not touch the session."
  fi
  # A sample every 2 s.
  i=0
  t=0
  while [ $((t + 2)) -le "$watch_s" ] && ! stopped; do
    sleep 2
    t=$((t + 2))
    i=$((i + 1))
    claude_status >"$raw.status.$i"
    agy_sample "$raw.agy.$i"
  done
  [ "$t" -lt "$watch_s" ] && ! stopped && sleep $((watch_s - t))
  # shellcheck disable=SC2086
  snapshot after $which
  {
    stopped && echo "watch: the stop file ended the watch at about $t s"
    echo "processes after the step:"
    for a in $which; do
      for x in $(agent_pids "$a"); do echo "$a $(ps_line "$x")"; done
    done
    echo
    echo "### 1. Files that changed during the step (size, path)"
    for a in $which; do
      {
        roots "$a"
        [ -n "$scoped" ] && cut -d' ' -f3- "$raw.before.open" "$raw.after.open"
      } | while read -r d; do
        [ -e "$d" ] && find "$d" -type f -newer "$marker" 2>/dev/null
      done | sort -u | while read -r f; do
        in_scope "$f" && echo "$a $(wc -c <"$f" | tr -d ' ') $f"
      done
    done
    echo
    echo "### 2. Open state files: before (<) and after (>)"
    diff "$raw.before.open" "$raw.after.open" || true
    echo
    echo "### 3. New records in JSONL files (types only)"
    while read -r n f; do
      in_scope "$f" || continue
      o=$(awk -v f="$f" '$2 == f {print $1}' "$raw.before.lines")
      [ "$n" = "${o:-0}" ] && continue
      echo "== $f (lines ${o:-0} -> $n)"
      tail -n "+$((${o:-0} + 1))" "$f" | head -n 40 >"$raw.new"
      jsonl_types "$raw.new" 40
    done <"$raw.after.lines"
    case " $which " in
      *" claude "*)
        echo
        echo "### 4. Status of the Claude pid files, every 2 s (fact 23)"
        [ -n "$scoped" ] && echo "only the pid files of the watched pids (--files-of-pids)"
        j=0
        while [ "$j" -le "$i" ]; do
          echo "t=$((j * 2))s: $(tr '\n' ' ' <"$raw.status.$j")"
          j=$((j + 1))
        done
        ;;
    esac
    case " $which " in
      *" agy "*)
        echo
        echo "### 5. agy summaries: status, not_fully_idle, step_count of the newest rows, every 2 s (fact 45)"
        if [ -n "$scoped" ]; then
          echo "left out: --files-of-pids is set, and the rows do not give the pid of their session"
        else
          j=0
          while [ "$j" -le "$i" ]; do
            echo "t=$((j * 2))s: $(cat "$raw.agy.$j")"
            j=$((j + 1))
          done
        fi
        ;;
    esac
  } >>"$raw"
  finish
}

front_tab() {
  [ "$PROBE_OS" = macos ] || { echo "kit: front-tab is for macOS"; exit 2; }
  can_ask || { echo "kit: front-tab asks questions, so it needs a terminal"; exit 2; }
  echo "kit: this step brings one Terminal or iTerm2 tab to the front by its tty."
  echo "kit: it changes the selected tab. Nothing else changes."
  # Caution: the osascript call can open a macOS dialog that asks for
  # Automation access.
  printf 'kit: the tty of the tab, for example ttys012: '
  read -r tty
  printf 'kit: bring the tab with /dev/%s to the front? [y/N] ' "$tty"
  read -r ans
  case $ans in y | Y) ;; *) echo "kit: skipped"; exit 0 ;; esac
  {
    echo "agent-signals guided step: front-tab, $stamp"
    echo "### 1. Terminal"
    osascript -e "tell application \"Terminal\"
      repeat with w in windows
        repeat with t in tabs of w
          if tty of t is \"/dev/$tty\" then
            set selected of t to true
            set frontmost of w to true
            activate
            return \"selected\"
          end if
        end repeat
      end repeat
      return \"no tab with that tty\"
    end tell" 2>&1
    echo "### 2. iTerm2"
    if pgrep -x iTerm2 >/dev/null 2>&1; then
      osascript -e "tell application \"iTerm2\"
        repeat with w in windows
          repeat with t in tabs of w
            repeat with s in sessions of t
              if tty of s is \"/dev/$tty\" then
                select t
                select w
                activate
                return \"selected\"
              end if
            end repeat
          end repeat
        end repeat
        return \"no session with that tty\"
      end tell" 2>&1
    else
      echo "iTerm2: not running"
    fi
  } >"$raw"
  printf 'kit: did the right tab come to the front? [y/n] '
  read -r ok
  echo "operator: right tab in front: $ok" >>"$raw"
  finish
}

case ${1:-} in
  --guided) shift; guided "$@" ;;
  --all | "") run_all "${1:-}" ;;
  *) sed -n '2,42p' "$0"; exit 2 ;;
esac
