#!/bin/sh
# Checks a guided step of the kit with a stub agy process and a fake home
# folder: the step counts the stub and not the kit, it lists the changed
# files, the new transcript records and the agy summaries status, and it
# stops when no agent session runs. It also runs the step through the
# one-line start, whose command line holds the agent name.
# Each step watches for 30 s, so the test takes about 70 s. The checks
# look for the pid of the stub, not for a count, because a machine can
# run other processes named agy. The file names must not hold the host
# name, because the scrub changes it.
# Run: sh tools/test-guided-step.sh
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
stub_pid=
cleanup() {
  [ -n "$stub_pid" ] && kill "$stub_pid" 2>/dev/null
  rm -rf "$tmp"
}
trap cleanup EXIT INT TERM

fake=$tmp/home
state=$fake/.gemini/antigravity-cli
mkdir -p "$state/presence" "$state/brain/b1/.system_generated/logs" "$tmp/bin" "$tmp/work"

# The summaries database of fact 045, with one running conversation.
if command -v python3 >/dev/null 2>&1; then
  python3 -I - "$state/conversation_summaries.db" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.execute("create table conversation_summaries (conversation_id text,"
          " status text, not_fully_idle numeric, step_count integer,"
          " last_modified_time datetime)")
c.execute("insert into conversation_summaries values"
          " ('c1', 'CASCADE_RUN_STATUS_RUNNING', 1, 2, '2026-11-01')")
c.commit()
PY
fi

# The stub agent: a process named agy that writes a presence lock and a
# transcript record every second.
cat >"$tmp/bin/agy" <<'EOF'
#!/bin/sh
s=$HOME/.gemini/antigravity-cli
while :; do
  touch "$s/presence/stub.lock"
  echo '{"type":"USER_INPUT"}' >>"$s/brain/b1/.system_generated/logs/transcript.jsonl"
  sleep 1
done
EOF
chmod +x "$tmp/bin/agy"

# The kit archive, as the release makes it.
mkdir -p "$tmp/kit/agent-signals-kit"
(cd "$root" && tar -cf - probes tools/scrub.sh tools/scrub.ps1) | (cd "$tmp/kit/agent-signals-kit" && tar -xf -)
(cd "$tmp/kit" && tar -czf "$tmp/kit.tar.gz" agent-signals-kit)

fail=0
check() {
  if grep -Eq -- "$2" "$3"; then
    echo "pass: $1"
  else
    echo "fail: $1: no line matches: $2"
    fail=1
  fi
}

# 1. No session runs: the step stops, also through the one-line start.
cd "$tmp/work" || exit 1
out=$(cat "$root/probes/kit.sh" | HOME=$fake AGENT_SIGNALS_URL="file://$tmp/kit.tar.gz" sh -s -- --guided permission agy 2>&1)
code=$?
if [ "$code" = 2 ] && echo "$out" | grep -q "no session of agy runs"; then
  echo "pass: the step stops when no agy session runs"
else
  echo "fail: the step did not stop with no agy session (exit $code)"
  echo "$out" | tail -n 5
  fail=1
fi

HOME=$fake "$tmp/bin/agy" &
stub_pid=$!
sleep 1

# 2. The step in a clone.
printf '\n' | HOME=$fake sh "$root/probes/run.sh" --guided permission agy >/dev/null 2>&1
f=$(ls agent-signals-probe-*.txt 2>/dev/null | head -n 1)
if [ -z "$f" ]; then
  echo "fail: the step in a clone wrote no file"
  fail=1
else
  check "the step counts the stub" "^agy +$stub_pid " "$f"
  check "the step lists the processes after the step" '^processes after the step:$' "$f"
  check "the step lists a changed file" '^agy [0-9]+ .*presence/stub\.lock$' "$f"
  check "the step lists the new transcript records" 'USER_INPUT' "$f"
  if command -v python3 >/dev/null 2>&1; then
    check "the step reads the agy summaries status" '^t=0s: CASCADE_RUN_STATUS_RUNNING 1 2$' "$f"
  fi
  [ -n "${KEEP:-}" ] && cp "$f" "$KEEP"; rm -f "$f"
fi

# 3. The step through the one-line start: the kit must not count itself.
cat "$root/probes/kit.sh" | HOME=$fake AGENT_SIGNALS_URL="file://$tmp/kit.tar.gz" sh -s -- --guided permission agy >/dev/null 2>&1
f=$(ls agent-signals-probe-*.txt 2>/dev/null | head -n 1)
if [ -z "$f" ]; then
  echo "fail: the step through the one-line start wrote no file"
  fail=1
else
  check "the one-line start counts the stub" "^agy +$stub_pid " "$f"
  if grep -q '^agy .* sh -s' "$f"; then
    echo "fail: the one-line start counted the kit as agy"
    fail=1
  else
    echo "pass: the one-line start does not count the kit"
  fi
  [ -n "${KEEP:-}" ] && cp "$f" "$KEEP"; rm -f "$f"
fi

exit "$fail"
