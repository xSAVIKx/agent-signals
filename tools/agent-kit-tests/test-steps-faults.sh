# shellcheck shell=sh
# Faults during a session step, with the stub agent as a fake claude on
# one backend (tmux, else pty):
#   - SIGTERM to the "kit step" process (the tool of an orchestrator ends
#     a command that runs too long);
#   - kill -9 of the "kit step" process only;
#   - kill -9 of the process group of "kit step" (the session stays);
#   - the end of the tmux server of the session (tmux only);
#   - the shell of an orchestrator: no TERM, TERM=dumb, and LANG=C with
#     LC_ALL=POSIX;
#   - a resume step in a run with the fixture home: the stop of the first
#     session must not stop the guided watch.
# Each case checks the exit code or the manifest line, and that the next
# step runs. lib.sh fails the test when a process of the test stays.
. "$ROOT/tools/agent-kit-tests/lib.sh"
. "$ROOT/tools/agent-kit-tests/core-lib.sh"
. "$ROOT/tools/agent-kit-tests/steps-lib.sh"

via=
for v in tmux pty; do
  if have "$v"; then via=$v; break; fi
done
if [ -z "$via" ]; then
  echo "skip: the fault test: no tmux and no pty backend"
  done_tests
fi
step=permission-claude@$via
sess=permission-claude-$via

kitx start --out "$D" >"$T/log" 2>&1
expect_code "kit start exits 0" 0 $?
run=$(run_of "$D")

# lock_pid: the pid in the step lock, when a step holds it (20 s at most).
lock_pid() {
  _i=0
  while [ "$_i" -lt 80 ]; do
    _p=$(readlink "$run/.step.lock" 2>/dev/null) && [ -n "$_p" ] && { echo "$_p"; return 0; }
    sleep 0.25
    _i=$((_i + 1))
  done
  return 1
}

# wait_for FILE SECONDS: true when FILE exists in SECONDS.
wait_for() {
  _i=0
  while [ "$_i" -lt $(($2 * 4)) ]; do
    [ -e "$1" ] && return 0
    sleep 0.25
    _i=$((_i + 1))
  done
  return 1
}

# script_ends: true when the step script of RUN/.step.script ends in 20 s.
script_ends() {
  _s=$(cat "$run/.step.script" 2>/dev/null) || return 0
  _i=0
  while kill -0 "$_s" 2>/dev/null; do
    [ "$_i" -lt 80 ] || return 1
    sleep 0.25
    _i=$((_i + 1))
  done
}

# steps_of NAME: the number of manifest lines of the step NAME.
steps_of() { awk -F '\t' -v n="$1" '$1 == "step" && $2 == n' "$run/manifest.tsv" | wc -l | tr -d ' '; }

# group_kit ARGS: kitx in a new session, so that the test can end its
# process group and stay alive. Run it with "&": the exec keeps the pid of
# the background job, so that pid is the group id.
# shellcheck disable=SC2016
group_kit() {
  exec python3 -I -c 'import os, sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' \
    sh -c '. "$1"; shift; kitx "$@"' sh "$T/kitx.sh" "$@"
}
cat >"$T/kitx.sh" <<EOF
T='$T' D='$D' H='$H' B='$B' ROOT='$ROOT'
$(sed -n '/^kitx() {/,/^}/p' "$ROOT/tools/agent-kit-tests/steps-lib.sh")
EOF

# The stub stays busy after the prompt and opens no dialog, so that the
# step waits for the dialog for WATCH seconds.
stub_set STUB_DIALOG=busy

# test_sigterm_waits_for_the_step: the step ends as usual and records its
# line. The lock goes away.
n0=$(steps_of permission-claude)
WATCH=8 kitx step "$step" >"$T/step" 2>&1 &
k=$!
bg_pid "$k"
p=$(lock_pid) || fail "sigterm: the step takes the lock" "no lock"
wait_for "$run/sessions/$sess/pid" 30 || fail "sigterm: the session starts" "no pid file"
kill -TERM "$p" 2>/dev/null
wait "$k"
expect_line "sigterm: the step says that it got the signal" '^kit: the step got SIGTERM\. It ended first\.$' "$T/step"
expect_line "sigterm: the step prints its result" "^step: $step (ok|fail)" "$T/step"
if [ "$(steps_of permission-claude)" -eq $((n0 + 1)) ]; then pass "sigterm: the manifest has the step line"; else fail "sigterm: the manifest has the step line" "$(steps_of permission-claude) lines"; fi
if [ -e "$run/.step.lock" ] || [ -L "$run/.step.lock" ]; then fail "sigterm: the lock is gone" "it stays"; else pass "sigterm: the lock is gone"; fi
if [ -f "$run/sessions/$sess/stopped" ]; then pass "sigterm: the session stopped"; else fail "sigterm: the session stopped" "no stopped file"; fi

