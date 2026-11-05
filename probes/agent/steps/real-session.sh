#!/bin/sh
# Step "real-session" (needs operator, cost none): the guided step for a
# session of the agent that the operator starts in a real terminal. The
# kit starts no session. It only watches.
#
#   kit step real-session-AGENT@operator
#       prints "operator: <action>" lines and exits 4. The operator starts
#       the session and asks for a file write.
#   kit step real-session-AGENT@operator --ready
#       runs the guided step of probes/run.sh with --wait 30 on the
#       processes of AGENT that the kit did not start: not a pid of
#       RUN/pids/, not the orchestrator (the first ancestor of the kit
#       whose command line matches the pattern of an agent), and not a
#       descendant of these. With no such process, it prints the
#       "operator:" lines again and exits 4.
#
# The guided step shows only the files that the watched processes hold
# open (--files-of-pids), because the kit does not know the folder of the
# session. With AGENT_SIGNALS_WATCH set (the tests), the watch takes that
# number of seconds.
set -u
: "${KIT_RUN:?}" "${KIT_ROOT:?}" "${KIT_DIR:?}" "${KIT_OUT:?}" "${KIT_STEP:?}" "${KIT_AGENT:?}"
. "$KIT_DIR/lib.sh"

reason() { echo "$1" >"$KIT_OUT.reason"; }

ready=
case ${1:-} in
  --ready) ready=yes ;;
  '') ;;
  *)
    echo "kit: usage: kit step $KIT_STEP@operator [--ready]" >&2
    reason bad-use
    exit 1
    ;;
esac

ask() {
  echo "operator: start $KIT_AGENT in a real terminal, in a new folder of your choice."
  echo "operator: in that session, send: Create a file named agent-signals-test.txt that holds the word hello."
  echo "operator: when the permission dialog shows, do not answer it. Tell the agent: ready."
  echo "operator: the agent then runs: kit step $KIT_STEP@operator --ready"
  echo "operator: the kit watches for 30 s. In the watch, push Esc to close the dialog."
}

if [ -z "$ready" ]; then
  ask
  reason ask
  exit 4
fi

pat=$(kit_agent_pattern "$KIT_AGENT")
if [ -z "$pat" ]; then
  reason no-pattern
  exit 3
fi

tmp=$(mktemp -d "$(dirname "$KIT_OUT")/real.XXXXXX") || exit 1
trap 'exit 130' INT TERM
trap 'rm -rf "$tmp"' EXIT

# The orchestrator: the first ancestor of this script whose command line
# matches the pattern of an agent, as in "kit doctor".
orch=
q=$$
while q=$(ps -o ppid= -p "$q" 2>/dev/null | tr -d ' ') && [ "${q:-0}" -gt 1 ]; do
  args=$(ps -o args= -p "$q" 2>/dev/null)
  case $args in *probes/agent/*) continue ;; esac
  for a in $KIT_ALL_AGENTS; do
    re=$(kit_agent_pattern "$a")
    [ -n "$re" ] || continue
    if printf '%s\n' "$args" | grep -Eq -- "$re"; then
      orch=$q
      break 2
    fi
  done
done

# The roots of the processes that do not count: the orchestrator and the
# pids of RUN/pids/.
{
  [ -n "$orch" ] && echo "$orch"
  for f in "$KIT_RUN"/pids/*; do
    [ -f "$f" ] && basename "$f"
  done
} >"$tmp/roots"

# The processes of the agent, with the processes below the roots taken
# out. The pattern and the rules of "pids" in probes/lib.sh: a process
# whose command line names probes/ does not count.
ps -A -o pid= -o ppid= -o args= 2>/dev/null | awk -v re="$pat" -v me="$$" -v rootf="$tmp/roots" '
  BEGIN { while ((getline r <rootf) > 0) skip[r] = 1 }
  {
    pid = $1; ppid = $2
    a = $0; sub(/^ *[0-9]+ +[0-9]+ +/, "", a)
    par[pid] = ppid; cmd[pid] = a; n[++k] = pid
  }
  END {
    for (i = 1; i <= k; i++) {
      p = n[i]
      if (cmd[p] !~ re || cmd[p] ~ /probes\// || cmd[p] ~ /^(awk|grep|ps) /) continue
      out = 0
      for (x = p; x != "" && x > 1; x = par[x]) {
        if (x in skip || x == me) { out = 1; break }
        if (++guard[p] > 1000) break
      }
      if (!out) print p
    }
  }' | sort -n >"$tmp/pids"

if [ ! -s "$tmp/pids" ]; then
  echo "kit: no session of $KIT_AGENT runs that the kit did not start." >&2
  ask
  reason no-session
  exit 4
fi

secs=${AGENT_SIGNALS_WATCH:-30}
echo "kit: $KIT_STEP@operator: watch $(wc -l <"$tmp/pids" | tr -d ' ') process(es) of $KIT_AGENT for $secs s" >&2
sh "$KIT_ROOT/probes/run.sh" --guided permission "$KIT_AGENT" --wait "$secs" \
  --pids "$tmp/pids" --files-of-pids --out "$tmp/watch.txt" </dev/null >"$tmp/watch.log" 2>&1
code=$?
if [ "$code" -ne 0 ] || [ ! -s "$tmp/watch.txt" ]; then
  cat "$tmp/watch.log" >&2
  reason "guided-exit-$code"
  exit 1
fi
mv "$tmp/watch.txt" "$KIT_OUT"
exit 0
