#!/bin/sh
# Scenario: capture Codex CLI screens for the corpus: idle, busy, the F2
# Warnings view, and the screen after Esc on that view.
#
# Needs: codex, tmux, and a Codex login in REAL_HOME (copied).
# Cost: one short turn on the plan of the login.
# Run: sh scenarios/codex/screens.sh
# The screens hold the path of the throwaway folder. Scrub it to
# /work/example and record the edit before a screen goes into the corpus.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=scenarios/lib.sh
. "$here/lib.sh"

SCN_NAME=codex-screens
sandbox_start
copy_login codex || die "no Codex login that is safe to copy"

tmux_start codex --sandbox read-only --ask-for-approval on-request
wait_for '\? for shortcuts' 30 || note "no idle footer seen"
sleep 3
capture idle
note "idle"

send_text "Count from 1 to 40, one number on each line. Use no tool."
send_key Enter
# Capture every 0.5 s for 6 s, so that one capture has the busy line.
i=0
while [ "$i" -lt 12 ]; do
  sleep 0.5
  capture "busy-$i"
  i=$((i + 1))
done
note "busy captures"
wait_for 'Worked for' 90 || note "no end of turn seen"
sleep 2
capture after-turn

send_key F2
sleep 2
capture warnings
note "warnings view"
send_key Escape
sleep 2
capture after-warnings
note "done"
echo "done: $SCN_OUT"
