# shellcheck shell=sh
# "kit start", "kit step" and the manifest. One real probe step, in a
# folder with a space in its path and with no stdin.
. "$ROOT/tools/agent-kit-tests/lib.sh"
. "$ROOT/tools/agent-kit-tests/core-lib.sh"

P=$FAKE/bin:$SYS_PATH
H=$T/home
mkdir -p "$H"

# The folder checks of kit start.
mkdir -m 0770 "$T/gw"
chmod 0770 "$T/gw"
(cd "$T" && HOME=$H kit start --out "$T/gw") >"$T/out" 2>&1
expect_code "a group-writable folder is bad use" 2 $?
mkdir -p "$T/repo/.git" "$T/repo/sub"
(cd "$T" && HOME=$H kit start --out "$T/repo/sub") >"$T/out" 2>&1
expect_code "a folder in a git work tree is bad use" 2 $?
mkdir -p "$H/.claude/x"
(cd "$T" && HOME=$H kit start --out "$H/.claude/x") >"$T/out" 2>&1
expect_code "a folder in ~/.claude is bad use" 2 $?
(cd "$T" && HOME=$H kit start --home other --out "$T") >"$T/out" 2>&1
expect_code "a bad home mode is bad use" 2 $?
(cd "$T" && HOME=$H kit start --out "$T/no-such") >"$T/out" 2>&1
expect_code "a missing folder is bad use" 2 $?

# A run in a folder with a space.
D="$T/a b"
mkdir -m 0700 "$D"
(cd "$D" && HOME=$H PATH=$P kit start --out "$D") >"$T/start" 2>&1
expect_code "kit start exits 0" 0 $?
run=$(run_of "$D")
expect_line "kit start prints the run as its last line" "^run: " "$(printf '%s' "$T/start")"
if [ "$(tail -n 1 "$T/start")" = "run: $run" ]; then pass "the last line is the run path"; else fail "the last line is the run path" "$(tail -n 1 "$T/start")"; fi
case $(basename "$run") in
  agent-signals-run-linux-* | agent-signals-run-macos-*) pass "the run folder has the name of the design" ;;
  *) fail "the run folder has the name of the design" "$run" ;;
esac
# shellcheck disable=SC2012
case $(ls -ld "$run" | cut -c1-10) in drwx------) pass "the run folder has mode 0700" ;; *) fail "the run folder has mode 0700" "$(ls -ld "$run")" ;; esac
expect_line "the manifest has the home mode" '^meta	home	real$' "$run/manifest.tsv"
expect_line "the manifest has the kit version" '^meta	kit	' "$run/manifest.tsv"
expect_no_line "the manifest has no host name" "$(hostname 2>/dev/null || uname -n)" "$run/manifest.tsv"

# The probe step, with no stdin.
(cd "$D" && HOME=$H PATH=$P kit step probe@none </dev/null) >"$T/step" 2>&1
expect_code "kit step probe@none exits 0" 0 $?
expect_line "kit step prints the result line" '^step: probe@none ok$' "$T/step"
expect_file "the step wrote 01-probe@none.txt" "$run/01-probe@none.txt"
expect_line "the probe file holds the claude probe" '^################ claude$' "$run/01-probe@none.txt"
expect_line "the probe ran the fake claude" '0\.0\.0-fake' "$run/01-probe@none.txt"
n=$(grep -c '^step	' "$run/manifest.tsv")
if [ "$n" = 1 ]; then pass "the manifest has one step line"; else fail "the manifest has one step line" "$n lines"; fi
sha=$(. "$ROOT/probes/agent/lib.sh" && kit_sha256 "$run/01-probe@none.txt")
expect_line "the step line has the SHA-256 of the file" "^step	probe	none	ok	[^	]+	[^	]+	01-probe@none\.txt	$sha	-$" "$run/manifest.tsv"
if [ -d "$run/.raw" ]; then fail "the step leaves no raw file" "$(ls -A "$run/.raw")"; else pass "the step leaves no raw file"; fi

