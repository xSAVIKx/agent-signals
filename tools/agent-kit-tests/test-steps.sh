# shellcheck shell=sh
# The test-session steps (probes/agent/steps/session-step.sh) with the stub
# agent as a fake claude, on each backend whose tool is installed. A
# backend whose tool is missing prints "skip:" and its cases do not run.
. "$ROOT/tools/agent-kit-tests/lib.sh"
. "$ROOT/tools/agent-kit-tests/core-lib.sh"
. "$ROOT/tools/agent-kit-tests/steps-lib.sh"

# A claude process that the kit did not start. The step must not count it.
HOME=$H "$T/other/claude" &
other=$!
bg_pid "$other"

kitx start --out "$D" >"$T/log" 2>&1
expect_code "kit start exits 0" 0 $?
run=$(run_of "$D")

# The steps are in the plan now: their scripts exist.
kitx plan >"$T/plan" 2>&1
for via in tmux pty; do
  have "$via" || continue
  expect_line "the plan lists permission-claude@$via" "^step: permission-claude@$via needs=login " "$T/plan"
done

ran=
for via in tmux pty; do
  if ! have "$via"; then
    echo "skip: $via: the backend tool is missing"
    continue
  fi
  ran=$via
  # test_permission_step_on_<via>. The stub asks the trust question
  # first, so that the step uses the "pre" pairs of steps.tsv.
  stub_set STUB_TRUST=yes
  t0=$(date +%s)
  kitx step "permission-claude@$via" >"$T/step" 2>&1
  rc=$?
  t1=$(date +%s)
  expect_code "$via: the permission step exits 0" 0 "$rc"
  expect_line "$via: the permission step is ok" "^step: permission-claude@$via ok$" "$T/step"
  expect_line "$via: the step prints its stages" "^kit: permission-claude@$via: wait for the dialog|^kit: permission-claude@$via: send the prompt" "$T/step"
  f=$run/$(last_file)
  case $f in
    *-permission-claude@"$via".txt) pass "$via: the step file has its name" ;;
    *) fail "$via: the step file has its name" "$f" ;;
  esac
  expect_line "$via: the file has the idle screen" '^################ screen: idle$' "$f"
  expect_line "$via: the file has the dialog screen" '^################ screen: dialog$' "$f"
  expect_line "$via: the file has the after screen" '^################ screen: after$' "$f"
  expect_line "$via: the dialog screen shows the dialog" '^Do you want to create agent-signals-test\.txt\?$' "$f"
  expect_line "$via: the answer Escape closed the dialog" '^no file$' "$f"
  expect_line "$via: the step answered the trust question" 'pre answer [0-9]+: Down' "$f"
  expect_line "$via: the file has the guided step" '^agent-signals guided step: permission, ' "$f"
  expect_line "$via: the watch counts only the session agent" '^processes: claude=1$' "$f"
  expect_no_line "$via: the watch does not count the other claude" "^claude +$other " "$f"
  expect_no_line "$via: the watch does not count the orchestrator" '^claude +[0-9]+ .*/orch/claude' "$f"
  expect_line "$via: the step file has the session pid" '^claude +[0-9]+ ' "$f"
  left=$(pids_run)
  if [ -z "$left" ]; then pass "$via: no pid of pids/ runs after the step"; else fail "$via: no pid of pids/ runs after the step" "$left"; fi
  if [ -d "$run/work/permission-claude-$via" ]; then fail "$via: the work folder is deleted" "it exists"; else pass "$via: the work folder is deleted"; fi
  echo "info: $via: the permission step took $((t1 - t0)) s"
  if [ "$rc" != 0 ]; then show "$T/step"; show "$f"; fi
done

# test_no_dialog_is_not_a_failure: a stub that never shows a dialog.
if [ -n "$ran" ]; then
  stub_set STUB_DIALOG=no
  WATCH=4 kitx step "permission-claude@$ran" >"$T/step" 2>&1
  expect_code "no dialog: the step exits 0" 0 $?
  expect_line "no dialog: the step is ok no-dialog" "^step: permission-claude@$ran ok no-dialog$" "$T/step"
  f=$run/$(last_file)
  expect_line "no dialog: the file keeps the last screen" '^################ screen: last$' "$f"
  expect_line "no dialog: the file has the result" '^result: ok no-dialog$' "$f"
  expect_line "no dialog: the manifest has the reason" "^step	permission-claude	$ran	ok	.*	no-dialog$" "$run/manifest.tsv"

  # The other kinds run with the same script.
  stub_set
  kitx step "new-chat-claude@$ran" >"$T/step" 2>&1
  expect_code "new-chat: the step exits 0" 0 $?
  expect_line "new-chat: the after screen shows the clear" '^cleared$' "$run/$(last_file)"
  kitx step "interrupt-claude@$ran" >"$T/step" 2>&1
  expect_code "interrupt: the step exits 0" 0 $?
  expect_line "interrupt: the file has the busy screen" '^################ screen: busy$' "$run/$(last_file)"
  expect_line "interrupt: Escape stopped the work" '^interrupted$' "$run/$(last_file)"
  kitx step "resume-claude@$ran" >"$T/step" 2>&1
  expect_code "resume: the step exits 0" 0 $?
  expect_line "resume: the new start has the resume argument" '^continued$' "$run/$(last_file)"
  kitx check >"$T/check" 2>&1
  expect_code "kit check passes after the session steps" 0 $?
  grep '^check: ' "$T/check" | grep -v '^check: ok$' | sed 's/^/  /'
fi

# A backend that is not for this OS skips.
kitx step permission-claude@psmux >"$T/step" 2>&1
expect_code "psmux on Unix skips" 3 $?
expect_line "psmux on Unix prints skip" '^step: permission-claude@psmux skip ' "$T/step"

done_tests
