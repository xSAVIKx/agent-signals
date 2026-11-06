#!/bin/sh
# Step "first-run" (needs none, cost none): the first start of an agent
# with a throwaway HOME and no login. It runs scenarios/first-run.sh, which
# starts the agent in a private tmux server, sends no key, and records the
# screen, the processes, the open files and the files in HOME after 5 s
# and after 20 s. The step puts all the output files of the scenario in
# KIT_OUT, one section for each file, and "kit step" scrubs it.
#
# It copies no login: the release kit has no scenarios/login.sh. It skips
# (exit 3) with the reason "needs-scenario" when the scenario files are not
# in the kit, and "needs-tmux" when tmux is not installed.
set -u
: "${KIT_RUN:?}" "${KIT_ROOT:?}" "${KIT_DIR:?}" "${KIT_OUT:?}" "${KIT_AGENT:?}" "${KIT_BACKEND:?}"
. "$KIT_DIR/lib.sh"

reason() { echo "$1" >"$KIT_OUT.reason"; }
scn=$KIT_ROOT/scenarios
if [ ! -f "$scn/first-run.sh" ] || [ ! -f "$scn/lib.sh" ] || [ ! -f "$KIT_ROOT/probes/lib.sh" ]; then
  reason needs-scenario
  exit 3
fi
if [ "$KIT_BACKEND" != tmux ]; then
  reason "no-backend-$KIT_BACKEND"
  exit 3
fi
if ! command -v tmux >/dev/null 2>&1; then
  reason needs-tmux
  exit 3
fi
cmd=$(kit_agent_command "$KIT_AGENT")
if [ -z "$cmd" ]; then
  reason not-installed
  exit 3
fi

# The work folder is next to KIT_OUT, in the run folder, so that the
# scrub changes its path.
w=$(mktemp -d "$(dirname "$KIT_OUT")/first-run.XXXXXX") || exit 1
# dash runs no EXIT trap on a signal, so a signal exits first. The
# scenario has its own trap, which stops the agent and deletes the
# throwaway HOME.
trap 'exit 130' INT TERM
# The throwaway folders of the scenario go in the run folder, not in
# ~/.cache of the real HOME. The scenario deletes each of them.
sroot=$KIT_RUN/scenario
trap 'rm -rf "$w"; rmdir "$sroot" 2>/dev/null' EXIT
echo "kit: $KIT_STEP@$KIT_BACKEND: run scenarios/first-run.sh $KIT_AGENT (about 25 s)" >&2
(cd "$w" && SCN_ROOT=$sroot SCN_OUT="$w/out" sh "$scn/first-run.sh" "$KIT_AGENT" "$cmd") </dev/null >"$w/log" 2>&1
code=$?
{
  echo "agent-signals first-run step: $KIT_STEP@$KIT_BACKEND, $(date -u +%Y%m%dT%H%M%SZ)"
  echo "agent: $KIT_AGENT"
  echo "scenario exit: $code"
  echo
  echo "################ scenario output"
  cat "$w/log"
  for f in "$w"/out/*; do
    [ -f "$f" ] || continue
    echo
    echo "################ file: $(basename "$f")"
    cat "$f"
  done
} >"$KIT_OUT"
if [ "$code" -ne 0 ]; then
  reason "scenario-exit-$code"
  exit 1
fi
exit 0
