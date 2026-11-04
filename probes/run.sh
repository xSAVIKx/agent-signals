#!/bin/sh
# The probe kit for Linux and macOS.
#
# Usage:
#   sh probes/run.sh            run every probe whose agent is installed
#   sh probes/run.sh --all      run every probe
#   sh probes/run.sh --guided STEP [AGENT] [OPTION ...]
#       STEP: permission | new-chat | resume | interrupt | front-tab
#       AGENT: claude | codex | agy | cursor | opencode | copilot | gemini
#       (default: all). "cursor" is the Cursor CLI. Its command is
#       "agent" or "cursor-agent", and the kit accepts all three names.
#   Options of a guided step:
#       --wait N         read no key: start the watch now, and watch for
#                        N seconds (1 to 600). The action occurs in the
#                        watch, also from a different process.
#       --pids FILE      count only the pids in FILE and their children.
#                        FILE holds one pid on each line, or it is a
#                        folder of files named by pid (a run's pids/).
#       --files-of-pids  show only the files that the counted processes
#                        hold open, and the files under a --scope folder.
#       --scope DIR      a folder for --files-of-pids. Give it again for
#                        more folders.
#       --out FILE       write the file to FILE.
#   Without --wait, the kit waits for Enter, and then watches for
#   AGENT_SIGNALS_WATCH seconds (default 30). With no terminal, it does
#   not wait for Enter.
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
trap 'rm -f "$raw" "$raw".*' EXIT

agents="claude codex agy cursor opencode copilot gemini"
command_of() {
  case $1 in
    cursor) command -v cursor-agent >/dev/null 2>&1 && echo cursor-agent || echo agent ;;
    *) echo "$1" ;;
  esac
}

# The folders that hold the session state of each agent.
state_dirs() {
  case $1 in
    claude) echo "$HOME/.claude/sessions $HOME/.claude/projects" ;;
    codex) echo "${CODEX_HOME:-$HOME/.codex}/sessions ${CODEX_HOME:-$HOME/.codex}/thread-writer-locks" ;;
    agy) echo "$HOME/.gemini/antigravity-cli" ;;
    cursor) echo "$HOME/.cursor/chats $HOME/.cursor/projects" ;;
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

finish() {
  sh "$root/tools/scrub.sh" "$raw" >"$out" 2>"$raw.scrub"
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
    if [ -z "$ans" ] && [ -t 0 ]; then
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

# watched: the pids of the --pids file or folder, and their children. A
# folder holds one file for each pid, named by the pid (the pids/ folder
# of a kit run).
watched() {
  if [ -d "$pids_from" ]; then
    ls "$pids_from"
  else
    cat "$pids_from"
  fi | while read -r _w; do
    case $_w in '' | *[!0-9]*) continue ;; esac
    children "$_w"
  done
}

# agent_pids AGENT: the pids of the agent processes that the step counts.
agent_pids() {
  if [ -z "$pids_from" ]; then
    pids "$(pattern_of "$1")"
    return
  fi
  _set=" $(watched | tr '\n' ' ') "
  pids "$(pattern_of "$1")" | while read -r _x; do
    case $_set in *" $_x "*) echo "$_x" ;; esac
  done
}

# roots AGENT: the folders that the step reads for AGENT: the state
# folders of the agent and the --scope folders, one on each line.
roots() {
  for _d in $(state_dirs "$1"); do echo "$_d"; done
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
# line count of the JSONL files. The line counts include files out of the
# scope, so that a file that opens during the step has a count before.
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

# claude_status: the status field of each Claude pid file (fact 23).
claude_status() {
  for f in "$HOME"/.claude/sessions/*.json; do
    [ -f "$f" ] || continue
    s=$(sed -n 's/.*"status":"\([a-z]*\)".*/\1/p' "$f")
    echo "$(basename "$f" .json) ${s:-none}"
  done
}

# seconds NAME VALUE: exit 2 when VALUE is not a number from 1 to 600.
seconds() {
  case $2 in
    '' | *[!0-9]*) echo "kit: $1 takes a number from 1 to 600: $2"; exit 2 ;;
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
        scope="$scope
${2%/}"
        shift 2
        ;;
      --out)
        [ "$#" -ge 2 ] || { echo "kit: --out needs a file"; exit 2; }
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
  watch_s=${AGENT_SIGNALS_WATCH:-30}
  seconds AGENT_SIGNALS_WATCH "$watch_s"
  [ -n "$wait_s" ] && watch_s=$wait_s
  which=
  for a in ${pick:-$agents}; do
    case $a in
      agent | cursor-agent) a=cursor ;;
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
      [ -z "$wait_s$pids_from$scoped$scope" ] || { echo "kit: front-tab asks questions, so it takes no other option"; exit 2; }
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
  claude_status >"$raw.status.0"
  agy_status >"$raw.agy.0"
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
    if [ -t 0 ]; then
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
  while [ $((t + 2)) -le "$watch_s" ]; do
    sleep 2
    t=$((t + 2))
    i=$((i + 1))
    claude_status >"$raw.status.$i"
    agy_status >"$raw.agy.$i"
  done
  [ "$t" -lt "$watch_s" ] && sleep $((watch_s - t))
  # shellcheck disable=SC2086
  snapshot after $which
  {
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
        j=0
        while [ "$j" -le "$i" ]; do
          echo "t=$((j * 2))s: $(cat "$raw.agy.$j")"
          j=$((j + 1))
        done
        ;;
    esac
  } >>"$raw"
  finish
}

front_tab() {
  [ "$PROBE_OS" = macos ] || { echo "kit: front-tab is for macOS"; exit 2; }
  [ -t 0 ] || { echo "kit: front-tab asks questions, so it needs a terminal"; exit 2; }
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
  *) sed -n '2,36p' "$0"; exit 2 ;;
esac