# test_kill_9_of_kit_step: the script sees that "kit step" is gone, stops
# its session and ends. The next step deletes the stale lock.
rm -f "$run/sessions/$sess/stopped" "$run/sessions/$sess/pid"
WATCH=60 kitx step "$step" >"$T/step" 2>&1 &
k=$!
bg_pid "$k"
p=$(lock_pid) || fail "kill -9: the step takes the lock" "no lock"
wait_for "$run/sessions/$sess/pid" 30 || fail "kill -9: the session starts" "no pid file"
sleep 2
kill -9 "$p" 2>/dev/null
wait "$k" 2>/dev/null
if wait_for "$run/sessions/$sess/stopped" 20; then pass "kill -9: the script stops its session"; else fail "kill -9: the script stops its session" "no stopped file in 20 s"; fi
if script_ends; then pass "kill -9: the old script ends"; else fail "kill -9: the old script ends" "it runs after 20 s"; fi
stub_set
WATCH=4 kitx step "$step" >"$T/step" 2>&1
expect_code "kill -9: the next step exits 0" 0 $?
# The case is about the stale lock, not the dialog: on a slow runner the
# 4 s wait can give "ok no-dialog".
expect_line "kill -9: the next step is ok" "^step: $step ok( |$)" "$T/step"
grep -q "^step: $step ok$" "$T/step" || { sed 's/^/  out: /' "$T/step"; f=$run/$(last_file); sed -n '/################ guided step/,/^### 1/p' "$f" | head -12 | sed 's/^/  watch: /'; }


# test_kill_9_of_the_group: the session stays with no step. The next step
# stops it and runs.
stub_set STUB_DIALOG=busy
rm -f "$run/sessions/$sess/stopped" "$run/sessions/$sess/pid"
group_kit step "$step" >"$T/step" 2>&1 &
k=$!
bg_pid "$k"
lock_pid >/dev/null || fail "group: the step takes the lock" "no lock"
wait_for "$run/sessions/$sess/pid" 30 || fail "group: the session starts" "no pid file"
sleep 2
kill -9 "-$k" 2>/dev/null
wait "$k" 2>/dev/null
if [ -f "$run/sessions/$sess/stopped" ]; then fail "group: the session stays" "it stopped"; else pass "group: the session stays"; fi
stub_set
WATCH=4 kitx step "$step" >"$T/step" 2>&1
expect_code "group: the next step exits 0" 0 $?
expect_line "group: the next step is ok" "^step: $step ok$" "$T/step"
grep -q "^step: $step ok$" "$T/step" || sed 's/^/  out: /' "$T/step"
f=$run/$(last_file)

expect_line "group: the next step stopped the old session" 'a session of an ended step stayed: stop it$' "$f"

# test_tmux_server_ends: the step fails with a reason, and stops.
if [ "$via" = tmux ]; then
  stub_set STUB_DIALOG=busy
  rm -f "$run/sessions/$sess/pid"
  WATCH=20 kitx step "$step" >"$T/step" 2>&1 &
  k=$!
  bg_pid "$k"
  lock_pid >/dev/null || fail "tmux ends: the step takes the lock" "no lock"
  wait_for "$run/sessions/$sess/pid" 30 || fail "tmux ends: the session starts" "no pid file"
  # The watch runs, so that the end of the server is a fault of a step
  # that runs, not of its start.
  _i=0
  until grep -q 'the watch runs$' "$T/step" || [ "$_i" -ge 120 ]; do sleep 0.25; _i=$((_i + 1)); done
  sock=$(cat "$run/sessions/$sess/socket" 2>/dev/null)
  if [ -n "$sock" ]; then
    tmux -S "$sock" kill-server 2>/dev/null
  else
    fail "tmux ends: the session has a socket file" "none"
  fi
  wait "$k"
  expect_code "tmux ends: the step exits 1" 1 $?
  expect_line "tmux ends: the step fails with a reason" "^step: $step fail (agent-ended|screen-failed)$" "$T/step"
else
  echo "skip: tmux ends: the backend is $via"
fi

# test_orchestrator_shell: the shell tool of an AI agent can have no TERM,
# TERM=dumb (Codex), or a C locale. The step must still work.
stub_set
for e in "-u TERM" "TERM=dumb" "LANG=C LC_ALL=POSIX"; do
  # shellcheck disable=SC2086
  (eval "export_env() { env $e \"\$@\"; }"; WATCH=4 export_env sh -c '. "$1"; shift; kitx "$@"' sh "$T/kitx.sh" step "$step") >"$T/step" 2>&1
  expect_code "env $e: the step exits 0" 0 $?
  expect_line "env $e: the step is ok" "^step: $step ok$" "$T/step"
  grep -q "^step: $step ok$" "$T/step" || { sed 's/^/  out: /' "$T/step"; f=$run/$(last_file); sed -n '/################ screen: last/,/################ log/p' "$f" | grep -v '^ *$' | tail -12 | sed 's/^/  screen: /'; }
done

# test_resume_keeps_the_watch_in_a_fixture_home: the session stop of the
# resume step stops the processes that name the throwaway home. The watch
# names it in --scope, and it must run on.
D2=$T/out2
mkdir -m 0700 "$D2"
(D=$D2; kitx start --home fixture --out "$D2") >"$T/log" 2>&1
expect_code "fixture: kit start exits 0" 0 $?
(D=$D2; WATCH=8 kitx step "resume-claude@$via") >"$T/step" 2>&1
expect_code "fixture resume: the step exits 0" 0 $?
expect_line "fixture resume: the step is ok" "^step: resume-claude@$via ok" "$T/step"
expect_no_line "fixture resume: the watch was not stopped" 'watch ended, exit (137|143)' "$T/step"

done_tests
