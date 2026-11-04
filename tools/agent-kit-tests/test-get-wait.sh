# shellcheck shell=sh
# The one-line start keeps the kit with --get, and a guided step runs with
# no key press (--wait), watches only some pids (--pids) and shows only
# their files (--files-of-pids, --scope).
# Each guided step watches for 1 to 4 s, so the file takes about 2 min.
. "$ROOT/tools/agent-kit-tests/lib.sh"

# The kit archive, as the release makes it.
mkdir -p "$T/kit/agent-signals-kit"
(cd "$ROOT" && tar -cf - probes tools/scrub.sh tools/scrub.ps1) | (cd "$T/kit/agent-signals-kit" && tar -xf -)
(cd "$T/kit" && tar -czf "$T/kit.tar.gz" agent-signals-kit)

# 1. --get keeps the kit and runs nothing else.
mkdir "$T/get"
(cd "$T/get" && AGENT_SIGNALS_URL="file://$T/kit.tar.gz" sh "$ROOT/probes/kit.sh" --get "$T/k" >"$T/out" 2>"$T/err")
expect_code "get exits 0" 0 $?
if [ -f "$T/k/agent-signals-kit/probes/run.sh" ]; then
  pass "get keeps the kit"
else
  fail "get keeps the kit" "no $T/k/agent-signals-kit/probes/run.sh"
fi
last=$(tail -n 1 "$T/out")
if [ "$last" = "kit: ready $T/k/agent-signals-kit" ]; then
  pass "get prints the folder"
else
  fail "get prints the folder" "last line: $last"
fi
if ls "$T/get"/agent-signals-probe-* >/dev/null 2>&1; then
  fail "get runs no probe" "a probe file exists"
else
  pass "get runs no probe"
fi
(cd "$T/get" && AGENT_SIGNALS_URL="file://$T/kit.tar.gz" sh "$ROOT/probes/kit.sh" --get "$T/k" >"$T/out" 2>&1)
expect_code "get does not overwrite a kit" 2 $?
expect_line "get names the folder that exists" 'already exists' "$T/out"
cat "$ROOT/probes/kit.sh" | (cd "$T/get" && AGENT_SIGNALS_URL="file://$T/kit.tar.gz" sh -s -- --get "$T/k2" >"$T/out" 2>/dev/null)
expect_line "get works through the one-line start" "^kit: ready $T/k2/agent-signals-kit\$" "$T/out"

# 2. Bad values of --wait, --pids and AGENT_SIGNALS_WATCH.
run=$ROOT/probes/run.sh
(cd "$T" && sh "$run" --guided permission agy --wait 0 </dev/null >"$T/out" 2>&1)
expect_code "wait 0 is bad use" 2 $?
expect_line "wait 0 is bad use: the reason" '^kit: --wait' "$T/out"
(cd "$T" && sh "$run" --guided permission agy --wait 601 </dev/null >"$T/out" 2>&1)
expect_code "wait 601 is bad use" 2 $?
expect_line "wait 601 is bad use: the reason" '^kit: --wait' "$T/out"
(cd "$T" && sh "$run" --guided permission agy --wait x </dev/null >"$T/out" 2>&1)
expect_code "wait x is bad use" 2 $?
expect_line "wait x is bad use: the reason" '^kit: --wait' "$T/out"
(cd "$T" && sh "$run" --guided permission agy --pids "$T/no-such" </dev/null >"$T/out" 2>&1)
expect_code "a missing pids file is bad use" 2 $?
expect_line "a missing pids file: the reason" '^kit: --pids' "$T/out"
(cd "$T" && AGENT_SIGNALS_WATCH=0 sh "$run" --guided permission agy </dev/null >"$T/out" 2>&1)
expect_code "AGENT_SIGNALS_WATCH=0 is bad use" 2 $?
expect_line "AGENT_SIGNALS_WATCH=0: the reason" '^kit: AGENT_SIGNALS_WATCH' "$T/out"

# 3. Stub agents in a fake home folder. A stub appends a record to the
# file $HELD, which it holds open, every second.
mkdir -p "$T/home" "$T/bin"
cat >"$T/bin/agy" <<'EOF'
#!/bin/sh
if [ -n "${HELD:-}" ]; then
  mkdir -p "$(dirname "$HELD")"
  exec 3>>"$HELD"
fi
while :; do
  [ -n "${HELD:-}" ] && echo "{\"type\":\"${KIND:-HELD}_RECORD\"}" >&3
  sleep 1
