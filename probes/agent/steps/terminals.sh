#!/bin/sh
# Step "terminals" (needs screen, cost none, macOS only): the terminal
# probe, probes/terminals/macos.sh. It lists the terminal programs, their
# tabs and the tty of each agent. It types nothing and selects no tab.
# Caution: the first osascript call of the probe can open a macOS dialog
# that asks for Automation access to Terminal or iTerm2. The operator can
# say no. That is why the step needs "screen".
set -u
: "${KIT_ROOT:?}" "${KIT_OUT:?}"
if [ "$(uname -s)" != Darwin ]; then
  echo "not-macos" >"$KIT_OUT.reason"
  exit 3
fi
{
  echo "agent-signals terminal probe, $(date -u +%Y%m%dT%H%M%SZ)"
  echo
  echo "################ terminals"
  sh "$KIT_ROOT/probes/terminals/macos.sh" 2>&1 </dev/null
} >"$KIT_OUT"
