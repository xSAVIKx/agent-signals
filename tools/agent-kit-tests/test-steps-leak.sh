# shellcheck shell=sh
# The leak test of a session step: permission-claude@pty (or @tmux when
# the pty backend cannot run here) with the stub agent, a fake home with
# known secret strings (LEAK-CANARY-<n>), and API keys in the environment.
# The project folder of the work folder holds a transcript with a canary,
# so that the scope of the guided watch holds it. No canary may come out
# in the run folder, in the archive or in the output of the kit.
. "$ROOT/tools/agent-kit-tests/lib.sh"
. "$ROOT/tools/agent-kit-tests/core-lib.sh"
. "$ROOT/tools/agent-kit-tests/steps-lib.sh"

via=
for v in pty tmux; do
  if have "$v"; then via=$v; break; fi
done
if [ -z "$via" ]; then
  echo "skip: the session leak test: no tmux and no pty backend"
  done_tests
fi
[ "$via" = pty ] || echo "info: the pty backend cannot run here, so the leak test uses tmux"

# leak_kit ARGS: kitx with the canary variables.
leak_kit() {
  ANTHROPIC_API_KEY=LEAK-CANARY-ENV-ANTHROPIC OPENAI_API_KEY=LEAK-CANARY-ENV-OPENAI \
    GH_TOKEN=LEAK-CANARY-ENV-GH kitx "$@"
}

leak_kit start --out "$D" >"$T/log" 2>&1
expect_code "kit start exits 0" 0 $?
run=$(run_of "$D")
# The project folder that Claude Code would use for the work folder of
# the session, with a transcript that holds a canary.
key=$(printf '%s' "$run/work/permission-claude-$via" | tr -c 'A-Za-z0-9' '-')
mkdir -p "$H/.claude/projects/$key"
echo '{"type":"user","message":{"content":"LEAK-CANARY-SCOPE"}}' >"$H/.claude/projects/$key/t.jsonl"
if grep -rq LEAK-CANARY "$H"; then pass "the fake home holds canaries"; else fail "the fake home holds canaries" "none"; fi

stub_set STUB_TRUST=yes
leak_kit step "permission-claude@$via" >"$T/out" 2>&1
expect_code "the session step exits 0" 0 $?
expect_line "the session step is ok" "^step: permission-claude@$via ok" "$T/out"
leak_kit check >>"$T/out" 2>&1
expect_code "kit check passes" 0 $?
grep '^check: ' "$T/out" | grep -v '^check: ok$' | sed 's/^/  /'

if grep -rl LEAK-CANARY "$run" >"$T/hits" 2>/dev/null; then
  fail "no canary in the run folder" "$(tr '\n' ' ' <"$T/hits")"
else
  pass "no canary in the run folder"
fi
if [ ! -f "$run.tar.gz" ]; then
  fail "the archive exists" "no archive"
elif gzip -dc "$run.tar.gz" | grep -aq LEAK-CANARY; then
  fail "no canary in the archive" "a canary"
else
  pass "no canary in the archive"
fi
if grep -q LEAK-CANARY "$T/out"; then fail "no canary in the output of the kit" "a canary"; else pass "no canary in the output of the kit"; fi

done_tests
