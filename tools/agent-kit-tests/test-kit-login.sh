# shellcheck shell=sh
# scenarios/kit-login.sh: the login step of one agent in CI. A stub agent
# stands for the real agent. The tests hold no real key.
. "$ROOT/tools/agent-kit-tests/lib.sh"
. "$ROOT/tools/agent-kit-tests/core-lib.sh"

KEY='FAKE-LOGIN-KEY-0123456789'
mkdir -p "$T/bin" "$T/run" "$T/home"
# login AGENT: run the script as the workflow does.
login() {
  HOME=$T/home RUNNER_TEMP=$T/run PATH=$T/bin:$SYS_PATH KIT_KEY=${LOGIN_KEY-$KEY} \
    sh "$ROOT/scenarios/kit-login.sh" run "$1"
}
no_key_left() {
  if grep -rFq "$KEY" "$T/home" 2>/dev/null; then fail "$1" "a file holds the key"; else pass "$1"; fi
}

# A failed "codex login" counts as a failed step, and the job goes on.
cat >"$T/bin/codex" <<'STUB'
#!/bin/sh
cat >"$HOME/.codex-stdin"
exit 1
STUB
chmod +x "$T/bin/codex"
login codex >"$T/out" 2>&1
expect_code "a failed codex login exits 0, so that the next steps run" 0 $?
expect_line "the failed codex login is in the list" '^codex: ' "$T/run/kit-failed.txt"
if [ "$(cat "$T/home/.codex-stdin")" = "$KEY" ]; then
  pass "codex gets the key on stdin"
else
  fail "codex gets the key on stdin" "it does not"
fi
rm -f "$T/home/.codex-stdin" "$T/bin/codex"
expect_no_line "the output does not hold the key" "$KEY" "$T/out"

# An agent with a key and no step is a failure. The key file goes away.
rm -f "$T/run/kit-failed.txt"
login claude >"$T/out" 2>&1
expect_code "an agent that is not installed exits 0" 0 $?
expect_line "an agent with a key and no step is in the list" '^claude: ' "$T/run/kit-failed.txt"
no_key_left "no file holds the key after the step of claude"

# A step with no key is a failure, not a pass.
rm -f "$T/run/kit-failed.txt"
LOGIN_KEY='' login cursor >"$T/out" 2>&1
expect_line "a step with no key is in the list" '^cursor: ' "$T/run/kit-failed.txt"

done_tests
