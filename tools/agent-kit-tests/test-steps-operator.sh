# shellcheck shell=sh
# The first-run step, the operator step (real-session) and the paths of
# the release kit.
. "$ROOT/tools/agent-kit-tests/lib.sh"
. "$ROOT/tools/agent-kit-tests/core-lib.sh"
. "$ROOT/tools/agent-kit-tests/steps-lib.sh"

kitx start --out "$D" >"$T/log" 2>&1
expect_code "kit start exits 0" 0 $?
run=$(run_of "$D")

# test_real_session_asks_first
kitx step real-session-agy@operator >"$T/step" 2>&1
expect_code "real-session asks first: exit 4" 4 $?
expect_line "real-session asks first: an operator line" '^operator: start agy in a real terminal' "$T/step"
expect_line "real-session asks first: the next command" '^operator: the agent then runs: kit step real-session-agy@operator --ready$' "$T/step"
expect_line "real-session asks first: the result line" '^step: real-session-agy@operator operator ask$' "$T/step"
expect_no_line "real-session asks first: no step line in the manifest" '^step	real-session-agy	' "$run/manifest.tsv"

# --ready with no session of agy: the kit asks again.
kitx step real-session-agy@operator --ready >"$T/step" 2>&1
expect_code "real-session with no session: exit 4" 4 $?
expect_line "real-session with no session: the reason" '^step: real-session-agy@operator operator no-session$' "$T/step"

# test_real_session_ready: one agy that the test starts, outside the kit,
# counts. An agy below the orchestrator and an agy in pids/ do not count.
HOME=$H "$T/other/agy" &
op=$!
bg_pid "$op"
HOME=$H "$T/other/agy" &
kp=$!
bg_pid "$kp"
(. "$ROOT/probes/agent/lib.sh" && kit_add_pid "$run" "$kp" "session test agent")
(export ORCH_CHILD="$T/other/agy" ORCH_CHILD_PID="$T/orch-child" && WATCH=3 kitx step real-session-agy@operator --ready) >"$T/step" 2>&1
rc=$?
expect_code "real-session ready: exit 0" 0 "$rc"
expect_line "real-session ready: ok" '^step: real-session-agy@operator ok$' "$T/step"
f=$run/$(last_file)
expect_line "real-session ready: the file has the guided step" '^agent-signals guided step: permission, ' "$f"
expect_line "real-session ready: one agy counts" '^processes: agy=1$' "$f"
expect_line "real-session ready: the agy of the operator counts" "^agy +$op " "$f"
expect_no_line "real-session ready: the agy in pids/ does not count" "^agy +$kp " "$f"
oc=$(cat "$T/orch-child" 2>/dev/null)
if [ -n "$oc" ]; then
  expect_no_line "real-session ready: the agy below the orchestrator does not count" "^agy +$oc " "$f"
else
  fail "real-session ready: the agy below the orchestrator does not count" "the orchestrator started no child"
fi
[ "$rc" = 0 ] || show "$T/step"
kill "$kp" "$op" 2>/dev/null
rm -f "$run/pids/$kp"

# test_first_run_step: the stub agent as claude, on tmux, with no login.
if command -v tmux >/dev/null 2>&1; then
  stub_set
  kitx step first-run-claude@tmux >"$T/step" 2>&1
  rc=$?
  expect_code "first-run: exit 0" 0 "$rc"
  expect_line "first-run: ok" '^step: first-run-claude@tmux ok$' "$T/step"
  f=$run/$(last_file)
  expect_line "first-run: the file has the screen after 5 s" '^################ file: 01-after-5s\.screen$' "$f"
  expect_line "first-run: the screen shows the stub" '^stub idle$' "$f"
  expect_line "first-run: the file has the processes after 20 s" '^################ file: 02-after-20s\.ps$' "$f"
  if [ -d "$run/scenario" ]; then fail "first-run: the throwaway folder is deleted" "$(ls -A "$run/scenario")"; else pass "first-run: the throwaway folder is deleted"; fi
  [ "$rc" = 0 ] || show "$T/step"
else
  echo "skip: first-run: no tmux"
fi
kitx check >"$T/check" 2>&1
expect_code "kit check passes after the operator steps" 0 $?
grep '^check: ' "$T/check" | grep -v '^check: ok$' | sed 's/^/  /'

# test_archive_has_no_copy_login: the release kit from tools/kit-paths.txt.
KIT_ARCHIVE_WORKTREE=1 sh "$ROOT/tools/kit-archive.sh" tar.gz "$T/kit.tar.gz" 0.0.0-test >"$T/log" 2>&1
expect_code "the kit archive builds" 0 $?
mkdir "$T/kit"
tar -xzf "$T/kit.tar.gz" -C "$T/kit"
K=$T/kit/agent-signals-kit
if grep -rlE '(^|[^A-Za-z0-9_])copy_login[[:space:]]*\(\)|function[[:space:]]+copy_login|def[[:space:]]+copy_login' "$K" >"$T/hits"; then
  fail "no file of the kit defines copy_login" "$(tr '\n' ' ' <"$T/hits")"
else
  pass "no file of the kit defines copy_login"
fi
if [ -e "$K/scenarios/login.sh" ]; then fail "the kit has no scenarios/login.sh" "it exists"; else pass "the kit has no scenarios/login.sh"; fi
for p in scenarios/lib.sh scenarios/first-run.sh scenarios/conpty.py scenarios/first-run-windows.py \
  scenarios/first-run-windows.ps1 tools/check-probe-output.sh tools/scrub.sh probes/agent/steps/session-step.sh \
  probes/agent/steps/first-run.sh probes/agent/steps/real-session.sh; do
  expect_file "the kit has $p" "$K/$p"
done
# The control: the work tree defines copy_login, so the search can find it.
expect_line "the control: scenarios/login.sh defines copy_login" '^copy_login\(\)' "$ROOT/scenarios/login.sh"

# A kit with no scenario files skips the first-run step.
kit_copy "$T/kc"
mkdir -m 0700 "$T/kc-out"
(cd "$T/kc-out" && HOME=$H PATH="$B:$PATH" sh "$T/kc/probes/agent/kit.sh" start --out "$T/kc-out") >"$T/log" 2>&1
(cd "$T/kc-out" && HOME=$H PATH="$B:$PATH" sh "$T/kc/probes/agent/kit.sh" step first-run-claude@tmux </dev/null) >"$T/step" 2>&1
expect_code "first-run with no scenario: exit 3" 3 $?
expect_line "first-run with no scenario: skip needs-scenario" '^step: first-run-claude@tmux skip needs-scenario$' "$T/step"

done_tests
