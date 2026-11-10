# shellcheck shell=sh
# The terminal check: trace-cast.py (asciicast v2) and the recording of a
# traced tmux session in "kit session start".
. "$ROOT/tools/agent-kit-tests/lib.sh"
. "$ROOT/tools/agent-kit-tests/core-lib.sh"
. "$ROOT/tools/agent-kit-tests/steps-lib.sh"

cast=$ROOT/probes/agent/trace-cast.py
stub=$ROOT/tools/testdata/agent-kit/stub-agent.sh

# pids_run RUN: each pid of RUN/pids/ that still runs.
pids_run() {
  for f in "$1"/pids/*; do
    [ -f "$f" ] || continue
    p=$(basename "$f")
    kill -0 "$p" 2>/dev/null && echo "$p"
  done
}

# Unit: a character split over two writes stays whole.
printf '1700000000123\n' >"$T/t0"
{
  printf 'a\342\224'
  sleep 0.2
  printf '\200b'
} | python3 -I "$cast" --t0 "$T/t0" --out "$T/u.cast" --width 120 --height 40
expect_code "unit: trace-cast.py exits 0" 0 $?
want='{"version": 2, "width": 120, "height": 40, "timestamp": 1700000000, "env": {"TERM": "xterm-256color"}}'
if [ "$(head -n 1 "$T/u.cast")" = "$want" ]; then pass "unit: the header"; else fail "unit: the header" "$(head -n 1 "$T/u.cast")"; fi
text=$(python3 -I -c '
import json, sys
ev = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8")][1:]
assert all(e[1] == "o" for e in ev)
sys.stdout.write("".join(e[2] for e in ev))' "$T/u.cast")
if [ "$text" = "a─b" ]; then pass "unit: the joined text is a─b"; else fail "unit: the joined text is a─b" "$text"; fi
# A second run on the same file adds no second header.
printf 'c' | python3 -I "$cast" --t0 "$T/t0" --out "$T/u.cast" --width 120 --height 40
n=$(grep -c '"version"' "$T/u.cast")
if [ "$n" = 1 ]; then pass "unit: a second run adds no header"; else fail "unit: a second run adds no header" "$n headers"; fi

# An incomplete character at the end becomes U+FFFD.
printf 'x\342\224' | python3 -I "$cast" --t0 "$T/t0" --out "$T/e.cast" --width 120 --height 40
last=$(tail -n 1 "$T/e.cast" | python3 -I -c 'import json,sys; sys.stdout.write(json.loads(sys.stdin.read())[2])')
if [ "$last" = "$(printf '\357\277\275')" ]; then pass "unit: an incomplete end gives U+FFFD"; else fail "unit: an incomplete end gives U+FFFD" "$last"; fi

# A write to the cast fails after the open (/dev/full): exit 1 and the
# --failed file.
if [ -w /dev/full ]; then
  printf 'abc' | python3 -I "$cast" --t0 "$T/t0" --out /dev/full --failed "$T/full.failed" --width 120 --height 40 2>"$T/full.err"
  expect_code "unit: a failed write exits 1" 1 $?
  if [ -e "$T/full.failed" ]; then pass "unit: a failed write makes the --failed file"; else fail "unit: a failed write makes the --failed file" "no file"; fi
  expect_line "unit: a failed write gives one stderr line" 'a write to the cast failed' "$T/full.err"
else
  echo "skip: unit: /dev/full is missing"
fi
# A good run makes no --failed file.
printf 'd' | python3 -I "$cast" --t0 "$T/t0" --out "$T/g.cast" --failed "$T/g.failed" --width 120 --height 40
expect_code "unit: a good run exits 0" 0 $?
if [ ! -e "$T/g.failed" ]; then pass "unit: a good run makes no --failed file"; else fail "unit: a good run makes no --failed file" "file exists"; fi

# --pid-file holds the pid of the recorder and a newline.
python3 -I "$cast" --t0 "$T/t0" --out "$T/p.cast" --pid-file "$T/p.pid" --width 120 --height 40 </dev/null &
_pp=$!
wait "$_pp"
expect_code "unit: a run with --pid-file exits 0" 0 $?
if [ "$(cat "$T/p.pid")" = "$_pp" ]; then pass "unit: --pid-file holds the pid of the recorder"; else fail "unit: --pid-file holds the pid of the recorder" "$(cat "$T/p.pid") / $_pp"; fi

# rec_gone FILE: pass when the pid in FILE (recorder.pid) does not run.
rec_gone() {
  _rp=$(cat "$1" 2>/dev/null)
  if [ -z "$_rp" ]; then
    fail "$2" "no pid in $1"
  elif kill -0 "$_rp" 2>/dev/null; then
    fail "$2" "pid $_rp runs"
  else
    pass "$2"
  fi
}

if ! command -v tmux >/dev/null 2>&1; then
  echo "skip: tmux is not installed"
  done_tests
fi

mkdir -m 700 "$T/run1"
raw=$T/raw
mkdir -m 0700 "$raw"
date +%s%3N >"$raw/t0" 2>/dev/null
case $(cat "$raw/t0") in *[!0-9]* | '') python3 -I -c 'import time; print(time.time_ns() // 1000000)' >"$raw/t0" ;; esac

# Session: the stub on tmux with KIT_TRACE. A subshell sets the variables
# for one call only: macOS sh keeps a variable that is set before a
# function call.
export AGENT_SIGNALS_RUN="$T/run1"
(KIT_TRACE=$raw; KIT_TRACE_CHECKS=; export KIT_TRACE KIT_TRACE_CHECKS
 kit session start s1 stub --via tmux --cmd "sh '$stub'") >"$T/o" 2>&1
expect_code "session: start exits 0" 0 $?
kit session wait s1 'stub idle' 30 >"$T/o" 2>&1
expect_code "session: wait for idle" 0 $?
sdir=$T/run1/sessions/s1
agent_pid=$(awk -F '\t' '$1 == "s1" { print $4 }' "$raw/sessions.tsv")
if [ -n "$agent_pid" ] && [ "$(cat "$sdir/pid")" = "$agent_pid" ]; then
  pass "session: the pid file equals the AGENT_PID of sessions.tsv"
else
  fail "session: the pid file equals the AGENT_PID of sessions.tsv" "$(cat "$sdir/pid") / $agent_pid"
fi
# The pane pid is the agent pid: the gate loop ended with exec.
if [ -e "$sdir/gate" ]; then pass "session: the gate file exists"; else fail "session: the gate file exists" "no file"; fi
cp "$sdir/recorder.pid" "$T/s1.rec.pid" 2>/dev/null
kit session stop s1 --keep >"$T/o" 2>&1
expect_code "session: stop --keep exits 0" 0 $?
rec_gone "$T/s1.rec.pid" "session: no recorder stays after stop"
if grep -q 'stub idle' "$raw/terminal.cast"; then pass "session: the cast holds stub idle"; else fail "session: the cast holds stub idle" "$(head -c 300 "$raw/terminal.cast")"; fi
# A second start of the same session (resume) continues the same file.
(KIT_TRACE=$raw; KIT_TRACE_CHECKS=terminal,network; export KIT_TRACE KIT_TRACE_CHECKS
 kit session start s1 stub --via tmux --cmd "sh '$stub'") >"$T/o" 2>&1
expect_code "session: the second start exits 0" 0 $?
kit session wait s1 'stub idle' 30 >"$T/o" 2>&1
expect_code "session: the second wait for idle" 0 $?
cp "$sdir/recorder.pid" "$T/s1b.rec.pid" 2>/dev/null
kit session stop s1 >"$T/o" 2>&1
expect_code "session: the second stop exits 0" 0 $?
rec_gone "$T/s1b.rec.pid" "session: no recorder stays after the second stop"
n=$(grep -c '"version"' "$raw/terminal.cast")
if [ "$n" = 1 ]; then pass "session: one header line after a second start"; else fail "session: one header line after a second start" "$n headers"; fi
n=$(grep -c 'stub idle' "$raw/terminal.cast")
if [ "$n" -ge 2 ]; then pass "session: the second start adds events"; else fail "session: the second start adds events" "$n"; fi

# sock_gone NAME TEXT: a failed start leaves no socket folder.
sock_gone() {
  _s=$(cat "$T/run1/sessions/$1/socket" 2>/dev/null)
  if [ -n "$_s" ] && [ ! -e "$(dirname "$_s")" ]; then pass "$2"; else fail "$2" "${_s:-no socket file}"; fi
}

# The cast cannot be opened (a folder): the recorder is not ready, the
# start exits 1, and no pid of the run stays.
mkdir "$T/raw-bad"
cp "$raw/t0" "$T/raw-bad/t0"
mkdir "$T/raw-bad/terminal.cast"
(KIT_TRACE=$T/raw-bad; KIT_TRACE_CHECKS=; KIT_TRACE_GATE_TURNS=6; export KIT_TRACE KIT_TRACE_CHECKS KIT_TRACE_GATE_TURNS
 kit session start s7 stub --via tmux --cmd "sh '$stub'") >"$T/o" 2>&1
expect_code "no recorder: start exits 1" 1 $?
expect_line "no recorder: the reason" 'the recorder did not start|the gate wait ended' "$T/o"
left=$(pids_run "$T/run1")
if [ -z "$left" ]; then pass "no recorder: no pid of the run stays"; else fail "no recorder: no pid of the run stays" "$left"; fi
sock_gone s7 "no recorder: no socket folder stays"

# The recorder fails after the start: a file size limit (ulimit -f) of the
# server lets the recorder open the cast and make "ready", but the first
# event is too large. The agent continues to run, and "stop" appends
# "terminal<tab>recorder-failed" to skipped.tsv. The stop runs with no
# KIT_TRACE.
mkdir -m 0700 "$T/raw-full"
cp "$raw/t0" "$T/raw-full/t0"
# The cast is filled to the limit, so the recorder writes no header.
pad='import sys
f = open(sys.argv[1], "ab", buffering=0)
try:
    while True:
        f.write(b"x" * 512)
except OSError:
    pass'
if (ulimit -f 64) 2>/dev/null; then
  (ulimit -f 64; python3 -I -c "$pad" "$T/raw-full/terminal.cast")
  (KIT_TRACE=$T/raw-full; KIT_TRACE_CHECKS=; export KIT_TRACE KIT_TRACE_CHECKS
   ulimit -f 64
   kit session start s8 stub --via tmux --cmd "sh '$stub'") >"$T/o" 2>&1
  expect_code "recorder fails: start exits 0" 0 $?
  kit session wait s8 'stub idle' 30 >"$T/o" 2>&1
  expect_code "recorder fails: the agent runs" 0 $?
  _n=0
  while [ ! -e "$T/run1/sessions/s8/recorder-failed" ] && [ "$_n" -lt 100 ]; do
    sleep 0.05
    _n=$((_n + 1))
  done
  if [ -e "$T/run1/sessions/s8/recorder-failed" ]; then pass "recorder fails: the recorder-failed file"; else fail "recorder fails: the recorder-failed file" "no file"; fi
  cp "$T/run1/sessions/s8/recorder.pid" "$T/s8.rec.pid" 2>/dev/null
  # The stop runs with no KIT_TRACE: it reads the trace folder from the
  # state folder of the session.
  (unset KIT_TRACE
   kit session stop s8) >"$T/o" 2>&1
  expect_code "recorder fails: stop with no KIT_TRACE exits 0" 0 $?
  rec_gone "$T/s8.rec.pid" "recorder fails: no recorder stays after stop"
  if [ -f "$T/raw-full/skipped.tsv" ]; then
    expect_line "recorder fails: the skip line" '^terminal	recorder-failed$' "$T/raw-full/skipped.tsv"
  else
    fail "recorder fails: the skip line" "no skipped.tsv"
  fi
  left=$(pids_run "$T/run1")
  if [ -z "$left" ]; then pass "recorder fails: no pid of the run stays"; else fail "recorder fails: no pid of the run stays" "$left"; fi
else
  echo "skip: recorder fails: ulimit -f is not supported"
fi

# A run folder with a space in its path.
mkdir -m 700 "$T/run with space"
raws=$T/raw\ s
mkdir -m 0700 "$raws"
cp "$raw/t0" "$raws/t0"
(AGENT_SIGNALS_RUN="$T/run with space"; KIT_TRACE=$raws; KIT_TRACE_CHECKS=; export AGENT_SIGNALS_RUN KIT_TRACE KIT_TRACE_CHECKS
 kit session start s6 stub --via tmux --cmd "sh '$stub'") >"$T/o" 2>&1
expect_code "space: start exits 0" 0 $?
(AGENT_SIGNALS_RUN="$T/run with space"; export AGENT_SIGNALS_RUN
 kit session wait s6 'stub idle' 30) >"$T/o" 2>&1
expect_code "space: the agent started and shows idle" 0 $?
sp_pid=$(cat "$T/run with space/sessions/s6/pid")
sp_want=$(awk -F '\t' '$1 == "s6" { print $4 }' "$raws/sessions.tsv")
if [ -n "$sp_pid" ] && [ "$sp_pid" = "$sp_want" ]; then pass "space: the pid matches"; else fail "space: the pid matches" "$sp_pid / $sp_want"; fi
(AGENT_SIGNALS_RUN="$T/run with space"; export AGENT_SIGNALS_RUN
 kit session stop s6) >"$T/o" 2>&1
expect_code "space: stop exits 0" 0 $?
if grep -q 'stub idle' "$raws/terminal.cast"; then pass "space: the cast holds stub idle"; else fail "space: the cast holds stub idle" "no text"; fi

# KIT_TRACE_CHECKS=network: no cast and no gate wait.
rm -f "$raw/terminal.cast"
(KIT_TRACE=$raw; KIT_TRACE_CHECKS=network; export KIT_TRACE KIT_TRACE_CHECKS
 kit session start s2 stub --via tmux --cmd "sh '$stub'") >"$T/o" 2>&1
expect_code "network only: start exits 0" 0 $?
kit session wait s2 'stub idle' 30 >"$T/o" 2>&1
expect_code "network only: wait for idle" 0 $?
sock=$(cat "$T/run1/sessions/s2/socket")
pane=$(tmux -S "$sock" display -p -t kit '#{pane_start_command}' 2>/dev/null)
kit session stop s2 >"$T/o" 2>&1
if [ ! -e "$raw/terminal.cast" ]; then pass "network only: no cast file"; else fail "network only: no cast file" "file exists"; fi
case $pane in
  *gate*) fail "network only: no gate wait in the pane command" "$pane" ;;
  *) pass "network only: no gate wait in the pane command" ;;
esac

# A tmux wrapper: WRAP_MODE=fail makes pipe-pane fail, slow delays it by 1 s.
real_tmux=$(command -v tmux)
mkdir "$T/wrap"
cat >"$T/wrap/tmux" <<WRAPEOF
#!/bin/sh
for a in "\$@"; do
  if [ "\$a" = pipe-pane ]; then
    [ "\${WRAP_MODE:-}" = fail ] && exit 1
    [ "\${WRAP_MODE:-}" = slow ] && sleep 1
  fi
done
exec "$real_tmux" "\$@"
WRAPEOF
chmod +x "$T/wrap/tmux"

# pipe-pane fails: the start exits 1, the server is stopped, no pid stays.
(PATH="$T/wrap:$PATH"; KIT_TRACE=$raw; KIT_TRACE_CHECKS=; WRAP_MODE=fail; export PATH KIT_TRACE KIT_TRACE_CHECKS WRAP_MODE
 kit session start s4 stub --via tmux --cmd "sh '$stub'") >"$T/o" 2>&1
expect_code "pipe-pane fails: start exits 1" 1 $?
expect_line "pipe-pane fails: the reason" 'pipe-pane failed' "$T/o"
left=$(pids_run "$T/run1")
if [ -z "$left" ]; then pass "pipe-pane fails: no pid of the run stays"; else fail "pipe-pane fails: no pid of the run stays" "$left"; fi
sock_gone s4 "pipe-pane fails: no socket folder stays"

# The gate wait ends before the recorder starts: the start exits 1.
(PATH="$T/wrap:$PATH"; KIT_TRACE=$raw; KIT_TRACE_CHECKS=; WRAP_MODE=slow; KIT_TRACE_GATE_TURNS=4; export PATH KIT_TRACE KIT_TRACE_CHECKS WRAP_MODE KIT_TRACE_GATE_TURNS
 kit session start s5 stub --via tmux --cmd "sh '$stub'") >"$T/o" 2>&1
expect_code "gate timeout: start exits 1" 1 $?
expect_line "gate timeout: the reason" "gate wait ended" "$T/o"
left=$(pids_run "$T/run1")
if [ -z "$left" ]; then pass "gate timeout: no pid of the run stays"; else fail "gate timeout: no pid of the run stays" "$left"; fi
sock_gone s5 "gate timeout: no socket folder stays"

# Step with the states: the first event comes before the idle state.
stub_set STUB_TRUST=yes
rm -f "$raw/terminal.cast" "$raw/states.tsv" "$raw/sessions.tsv"
(KIT_TRACE=$raw; KIT_TRACE_CHECKS=; export KIT_TRACE KIT_TRACE_CHECKS; kitx step "permission-claude@tmux") >"$T/step" 2>&1
expect_code "step: exits 0" 0 $?
t0=$(cat "$raw/t0")
idle=$(awk -F '\t' '$2 == "idle" { print $1; exit }' "$raw/states.tsv")
first=$(sed -n 2p "$raw/terminal.cast" | python3 -I -c 'import json,sys; print(json.loads(sys.stdin.read())[0])')
if [ -n "$idle" ] && [ -n "$first" ] && awk -v f="$first" -v i="$idle" -v t="$t0" 'BEGIN { exit !(f * 1000 < i - t) }'; then
  pass "step: the first event is before the idle state"
else
  fail "step: the first event is before the idle state" "first=$first idle=$idle t0=$t0"
fi

# pty: a skip line, no cast.
if have pty; then
  rm -f "$raw/terminal.cast" "$raw/skipped.tsv"
  (KIT_TRACE=$raw; KIT_TRACE_CHECKS=; export KIT_TRACE KIT_TRACE_CHECKS
   kit session start s3 stub --via pty --cmd "sh '$stub'") >"$T/o" 2>&1
  expect_code "pty: start exits 0" 0 $?
  kit session stop s3 >"$T/o" 2>&1
  expect_line "pty: the skip line" '^terminal	pty-not-yet$' "$raw/skipped.tsv"
  if [ ! -e "$raw/terminal.cast" ]; then pass "pty: no cast file"; else fail "pty: no cast file" "file exists"; fi
else
  echo "skip: pty: the backend tool is missing"
fi

done_tests
