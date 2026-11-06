#!/bin/sh
# Step "real-session" (needs operator, cost none): the guided step for a
# session of the agent that the operator starts in a real terminal. The
# kit starts no session. It only watches.
#
#   kit step real-session-AGENT@operator
#       prints "operator: <action>" lines and exits 4. The operator starts
#       the session and asks for a file write.
#   kit step real-session-AGENT@operator --ready
#       runs the guided step of probes/run.sh with --wait 30 on one session
#       of AGENT. A process counts when:
#       - it matches the pattern of AGENT, by the rules of probes/run.sh:
#         not the kit, not a tmux or psmux process (is_mux), and not a
#         shell that runs command text (shell_text);
#       - it belongs to the current account;
#       - it started after the first call (RUN/.kit/ask-AGENT holds the
#         time of that call);
#       - it is not a pid of RUN/pids/, not an ancestor of the kit whose
#         command line matches the pattern of an agent (the orchestrator),
#         and not a descendant of these.
#       A process below a counted process belongs to that session.
#       With no such process (reason no-session), or with more than one
#       session (reason many-sessions), it prints "operator:" lines and
#       exits 4. A --ready with no first call acts as the first call.
#
# The guided step shows only the files that the watched processes hold
# open (--files-of-pids), because the kit does not know the folder of the
# session. With AGENT_SIGNALS_WATCH set (the tests), the watch takes that
# number of seconds.
set -u
: "${KIT_RUN:?}" "${KIT_ROOT:?}" "${KIT_DIR:?}" "${KIT_OUT:?}" "${KIT_STEP:?}" "${KIT_AGENT:?}"
. "$KIT_DIR/lib.sh"
# pids, is_mux and shell_text: the rules of probes/run.sh.
# shellcheck source=probes/lib.sh
. "$KIT_ROOT/probes/lib.sh"

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

askf=$KIT_RUN/.kit/ask-$KIT_AGENT
if [ -z "$ready" ] || [ ! -r "$askf" ]; then
  mkdir -p "$KIT_RUN/.kit"
  date +%s >"$askf"
  ask
  reason ask
  exit 4
fi
since=$(cat "$askf")

pat=$(kit_agent_pattern "$KIT_AGENT")
if [ -z "$pat" ]; then
  reason no-pattern
  exit 3
fi

tmp=$(mktemp -d "$(dirname "$KIT_OUT")/real.XXXXXX") || exit 1
trap 'exit 130' INT TERM
trap 'rm -rf "$tmp"' EXIT

# no_session: the session has gone, or none started.
no_session() {
  echo "kit: no new session of $KIT_AGENT runs that the kit did not start." >&2
  ask
  reason no-session
  exit 4
}

# below ROOTS SELF: the pids below a pid of the file ROOTS. With SELF "yes",
# also the pids of ROOTS.
below() {
  ps -A -o pid= -o ppid= 2>/dev/null | awk -v rootf="$1" -v self="$2" '
    BEGIN { while ((getline r <rootf) > 0) root[r] = 1 }
    { par[$1] = $2 }
    END {
      for (p in par) {
        n = 0
        x = (self == "yes") ? p : par[p]
        while (x != "" && x + 0 > 1 && n++ < 1000) {
          if (x in root) { print p; break }
          x = par[x]
        }
      }
    }'
}

# age PID: the age of PID in seconds, from "[[dd-]hh:]mm:ss".
age() {
  ps -o etime= -p "$1" 2>/dev/null | tr -d ' ' | awk -F '[-:]' '
    NF >= 2 { s = $NF + 60 * $(NF - 1); if (NF >= 3) s += 3600 * $(NF - 2); if (NF == 4) s += 86400 * $1; print s }'
}

# The roots of the processes that do not count: this script, each ancestor
# whose command line matches the pattern of an agent, and the pids of
# RUN/pids/.
{
  echo "$$"
  q=$$
  while q=$(ps -o ppid= -p "$q" 2>/dev/null | tr -d ' ') && [ "${q:-0}" -gt 1 ]; do
    args=$(ps -o args= -p "$q" 2>/dev/null)
    case $args in *probes/agent/*) continue ;; esac
    for a in $KIT_ALL_AGENTS; do
      re=$(kit_agent_pattern "$a")
      [ -n "$re" ] || continue
      if printf '%s\n' "$args" | grep -Eq -- "$re"; then
        echo "$q"
        break
      fi
    done
  done
  for f in "$KIT_RUN"/pids/*; do
    [ -f "$f" ] && basename "$f"
  done
} >"$tmp/roots"
skip=" $(below "$tmp/roots" yes | tr '\n' ' ') "

uid=$(id -u)
now=$(date +%s)
pids "$pat" | while read -r p; do
  case $skip in *" $p "*) continue ;; esac
  [ "$(ps -o uid= -p "$p" 2>/dev/null | tr -d ' ')" = "$uid" ] || continue
  is_mux "$p" && continue
  shell_text "$p" && continue
  a=$(age "$p")
  [ -n "$a" ] && [ $((now - a)) -ge "$since" ] || continue
  echo "$p"
done >"$tmp/found"

# One session: a process below a found process belongs to it.
inner=" $(below "$tmp/found" no | tr '\n' ' ') "
while read -r p; do
  case $inner in *" $p "*) ;; *) echo "$p" ;; esac
done <"$tmp/found" >"$tmp/pids"

n=$(wc -l <"$tmp/pids" | tr -d ' ')
[ "$n" -gt 0 ] || no_session
if [ "$n" -gt 1 ]; then
  echo "operator: $n sessions of $KIT_AGENT started after the kit asked. The kit watches one session only."
  echo "operator: stop all of them except one."
  echo "operator: the agent then runs: kit step $KIT_STEP@operator --ready"
  reason many-sessions
  exit 4
fi

secs=${AGENT_SIGNALS_WATCH:-30}
echo "kit: $KIT_STEP@operator: watch one session of $KIT_AGENT for $secs s" >&2
sh "$KIT_ROOT/probes/run.sh" --guided permission "$KIT_AGENT" --wait "$secs" \
  --pids "$tmp/pids" --files-of-pids --out "$tmp/watch.txt" </dev/null >"$tmp/watch.log" 2>&1
code=$?
# run.sh exits 2 when the session has gone.
[ "$code" -ne 2 ] || no_session
if [ "$code" -ne 0 ] || [ ! -s "$tmp/watch.txt" ]; then
  cat "$tmp/watch.log" >&2
  reason "guided-exit-$code"
  exit 1
fi
mv "$tmp/watch.txt" "$KIT_OUT"
exit 0
