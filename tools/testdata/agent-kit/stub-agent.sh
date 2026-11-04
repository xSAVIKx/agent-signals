#!/bin/sh
# A stub agent for the tests of the agent kit. It needs a terminal on its
# input. It draws a known idle screen and a known dialog screen, and it
# writes a file in the current folder. It calls no model.
#
# Keys:
#   text, then Enter   "write" opens the dialog. "env" writes the
#                      environment to stub-env.txt. Other text goes back
#                      to idle.
#   1 in the dialog    writes agent-signals-test.txt with "hello".
#   2 or Escape in the dialog goes back to idle.
#   C-c or C-d         stops the stub.
#
# Run: sh tools/testdata/agent-kit/stub-agent.sh
set -u
esc=$(printf '\033')
eot=$(printf '\004')
etx=$(printf '\003')
nl=$(printf '\nx')
nl=${nl%x}
cr=$(printf '\r')
saved=$(stty -g 2>/dev/null || true)
restore() { [ -n "$saved" ] && stty "$saved" 2>/dev/null; }
trap 'restore; exit 0' EXIT
trap 'exit 0' INT TERM HUP
# No echo, no line buffer and no signal keys, so that the stub reads each
# key.
stty -icanon -echo -isig min 1 time 0 2>/dev/null

state=idle
buf=
note=
draw() {
  printf '\033[H\033[2J'
  if [ "$state" = dialog ]; then
    printf 'stub dialog\r\n\r\n'
    printf 'Do you want to create agent-signals-test.txt?\r\n'
    printf '1. Yes\r\n'
    printf '2. No\r\n'
  else
    printf 'stub idle\r\n'
    [ -n "$note" ] && printf '%s\r\n' "$note"
    printf '\r\n> %s' "$buf"
  fi
}

draw
while :; do
  # The "x" keeps a newline in the value. At the end of the input, dd
  # gives no byte: stop.
  c=$(dd bs=1 count=1 2>/dev/null; echo x)
  c=${c%x}
  [ -n "$c" ] || exit 0
  case $c in
    "$etx" | "$eot") exit 0 ;;
  esac
  if [ "$state" = dialog ]; then
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
  else
    case $c in
      "$nl" | "$cr")
        case $buf in
          write) state=dialog ;;
          env)
            env >stub-env.txt
            note="env saved"
            ;;
          *) note= ;;
        esac
        buf=
        ;;
      "$esc") buf='' note='' ;;
      *) buf=$buf$c ;;
    esac
  fi
  draw
done