done
EOF
cp "$T/bin/agy" "$T/bin/codex"
cp "$T/bin/agy" "$T/bin/tmux"
cp "$T/bin/agy" "$T/bin/orch"
chmod +x "$T/bin/agy" "$T/bin/codex" "$T/bin/tmux" "$T/bin/orch"
state=$T/home/.gemini/antigravity-cli
HOME=$T/home "$T/bin/agy" &
a1=$!
bg_pid "$a1"
HOME=$T/home "$T/bin/agy" &
a2=$!
bg_pid "$a2"
echo "$a1" >"$T/pids"
mkdir "$T/pids.d"
: >"$T/pids.d/$a2"
sleep 1

# guided DIR ARGS: run a guided step in the new folder DIR with stdin
# /dev/null. The output is in DIR.out, and $f is the file of the step.
guided() {
  _d=$1
  shift
  mkdir -p "$_d"
  (cd "$_d" && HOME=$T/home sh "$run" --guided permission "$@" </dev/null >"$_d.out" 2>&1)
  _c=$?
  f=$(ls "$_d"/agent-signals-probe-*.txt 2>/dev/null | head -n 1)
  return "$_c"
}

# --wait reads no key, also with stdin /dev/null. A machine can run other
# agy processes, so the check looks for the pids of the stubs.
start=$(date +%s)
guided "$T/w1" agy --wait 2
expect_code "the step with --wait exits 0" 0 $?
took=$(($(date +%s) - start))
if [ "$took" -le 120 ]; then pass "the step with --wait ends in 120 s"; else fail "the step with --wait ends in 120 s" "took $took s"; fi
if [ -z "$f" ]; then
  fail "the step with --wait writes a file" "no file"
else
  expect_line "wait counts the first stub" "^agy +$a1 " "$f"
  expect_line "wait counts the second stub" "^agy +$a2 " "$f"
  expect_line "wait gives the watch length" '^watch: 2 s$' "$f"
fi
expect_no_line "wait asks for no key" 'push Enter' "$T/w1.out"

# --pids FILE counts only the pids in the file and their children.
guided "$T/w2" agy --wait 1 --pids "$T/pids"
expect_code "the step with --pids exits 0" 0 $?
if [ -z "$f" ]; then
  fail "the step with --pids writes a file" "no file"
else
  expect_line "pids counts one agy" '^processes: agy=1$' "$f"
  expect_line "pids counts the stub in the file" "^agy +$a1 " "$f"
  expect_no_line "pids does not count the other stub" "^agy +$a2 " "$f"
fi

# A pids folder of a kit run (one file for each pid) works as well.
guided "$T/w3" agy --pids "$T/pids.d" --wait 1
expect_code "the step with a pids folder exits 0" 0 $?
if [ -z "$f" ]; then
  fail "the step with a pids folder writes a file" "no file"
else
  expect_line "a pids folder counts one agy" '^processes: agy=1$' "$f"
  expect_line "a pids folder counts its stub" "^agy +$a2 " "$f"
fi

# A pids file with no running agent: the step stops.
echo 999999 >"$T/dead"
guided "$T/w4" agy --wait 1 --pids "$T/dead"
expect_code "a pids file with no session stops the step" 2 $?

# 4. A tmux server keeps the argv of its client, so the codex pattern
# matches it. With --pids, it does not count.
HOME=$T/home "$T/bin/tmux" -S x new-session codex &
tm=$!
bg_pid "$tm"
HOME=$T/home "$T/bin/codex" &
c1=$!
bg_pid "$c1"
echo "$c1" >"$T/pids.codex"
sleep 1
guided "$T/t1" codex --wait 1
if [ -n "$f" ] && grep -Eq "^codex +$tm " "$f"; then
  pass "the codex pattern matches the tmux argv"
else
  fail "the codex pattern matches the tmux argv" "so the next check proves nothing"
fi
guided "$T/t2" codex --wait 1 --pids "$T/pids.codex"
expect_code "the codex step with --pids exits 0" 0 $?
if [ -z "$f" ]; then
  fail "the codex step with --pids writes a file" "no file"
else
  expect_line "pids counts one codex" '^processes: codex=1$' "$f"
  expect_line "pids counts the codex stub" "^codex +$c1 " "$f"
  expect_no_line "pids does not count the tmux server" "^codex +$tm " "$f"
fi