# manifest.json and summary.txt.
expect_line "the summary has the fixed first line" '^kit [^ ]+ on (linux|macos) \([^)]+\), .+\. Run from [0-9T:Z-]+ to [0-9T:Z-]+ \(real\)\.$' "$run/summary.txt"
expect_line "the summary has a line for the step" '^probe@none: ok, 01-probe@none\.txt$' "$run/summary.txt"
if command -v python3 >/dev/null 2>&1; then
  if python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["steps"][0]["name"] == "probe" and d["steps"][0]["reason"] is None' "$run/manifest.json"; then
    pass "manifest.json is JSON"
  else
    fail "manifest.json is JSON" "python3 cannot read it"
  fi
else
  pass "manifest.json is JSON (skipped: no python3)"
fi

# Bad use.
(cd "$D" && kit step no-such@none) >"$T/out" 2>&1
expect_code "an unknown step is bad use" 2 $?
(cd "$D" && kit step probe@tmux) >"$T/out" 2>&1
expect_code "a backend that the step does not have is bad use" 2 $?
if [ "$(uname -s)" != Darwin ]; then
  (cd "$D" && kit step terminals@none) >"$T/out" 2>&1
  expect_code "the terminal probe on Linux is bad use" 2 $?
fi
(cd "$T" && AGENT_SIGNALS_RUN="$T/none" kit step probe@none) >"$T/out" 2>&1
expect_code "a step with no run is bad use" 2 $?

# The step contract, with a fake step script in a kit copy.
kit_copy "$T/k"
fake_step "$T/k" permission
mkdir -m 0700 "$T/r"
(cd "$T/r" && HOME=$H kitc "$T/k" start --out "$T/r") >/dev/null 2>&1
run2=$(run_of "$T/r")
(cd "$T/r" && HOME=$H kitc "$T/k" step permission-claude@pty --ready) >"$T/out" 2>&1
expect_code "a fake step exits 0" 0 $?
f=$run2/01-permission-claude@pty.txt
expect_line "the script gets the variables" '^step=permission-claude kind=permission agent=claude backend=pty home=real$' "$f"
expect_line "the script gets the fixed prompt" '^prompt=Create a file named agent-signals-test\.txt that holds the word hello\.$' "$f"
expect_line "the script gets the answer" '^answer=Escape$' "$f"
expect_line "the script gets the arguments" '^args=--ready$' "$f"
expect_no_line "the file is scrubbed" "$H" "$f"
(cd "$T/r" && HOME=$H FAKE_CODE=3 FAKE_REASON=needs-pyte kitc "$T/k" step permission-claude@pty) >"$T/out" 2>&1
expect_code "a script skip exits 3" 3 $?
expect_line "a script skip prints its reason" '^step: permission-claude@pty skip needs-pyte$' "$T/out"
(cd "$T/r" && HOME=$H FAKE_CODE=1 kitc "$T/k" step permission-claude@pty) >"$T/out" 2>&1
expect_code "a script fail exits 1" 1 $?
expect_line "a fail prints fail" '^step: permission-claude@pty fail$' "$T/out"
(cd "$T/r" && HOME=$H FAKE_CODE=4 FAKE_REASON=start-the-agent kitc "$T/k" step permission-claude@pty) >"$T/out" 2>&1
expect_code "an operator step exits 4" 4 $?
expect_line "an operator step prints operator" '^step: permission-claude@pty operator start-the-agent$' "$T/out"
n=$(grep -c '^step	' "$run2/manifest.tsv")
if [ "$n" = 3 ]; then pass "an operator result adds no step line"; else fail "an operator result adds no step line" "$n lines"; fi
(cd "$T/r" && HOME=$H FAKE_NO_OUT=yes kitc "$T/k" step permission-claude@pty) >"$T/out" 2>&1
expect_code "ok with no output is a fail" 1 $?
expect_line "ok with no output prints no-output" 'fail no-output$' "$T/out"

# The reason keeps only a-z, 0-9, "." and "-".
(cd "$T/r" && HOME=$H FAKE_CODE=3 FAKE_REASON='Need "x"/y z' kitc "$T/k" step permission-claude@pty) >"$T/out" 2>&1
expect_line "the reason keeps only safe characters" '^step: permission-claude@pty skip -eed--x--y-z$' "$T/out"
(cd "$T/r" && HOME=$H kitc "$T/k" step 'permission-claude@T1') >"$T/out" 2>&1
expect_code "a backend with other characters is bad use" 2 $?

