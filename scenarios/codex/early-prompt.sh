#!/bin/sh
# Scenario: a prompt that reaches Codex just after the first idle screen.
#
# It answers one question: does a prompt sent DELAY seconds after the screen
# first shows "Ask Codex to do anything" reach the model?
#
# Each trial starts a new Codex process in a new throwaway home, with the
# fake model of the kit (probes/agent/fake-model.py). It waits for the idle
# text, waits DELAY, types the prompt, waits 0.2 s, and sends Enter. The trial
# counts as "sent" when the approval dialog shows within 6 s. Else it reads the
# screen: "text-in-box" when the text waits in the box and the fake model got
# no request, "asked-no-dialog" when it got a request, and "text-gone" when the
# box does not show the text.
#
# Needs: codex, tmux, python3. No login, no network, no cost.
# Run: sh scenarios/codex/early-prompt.sh [TRIALS] [DELAY ...]
# Each trial takes about 8 s. The output is one line for each delay.
set -u
here=$(cd "$(dirname "$0")/../.." && pwd)
trials=${1:-10}
[ "$#" -gt 0 ] && shift
[ "$#" -gt 0 ] || set -- 0 0.3 0.5 0.8 1 1.5 2 3
codex --version
trial() {
  d=$(mktemp -d)
  mkdir "$d/home" "$d/work"
  python3 "$here/probes/agent/fake-model.py" --codex-home "$d/home/.codex" --log "$d/log" </dev/null >/dev/null 2>&1 &
  fake=$!
  while [ ! -f "$d/home/.codex/config.toml" ]; do sleep 0.1; done
  t() { tmux -S "$d/s" "$@"; }
  (cd "$d/work" && t new-session -d -s t -x 120 -y 36 \
    "env -i HOME=$d/home PATH=$PATH TERM=xterm-256color AGENT_SIGNALS_FAKE_KEY=dummy codex")
  n=0
  while [ "$n" -lt 300 ]; do
    s=$(t capture-pane -p)
    case $s in
      *'Ask Codex to do'*) break ;;
      *'Trust and continue'*) t send-keys Enter ;;
    esac
    n=$((n + 1))
    sleep 0.05
  done
  sleep "$1"
  t send-keys -l 'Create a file now'
  sleep 0.2
  t send-keys Enter
  r=lost
  n=0
  while [ "$n" -lt 60 ]; do
    case $(t capture-pane -p) in *'Would you like'*) r=sent; break ;; esac
    n=$((n + 1))
    sleep 0.1
  done
  if [ "$r" = lost ]; then
    case $(t capture-pane -p) in
      *'› Create a file now'*)
        n=$(grep -c POST "$d/log")
        [ "$n" -gt 0 ] && r=asked || r=box
        ;;
      *) r=gone ;;
    esac
  fi
  t kill-server 2>/dev/null
  kill "$fake" 2>/dev/null
  rm -rf "$d"
  echo "$r"
}
for delay in "$@"; do
  sent=0 box=0 gone=0 asked=0 i=0
  while [ "$i" -lt "$trials" ]; do
    i=$((i + 1))
    case $(trial "$delay") in
      sent) sent=$((sent + 1)) ;;
      box) box=$((box + 1)) ;;
      asked) asked=$((asked + 1)) ;;
      *) gone=$((gone + 1)) ;;
    esac
  done
  echo "delay=$delay sent=$sent text-in-box=$box text-gone=$gone asked-no-dialog=$asked"
done