# 5. In the background, with --files-of-pids and --scope: the caller
# drives the session in the watch. The records of an orchestrator in the
# same home folder do not show.
HOME=$T/home HELD=$state/held/h.jsonl "$T/bin/agy" &
a3=$!
bg_pid "$a3"
HOME=$T/home HELD=$state/brain/o/o.jsonl KIND=ORCH "$T/bin/orch" &
o1=$!
bg_pid "$o1"
echo "$a3" >"$T/pids.bg"
mkdir -p "$state/brain/s" "$T/bg"
sleep 1
(cd "$T/bg" && HOME=$T/home sh "$run" --guided permission agy --wait 4 --pids "$T/pids.bg" \
  --files-of-pids --scope "$state/brain/s" --out "$T/bg.txt" </dev/null >"$T/bg.out" 2>&1) &
bg=$!
# The caller does the action after the "kit: watch starts" line.
n=0
until grep -q '^kit: watch starts' "$T/bg.out" 2>/dev/null || [ "$n" -ge 120 ]; do
  sleep 1
  n=$((n + 1))
done
echo '{"type":"SESSION_RECORD"}' >>"$state/brain/s/s.jsonl"
wait "$bg"
expect_code "the step in the background exits 0" 0 $?
if [ -f "$T/bg.txt" ]; then
  pass "out writes the file"
  expect_line "scope shows a file in the scope" 'brain/s/s\.jsonl' "$T/bg.txt"
  expect_line "scope shows a file that a counted pid holds open" 'held/h\.jsonl' "$T/bg.txt"
  expect_no_line "scope hides the orchestrator file" 'brain/o/' "$T/bg.txt"
  if command -v python3 >/dev/null 2>&1; then
    expect_line "scope shows the session records" 'SESSION_RECORD' "$T/bg.txt"
    expect_line "scope shows the records of the open file" 'HELD_RECORD' "$T/bg.txt"
    expect_no_line "scope hides the orchestrator records" 'ORCH_RECORD' "$T/bg.txt"
  fi
else
  fail "out writes the file" "no $T/bg.txt"
fi
if ls "$T/bg"/agent-signals-probe-* >/dev/null 2>&1; then
  fail "out writes no other file" "a file in the current folder"
else
  pass "out writes no other file"
fi

# 6. An open pipe on stdin: the kit does not wait for a key. The writer
# of the pipe runs for one hour. A read would wait for it, so the kit
# must end while the writer still runs.
mkfifo "$T/fifo"
sleep 3600 >"$T/fifo" &
sp=$!
bg_pid "$sp"
mkdir "$T/p1"
(cd "$T/p1" && HOME=$T/home AGENT_SIGNALS_WATCH=2 sh "$run" --guided permission agy --pids "$T/pids" <"$T/fifo" >"$T/p1.out" 2>&1)
expect_code "a pipe on stdin: the step exits 0" 0 $?
if kill -0 "$sp" 2>/dev/null; then pass "a pipe on stdin: no wait for Enter"; else fail "a pipe on stdin: no wait for Enter" "the step ended after the writer"; fi
expect_line "a pipe on stdin: the kit says so" 'no terminal to push Enter' "$T/p1.out"
expect_line "AGENT_SIGNALS_WATCH sets the watch" '^watch: 2 s$' "$(ls "$T/p1"/agent-signals-probe-*.txt | head -n 1)"

# 7. The probes with an open pipe on stdin. On macOS, the terminal
# question: with no tty and no value, the answer is no.
mkdir "$T/m1" "$T/m2"
(cd "$T/m1" && HOME=$T/home sh "$run" <"$T/fifo" >/dev/null 2>&1)
expect_code "a pipe on stdin: the probes exit 0" 0 $?
if kill -0 "$sp" 2>/dev/null; then pass "a pipe on stdin: the probes do not wait"; else fail "a pipe on stdin: the probes do not wait" "the probes ended after the writer"; fi
kill "$sp" 2>/dev/null
if [ "$(uname -s)" = Darwin ]; then
  expect_line "no tty skips the terminal probe" '^################ terminals: skipped, no terminal' "$(ls "$T/m1"/agent-signals-probe-*.txt | head -n 1)"
  (cd "$T/m2" && HOME=$T/home AGENT_SIGNALS_TERMINALS=no sh "$run" </dev/null >/dev/null 2>&1)
  expect_line "AGENT_SIGNALS_TERMINALS=no skips the terminal probe" '^################ terminals: skipped by the operator' "$(ls "$T/m2"/agent-signals-probe-*.txt | head -n 1)"
fi

done_tests