# A step script must not write in a run folder that others can read.
mkdir -m 0700 "$T/m"
(cd "$T/m" && HOME=$H kitc "$T/k" start --out "$T/m") >/dev/null 2>&1
chmod 0755 "$(run_of "$T/m")"
(cd "$T/m" && HOME=$H kitc "$T/k" step permission-claude@pty) >"$T/out" 2>&1
expect_code "a step in a run folder with mode 0755 is bad use" 2 $?

# A scrub that fails gives "fail scrub" and no file.
kit_copy "$T/k2"
fake_step "$T/k2" permission
printf '#!/bin/sh\necho partial\nexit 1\n' >"$T/k2/tools/scrub.sh"
mkdir -m 0700 "$T/s"
(cd "$T/s" && HOME=$H kitc "$T/k2" start --out "$T/s") >/dev/null 2>&1
(cd "$T/s" && HOME=$H kitc "$T/k2" step permission-claude@pty) >"$T/out" 2>&1
expect_code "a failed scrub fails the step" 1 $?
expect_line "a failed scrub prints fail scrub" '^step: permission-claude@pty fail scrub$' "$T/out"
run3=$(run_of "$T/s")
set -- "$run3"/01-*
if [ -e "$1" ]; then fail "a failed scrub leaves no step file" "$1"; else pass "a failed scrub leaves no step file"; fi
if [ -d "$run3/.raw" ]; then fail "a failed scrub leaves no raw file" "$(ls -A "$run3/.raw")"; else pass "a failed scrub leaves no raw file"; fi

# A step with one backend runs with no @, and gets the next number.
cat >"$T/k/probes/agent/steps/probe.sh" <<'EOF'
#!/bin/sh
echo "fake probe" >"$KIT_OUT"
EOF
# The start in "$T/m" is newer, so this test names the run.
(cd "$T/r" && HOME=$H AGENT_SIGNALS_RUN=$run2 kitc "$T/k" step probe) >"$T/out" 2>&1
expect_code "a step with one backend runs with no @" 0 $?
expect_file "the next step has the next number" "$run2/05-probe@none.txt"

# A throwaway home skips a login step.
mkdir -m 0700 "$T/t"
(cd "$T/t" && HOME=$H kitc "$T/k" start --home throwaway --out "$T/t") >/dev/null 2>&1
(cd "$T/t" && HOME=$H kitc "$T/k" step permission-claude@tmux) >"$T/out" 2>&1
expect_code "a login step in a throwaway home exits 0" 0 $?
expect_line "a login step in a throwaway home skips" '^step: permission-claude@tmux skip no-login$' "$T/out"
expect_line "the skip is in the manifest" '^step	permission-claude	tmux	skip	[^	]+	[^	]+	-	-	no-login$' "$(run_of "$T/t")/manifest.tsv"

# An unattended run skips a step that needs the operator.
mkdir -m 0700 "$T/u"
(cd "$T/u" && HOME=$H kitc "$T/k" start --unattended --out "$T/u") >/dev/null 2>&1
expect_line "the manifest records an unattended run" '^meta	unattended	yes$' "$(run_of "$T/u")/manifest.tsv"
expect_line "manifest.json records an unattended run" '"unattended": true' "$(run_of "$T/u")/manifest.json"
(cd "$T/u" && HOME=$H kitc "$T/k" step real-session-claude@operator) >"$T/out" 2>&1
expect_code "an operator step in an unattended run exits 0" 0 $?
expect_line "an operator step in an unattended run skips" '^step: real-session-claude@operator skip unattended$' "$T/out"
(cd "$T/u" && HOME=$H kitc "$T/k" plan) >"$T/out" 2>&1
expect_line "the plan of an unattended run marks an operator step" '^step: real-session-claude@operator needs=operator cost=[^ ]+ skip=unattended ' "$T/out"
expect_line "the plan of an unattended run keeps the probe" '^step: probe@none needs=none cost=none measures=' "$T/out"
(cd "$T/t" && HOME=$H AGENT_SIGNALS_RUN=$(run_of "$T/t") kitc "$T/k" plan) >"$T/out" 2>&1
expect_no_line "a run with a person has no unattended skip" 'skip=unattended' "$T/out"

done_tests
