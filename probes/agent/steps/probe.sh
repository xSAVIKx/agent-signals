#!/bin/sh
# Step "probe" (needs none, cost none): the full probe kit,
# "probes/run.sh --all", with no key press. It runs in a new temporary
# folder, and its file goes to KIT_OUT. The terminal probe of macOS is the
# step "terminals", so this step answers its question with no.
set -u
: "${KIT_ROOT:?}" "${KIT_OUT:?}"
w=$(mktemp -d) || exit 1
# dash runs no EXIT trap on a signal, so a signal exits first.
trap 'exit 130' INT TERM
trap 'rm -rf "$w"' EXIT
cd "$w" || exit 1
AGENT_SIGNALS_TERMINALS=no sh "$KIT_ROOT/probes/run.sh" --all </dev/null >"$w/log" 2>&1
code=$?
set -- "$w"/agent-signals-probe-*.txt
if [ ! -f "$1" ]; then
  echo "no-probe-file" >"$KIT_OUT.reason"
  exit 1
fi
mv "$1" "$KIT_OUT" || exit 1
if [ "$code" -ne 0 ]; then
  echo "run.sh-exit-$code" >"$KIT_OUT.reason"
  exit 1
fi
exit 0
