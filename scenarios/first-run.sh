#!/bin/sh
# Scenario: the first start of an agent with no login.
#
# It starts the agent in a throwaway HOME and a private tmux server, sends
# no key, and records after 5 s and after 20 s: the screen, the process
# tree, the open files, and the files that the agent made in HOME.
# It answers: what does a new install show first, which processes start,
# and which files exist before a login?
#
# Needs: tmux and the agent. No login, no model turn, no cost.
# Run: sh scenarios/first-run.sh AGENT [COMMAND]
#   AGENT: claude | codex | agy | cursor | opencode, or any name with COMMAND
set -eu
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scenarios/lib.sh
. "$here/lib.sh"

agent=${1:?usage: first-run.sh AGENT}
case $agent in
  claude) cmd=claude ;;
  codex) cmd=codex ;;
  agy) cmd=agy ;;
  cursor) cmd=cursor-agent ;;
  opencode) cmd=opencode ;;
  *) cmd=${2:-} ;;
esac
[ -n "${2:-}" ] && cmd=$2
[ -n "$cmd" ] || die "unknown agent: $agent (give the command too)"
command -v "$cmd" >/dev/null 2>&1 || die "not installed: $cmd"

SCN_NAME=first-run-$agent
sandbox_start
# The version is the first line on stdout. Some agents print a warning
# on stderr first (OpenHands), so stderr counts only when stdout is empty.
v=$("$cmd" --version 2>/dev/null </dev/null | grep -v '^[[:space:]]*$' | head -n 1)
[ -n "$v" ] || v=$("$cmd" --version 2>&1 </dev/null | head -n 1)
note "version: $v"
note "os: $PROBE_OS $(uname -m)"

step() {
  capture "$1"
  processes "$1" "$(agent_pid)"
  scn_open_files "$1" "$(agent_pid)"
  snapshot_files "$1" "$SCN_HOME"
  note "step $1"
}

tmux_start "$cmd"
sleep 5
step 01-after-5s
sleep 15
step 02-after-20s
echo "done: $SCN_OUT"
