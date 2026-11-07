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
  # The watch ends before the session stops, and it ends early.
  section "$f" '^processes after the step:' '^### 1\.' >"$T/sec"
  expect_line "$via: the session runs in the after snapshot" '^claude +[0-9]+ ' "$T/sec"
  expect_line "$via: the stop file ended the watch" '^watch: the stop file ended the watch' "$f"
  section "$f" '^### 1\.' '^### 2\.' >"$T/sec"
  # The scrub hides the file name. stub-work.txt has 5 bytes.
  expect_line "$via: section 1 has the file of the agent in the work folder" '^claude 5 /work/example' "$T/sec"
  section "$f" '^### 2\.' '^### 3\.' >"$T/sec"
  expect_line "$via: section 2 has the file that the agent holds open" '^> .*stub\.jsonl' "$T/sec"
  section "$f" '^### 3\.' '^### 4\.' >"$T/sec"
  expect_line "$via: section 3 has a record of the folder that came at the prompt" '^== .*stub\.jsonl \(lines 0 -> 1\)' "$T/sec"
  # The watch sees the dialog: the answer waits for the hold.
  expect_line "$via: the step holds the dialog" 'the dialog shows\. Hold it for 10 s' "$f"
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

  # A step with no record does not say plain ok.
  stub_set STUB_RECORDS=no
  WATCH=4 kitx step "permission-claude@$ran" >"$T/step" 2>&1
  expect_code "no records: the step exits 0" 0 $?
  expect_line "no records: the step is ok no-records" "^step: permission-claude@$ran ok no-records$" "$T/step"

  # With --files-of-pids, the watch does not walk ~/.claude/projects: a
  # fake find logs its folders.
  real_find=$(command -v find)
  cat >"$B/find" <<EOF
#!/bin/sh
echo "\$1" >>"$T/find.log"
exec "$real_find" "\$@"
EOF
  chmod +x "$B/find"
  stub_set
  WATCH=4 kitx step "permission-claude@$ran" >"$T/step" 2>&1
  expect_code "no tree walk: the step exits 0" 0 $?
  rm -f "$B/find"
  expect_line "no tree walk: the watch reads its scope" '/work/permission-claude-' "$T/find.log"
  expect_no_line "no tree walk: the watch does not read all projects" '/\.claude/projects$' "$T/find.log"

  # A real welcome box: the screen shows no display name or organisation.
  cp "$H/.claude.json" "$T/claude.json"
  echo '{"oauthAccount": {"displayName": "Alice Example", "organizationName": "Acme Corp"}}' >"$H/.claude.json"
  stub_set 'STUB_WELCOME="Acme Corp"'
  WATCH=4 kitx step "permission-claude@$ran" >"$T/step" 2>&1
  expect_code "welcome box: the step exits 0" 0 $?
  f=$run/$(last_file)
  expect_no_line "welcome box: the organisation is not in the file" 'Acme Corp' "$f"
  expect_line "welcome box: the line is blank" '^<blanked by the kit>$' "$f"
  expect_line "welcome box: the file says so" '^screens: the kit blanks each welcome box line' "$f"
  cp "$T/claude.json" "$H/.claude.json"

  # An agent that ends is a failure. After C-c at the prompt, no dialog
  # can come.
  stub_set STUB_EXIT=yes
  WATCH=4 kitx step "permission-claude@$ran" >"$T/step" 2>&1
  expect_code "agent ended: the step exits 1" 1 $?
  expect_line "agent ended: the step is fail agent-ended" "^step: permission-claude@$ran fail agent-ended$" "$T/step"

  # A missed busy screen is a failure: no-dialog is only for permission.
  stub_set STUB_BUSY=no
  WATCH=4 kitx step "interrupt-claude@$ran" >"$T/step" 2>&1
  expect_code "no busy: the step exits 1" 1 $?
  expect_line "no busy: the step is fail no-busy" "^step: interrupt-claude@$ran fail no-busy$" "$T/step"

  # new-chat needs a screen with no prompt text.
  stub_set STUB_KEEP=yes
  WATCH=4 kitx step "new-chat-claude@$ran" >"$T/step" 2>&1
  expect_code "prompt stays: the step exits 1" 1 $?
  expect_line "prompt stays: the step is fail prompt-on-screen" "^step: new-chat-claude@$ran fail prompt-on-screen$" "$T/step"

  # A box that loses the text: the step clears it and types again, one time.
  stub_set STUB_LOSE=30 "STUB_LOG=$T/lose.log"
  rm -f "$T/lose.log"
  WATCH=8 kitx step "permission-claude@$ran" >"$T/step" 2>&1
  expect_code "a lost prompt: the step exits 0" 0 $?
  f=$(ls -t "$(run_of "$D")"/*permission-claude* | head -n 1)
  expect_line "a lost prompt: the log says so" 'the prompt is not on the screen' "$f"
  expect_no_line "a lost prompt: no step ends with no dialog" 'no-dialog' "$T/step"

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
  # The failed steps of this file have files too. kit check reads them all.
  kitx check >"$T/check" 2>&1
  expect_code "kit check passes after the session steps" 0 $?
  grep '^check: ' "$T/check" | grep -v '^check: ok$' | sed 's/^/  /'
fi

# A watch that fails is a failure. The fake run.sh of a kit copy prints the
# start line, and then does what its mode says.
if [ -n "$ran" ]; then
  kit_copy "$T/kw"
  cat >"$T/kw/probes/run.sh" <<'EOF'
#!/bin/sh
echo "kit: watch starts, 1 s"
case $(cat "$WATCH_MODE") in
  hang) while :; do sleep 1; done ;;
  exit) exit 1 ;;
esac
exit 0
EOF
  export WATCH_MODE="$T/watch-mode"
  stub_set
  for m in hang:watch-timeout exit:watch-exit-1 nofile:no-guided; do
    echo "${m%:*}" >"$WATCH_MODE"
    KITSH=$T/kw/probes/agent/kit.sh WATCH=2 kitx step "permission-claude@$ran" >"$T/step" 2>&1
    expect_code "watch ${m%:*}: the step exits 1" 1 $?
    expect_line "watch ${m%:*}: the step is fail ${m#*:}" "^step: permission-claude@$ran fail ${m#*:}$" "$T/step"
  done
fi

# An agent with no measured screens skips before it starts a session.
printf '#!/bin/sh\nexit 0\n' >"$B/cursor-agent"
chmod +x "$B/cursor-agent"
kitx step permission-cursor@tmux >"$T/step" 2>&1
expect_code "cursor skips" 3 $?
expect_line "cursor skips as unmeasured" '^step: permission-cursor@tmux skip unmeasured$' "$T/step"

# The new options of the guided step.
sh "$ROOT/probes/run.sh" --guided permission claude --scope-new relative/path >"$T/o" 2>&1 </dev/null
expect_code "--scope-new with a relative path is bad use" 2 $?
expect_line "--scope-new names the reason" "needs an absolute path" "$T/o"
sh "$ROOT/probes/run.sh" --guided permission claude --stop-file >"$T/o" 2>&1 </dev/null
expect_code "--stop-file with no file is bad use" 2 $?
expect_line "--stop-file names the reason" "needs a file" "$T/o"

# A backend that is not for this OS skips.
kitx step permission-claude@psmux >"$T/step" 2>&1
expect_code "psmux on Unix skips" 3 $?
expect_line "psmux on Unix prints skip" '^step: permission-claude@psmux skip ' "$T/step"

done_tests
