#!/bin/sh
# The probe kit for Linux and macOS.
#
# Usage:
#   sh probes/run.sh            run every probe whose agent is installed
#   sh probes/run.sh --all      run every probe
#   sh probes/run.sh --guided STEP [AGENT]
#       STEP: permission | new-chat | resume | interrupt | front-tab
#       AGENT: claude | codex | agy | cursor | opencode | copilot | gemini
#       (default: all)
#
# The kit writes one file in the current folder:
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
    agy) echo "$HOME/.gemini/antigravity-cli/presence $HOME/.gemini/antigravity-cli/conversations $HOME/.gemini/antigravity-cli/brain" ;;
    cursor) echo "$HOME/.cursor/chats $HOME/.cursor/projects" ;;
    opencode) echo "${XDG_DATA_HOME:-$HOME/.local/share}/opencode" ;;
    copilot) echo "$HOME/.copilot/session-state" ;;
    gemini) echo "$HOME/.gemini/tmp $HOME/.gemini/history" ;;
  esac
}

# The process pattern of each agent (as in its probe).
pattern_of() {
  case $1 in
    claude) echo '(^|[ /])claude( |$)' ;;
    codex) echo '(^|[ /])codex( |$)' ;;
    agy) echo '(^|[ /])agy( |$)' ;;
    cursor) echo 'cursor-agent|/\.local/bin/agent( |$)' ;;
    opencode) echo '(^|[ /])opencode( |$)' ;;
    copilot) echo '(^|[ /])copilot( |$)|/copilot-(linux|darwin)-[a-z0-9]+/copilot' ;;
    gemini) echo '(^|[ /])gemini( |$)' ;;
  esac
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
    printf 'kit: run the terminal probe? It can open an Automation dialog. [y/N] '
    read -r ans
    case $ans in
      y | Y) { echo; echo "################ terminals"; sh "$here/terminals/macos.sh" 2>&1; } >>"$raw" ;;
      *) echo "################ terminals: skipped by the operator" >>"$raw" ;;
    esac
  fi
  finish
}

# snapshot NAME AGENTS: the open state files of each agent process, and the
# line count of the newest JSONL files.
snapshot() {
  name=$1
  shift
  for a in "$@"; do
    for x in $(pids "$(pattern_of "$a")"); do
      for k in $(children "$x"); do
        open_files "$k" '\.claude|\.codex|\.gemini|\.cursor|opencode|\.copilot' | sed "s#^#$a $x #"
      done
    done
  done | sort -u >"$raw.$name.open"
  for a in "$@"; do
    for d in $(state_dirs "$a"); do
      [ -d "$d" ] && find "$d" -name '*.jsonl' -type f 2>/dev/null
    done
  done | while read -r f; do
    echo "$(wc -l <"$f" | tr -d ' ') $f"
  done >"$raw.$name.lines"
}

# claude_status: the status field of each Claude pid file (fact 23).
claude_status() {
  for f in "$HOME"/.claude/sessions/*.json; do
    [ -f "$f" ] || continue
    s=$(sed -n 's/.*"status":"\([a-z]*\)".*/\1/p' "$f")
    echo "$(basename "$f" .json) ${s:-none}"
  done
}

guided() {
  step=$1
  which=${2:-$agents}
  case $step in
    permission) action="In one agent session, ask for a file write, for example: Create a file named note.txt that holds the word hello. Wait until the permission dialog shows. Do not answer it yet." ;;
    new-chat) action="In one session, start a new chat: /new-chat in Cursor, /clear in Claude, /new in Codex." ;;
    resume) action="Exit one session. Then start it again with its resume command: cursor-agent --resume, claude --continue, codex resume --last, agy --continue." ;;
    interrupt) action="In one session, send a prompt that takes some time, then push Esc while the agent works. Then push Ctrl+C one time." ;;
    front-tab) front_tab; return ;;
    *) echo "kit: unknown step: $step"; exit 2 ;;
  esac
  {
    echo "agent-signals guided step: $step, $stamp"
    echo "agents: $which"
  } >"$raw"
  # shellcheck disable=SC2086
  snapshot before $which
  marker=$raw.marker
  : >"$marker"
  claude_status >"$raw.status.0"
  echo
  echo "kit: do this now, then come back and push Enter:"
  echo "  $action"
  printf 'kit: push Enter when it is done. '
  read -r _
  echo "kit: watching the agent folders for 30 s. Do not touch the session."
  i=1
  while [ "$i" -le 15 ]; do
    sleep 2
    claude_status >"$raw.status.$i"
    i=$((i + 1))
  done
  # shellcheck disable=SC2086
  snapshot after $which
  {
    echo
    echo "### 1. Files that changed during the step (size, path)"
    for a in $which; do
      for d in $(state_dirs "$a"); do
        [ -d "$d" ] && find "$d" -type f -newer "$marker" 2>/dev/null | while read -r f; do
          echo "$a $(wc -c <"$f" | tr -d ' ') $f"
        done
      done
    done
    echo
    echo "### 2. Open state files: before (<) and after (>)"
    diff "$raw.before.open" "$raw.after.open" || true
    echo
    echo "### 3. New records in JSONL files (types only)"
    while read -r n f; do
      o=$(awk -v f="$f" '$2 == f {print $1}' "$raw.before.lines")
      [ "$n" = "${o:-0}" ] && continue
      echo "== $f (lines $o -> $n)"
      tail -n "+$((${o:-0} + 1))" "$f" | head -n 40 >"$raw.new"
      jsonl_types "$raw.new" 40
    done <"$raw.after.lines"
    echo
    echo "### 4. Status of the Claude pid files, every 2 s (fact 23)"
    j=0
    while [ "$j" -le 15 ]; do
      echo "t=$((j * 2))s: $(tr '\n' ' ' <"$raw.status.$j")"
      j=$((j + 1))
    done
  } >>"$raw"
  finish
}

front_tab() {
  [ "$PROBE_OS" = macos ] || { echo "kit: front-tab is for macOS"; exit 2; }
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
  --guided) shift; guided "${1:-}" "${2:-}" ;;
  --all | "") run_all "${1:-}" ;;
  *) sed -n '2,16p' "$0"; exit 2 ;;
esac
