#!/bin/sh
# A stub agent for the tests of the agent kit. It needs a terminal on its
# input. It draws a known idle screen and a known dialog screen, and it
# writes a file in the current folder. It calls no model.
#
# Keys:
#   text, then Enter   "write" or the prompt of the permission steps
#                      ("Create a file named ...") opens the dialog.
#                      "env" writes the environment to stub-env.txt.
#                      "Count ..." makes the stub busy. "/clear" clears
#                      the note. Other text goes back to idle.
#   1 in the dialog    writes agent-signals-test.txt with "hello".
#   2 or Escape in the dialog goes back to idle.
#   Escape when busy   goes back to idle.
#   C-c or C-d         stops the stub.
#   C-u                clears the box.
#
# The idle screen has the line "? for shortcuts", the dialog screen the
# line "Do you want to create agent-signals-test.txt?" and the busy screen
# the text "esc to interrupt", as the steps.tsv regexes of claude want.
#
# Settings: the environment, or the file "$0.env" (lines NAME=VALUE that
# the stub reads with "."). A test that copies the stub to bin/claude puts
# its settings in bin/claude.env, because "kit session" starts the agent
# with a clean environment.
#   STUB_LOG=FILE      add one line to FILE for each key: "key Enter",
#                      "key Escape", "key C-c", "key C-d", or "char C" for
#                      a character C.
#   STUB_DIALOG=no     the prompt of the permission steps opens no dialog.
#   STUB_RECORDS=no    the stub writes no record (read record below).
#   STUB_WELCOME=TEXT  the idle screen shows TEXT, as a welcome box does.
#   STUB_EXIT=yes      the stub stops at a prompt.
#   STUB_BUSY=no       "Count ..." does not make the stub busy.
#   STUB_KEEP=yes      "/clear" stays in the box after Enter.
#   STUB_LOSE=N        the stub drops the first N characters of input, as an
#                      agent that redraws its box after the idle screen.
#   STUB_TRUST=yes     start with a trust question, with the selection on
#                      "No, exit". Down moves the selection to "Yes, I
#                      trust this folder". Enter on Yes goes to idle, Enter
#                      on No stops the stub.
#
# Each prompt of a session step (Create, Count, /clear, Reply) writes the
# file stub-work.txt in the current folder, and one record to the file
# stub.jsonl in the Claude project folder of the current folder. The stub
# makes that folder at the first prompt, and holds the file open.
#
# The stub starts no process while it waits for a key, except dd, so that
# a process count sees one stub process.
#
# Run: sh tools/testdata/agent-kit/stub-agent.sh
set -u
# shellcheck disable=SC1090
[ -r "$0.env" ] && . "$0.env"
esc=$(printf '\033')
eot=$(printf '\004')
etx=$(printf '\003')
cr=$(printf '\r')
nak=$(printf '\025')
lose=${STUB_LOSE:-0}
kf=$(mktemp) || exit 1
saved=$(stty -g 2>/dev/null || true)
restore() { [ -n "$saved" ] && stty "$saved" 2>/dev/null; rm -f "$kf"; }
trap 'restore; exit 0' EXIT
trap 'exit 0' INT TERM HUP
# No echo, no line buffer and no signal keys, so that the stub reads each
# key.
stty -icanon -echo -isig min 1 time 0 2>/dev/null

state=idle
sel=no
[ "${STUB_TRUST:-}" = yes ] && state=trust
case " $* " in *" --continue "* | *" resume "*) note="continued" ;; *) note= ;; esac
buf=
draw() {
  printf '\033[H\033[2J'
  case $state in
    dialog)
      printf 'stub dialog\r\n\r\n'
      printf 'Do you want to create agent-signals-test.txt?\r\n'
      printf '1. Yes\r\n'
      printf '2. No\r\n'
      ;;
    trust)
      printf 'stub trust\r\n\r\n'
      if [ "$sel" = yes ]; then
        printf '\342\235\257 Yes, I trust this folder\r\n  No, exit\r\n'
      else
        printf '  Yes, I trust this folder\r\n\342\235\257 No, exit\r\n'
      fi
      ;;
    busy)
      printf 'stub busy\r\n\r\n* Counting (esc to interrupt)\r\n'
      ;;
    *)
      printf 'stub idle\r\n'
      [ -n "${STUB_WELCOME:-}" ] && printf '%s\r\n' "$STUB_WELCOME"
      [ -n "$note" ] && printf '%s\r\n' "$note"
      printf '\r\n> %s\r\n? for shortcuts' "$buf"
      ;;
  esac
}

# record: read the comment at the start of this file.
held=
record() {
  [ "${STUB_RECORDS:-}" = no ] && return 0
  echo stub >stub-work.txt
  if [ -z "$held" ]; then
    held=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/$(printf '%s' "$(pwd -P)" | tr -c 'A-Za-z0-9' '-')
    mkdir -p "$held"
    exec 3>>"$held/stub.jsonl"
  fi
  echo '{"type":"user"}' >&3
}

# key: read one byte into c. dd writes it to a file, and "read" gets it
# with no subshell. At the end of the input, dd gives no byte: stop.
key() {
  dd bs=1 count=1 of="$kf" 2>/dev/null
  [ -s "$kf" ] || exit 0
  c=
  IFS= read -r c <"$kf" || :
  # "read" gives an empty value for a newline.
  [ -n "$c" ] || c=$cr
}

draw
while :; do
  key
  if [ -n "${STUB_LOG:-}" ]; then
    case $c in
      "$cr") k="key Enter" ;;
      "$esc") k="key Escape" ;;
      "$etx") k="key C-c" ;;
      "$eot") k="key C-d" ;;
      *) k="char $c" ;;
    esac
    echo "$k" >>"$STUB_LOG"
  fi
  case $c in
    "$etx" | "$eot") exit 0 ;;
  esac
  case $state in
    trust)
      case $c in
        "$esc")
          # An arrow key: ESC [ A to D.
          key
          key
          case $c in A) sel=yes ;; B) sel=yes ;; esac
          ;;
        "$cr")
          [ "$sel" = yes ] || exit 0
          state=idle
          ;;
      esac
      ;;
    dialog)
      case $c in
        1)
          echo hello >agent-signals-test.txt
          note="created agent-signals-test.txt"
          state=idle
          ;;
        2 | "$esc")
          note="no file"
          state=idle
          ;;
      esac
      ;;
    busy)
      case $c in
        "$esc")
          note="interrupted"
          state=idle
          ;;
      esac
      ;;
    *)
      case $c in
        "$cr")
          case $buf in
            "Create a file named"* | Count* | /clear | Reply*)
              record
              [ "${STUB_EXIT:-}" = yes ] && exit 0
              ;;
          esac
          case $buf in
            write | "Create a file named"*)
              if [ "${STUB_DIALOG:-}" = no ]; then note="no dialog"; else state=dialog; fi
              ;;
            env)
              env >stub-env.txt
              note="env saved"
              ;;
            Count*) [ "${STUB_BUSY:-}" = no ] || state=busy ;;
            /clear)
              note="cleared"
              ;;
            *) note= ;;
          esac
          if [ "${STUB_KEEP:-}" = yes ] && [ "$buf" = /clear ]; then
            note=
          else
            buf=
          fi
          ;;
        "$esc") buf='' note='' ;;
        "$nak") buf= ;;
        *)
          if [ "$lose" -gt 0 ]; then
            lose=$((lose - 1))
          else
            buf=$buf$c
          fi
          ;;
      esac
      ;;
  esac
  draw
done
