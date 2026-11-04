# shellcheck shell=sh
# The leak test: the probe step runs with a fake home that holds login
# files, settings, pid files and transcripts with known secret strings
# (LEAK-CANARY-<n>), and with API keys in the environment. No canary may
# come out in the run folder or in the archive.
. "$ROOT/tools/agent-kit-tests/lib.sh"
. "$ROOT/tools/agent-kit-tests/core-lib.sh"

# A copy of the fake home, so that the test folder holds all paths.
H=$T/home
mkdir -p "$H"
(cd "$FAKE/home" && tar -cf - .) | (cd "$H" && tar -xf -)
P=$FAKE/bin:$SYS_PATH
mkdir -m 0700 "$T/out"

# leak_env CMD...: run CMD with the fake home and the canary variables.
leak_env() {
  HOME=$H PATH=$P \
    ANTHROPIC_API_KEY=LEAK-CANARY-ENV-ANTHROPIC \
    OPENAI_API_KEY=LEAK-CANARY-ENV-OPENAI \
    CURSOR_API_KEY=LEAK-CANARY-ENV-CURSOR \
    GH_TOKEN=LEAK-CANARY-ENV-GH \
    "$@"
}

(cd "$T/out" && leak_env sh "$ROOT/probes/agent/kit.sh" start --out "$T/out") >"$T/log" 2>&1
expect_code "kit start exits 0" 0 $?
run=$(run_of "$T/out")
(cd "$T/out" && leak_env sh "$ROOT/probes/agent/kit.sh" step probe@none </dev/null) >"$T/log" 2>&1
expect_code "kit step probe@none exits 0" 0 $?
expect_line "the probe read the fake home" '^################ claude$' "$run/01-probe@none.txt"
(cd "$T/out" && leak_env sh "$ROOT/probes/agent/kit.sh" check) >"$T/log" 2>&1
expect_code "kit check passes" 0 $?
[ "$(cat "$T/log")" ] && sed 's/^/  /' "$T/log" | grep '^  check: ' | grep -v 'pass$'

if grep -rl LEAK-CANARY "$run" >"$T/hits" 2>/dev/null; then
  fail "no canary in the run folder" "$(tr '\n' ' ' <"$T/hits")"
else
  pass "no canary in the run folder"
fi
if [ -f "$run.tar.gz" ] && gzip -dc "$run.tar.gz" | grep -aq LEAK-CANARY; then
  fail "no canary in the archive" "a canary"
else
  expect_file "the archive exists" "$run.tar.gz"
fi
if grep -q LEAK-CANARY "$T/log"; then fail "no canary in the output of kit check" "a canary"; else pass "no canary in the output of kit check"; fi

done_tests
