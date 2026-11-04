# shellcheck shell=sh
# "kit check" and "kit edit", with fake step scripts in a kit copy.
. "$ROOT/tools/agent-kit-tests/lib.sh"
. "$ROOT/tools/agent-kit-tests/core-lib.sh"

H=$T/home-of-test
mkdir -p "$H"
kit_copy "$T/k"
fake_step "$T/k" permission

# new_run NAME: a new run folder $T/NAME with one ok step, and its path in
# $run.
new_run() {
  mkdir -m 0700 "$T/$1"
  (cd "$T/$1" && HOME=$H kitc "$T/k" start --out "$T/$1") >/dev/null 2>&1
  run=$(run_of "$T/$1")
  (cd "$T/$1" && HOME=$H kitc "$T/k" step permission-claude@pty) >/dev/null 2>&1
  file=$run/01-permission-claude@pty.txt
}
# check NAME: kit check in the folder $T/NAME, output in $T/out.
check() { (cd "$T/$1" && HOME=$H kitc "$T/k" check) >"$T/out" 2>&1; }

new_run clean
mkdir -p "$run/sessions/s1" "$run/pids"
echo "API_KEY=LEAK-CANARY-SESSION" >"$run/sessions/s1/env"
(cd "$T/clean" && HOME=$H FAKE_CODE=1 FAKE_NO_OUT=yes kitc "$T/k" step permission-claude@pty) >/dev/null 2>&1
check clean
expect_code "kit check passes a clean run" 0 $?
expect_line "kit check prints the archive" "^archive: $(basename "$run")\.tar\.gz$|^archive: .*/$(basename "$run")\.tar\.gz$" "$T/out"
expect_line "kit check prints pass" '^check: pass$' "$T/out"
expect_file "the archive is next to the run folder" "$run.tar.gz"
tar -tzf "$run.tar.gz" >"$T/list"
expect_line "the archive holds the step file" "^$(basename "$run")/01-permission-claude@pty\.txt$" "$T/list"
expect_line "the archive holds manifest.json" "/manifest\.json$" "$T/list"
expect_line "the archive holds summary.txt" "/summary\.txt$" "$T/list"
expect_no_line "the archive holds no session state" "/sessions" "$T/list"
if gzip -dc "$run.tar.gz" | grep -aq LEAK-CANARY; then fail "the archive holds no session env" "a canary"; else pass "the archive holds no session env"; fi

# A doctor file with its own step line is a known file.
echo "os: linux" >"$run/00-doctor.txt"
sha=$(. "$ROOT/probes/agent/lib.sh" && kit_sha256 "$run/00-doctor.txt")
printf 'step\tdoctor\tnone\tok\t2026-11-01T00:00:00Z\t2026-11-01T00:00:01Z\t00-doctor.txt\t%s\n' "$sha" >>"$run/manifest.tsv"
check clean
expect_code "kit check accepts the doctor line" 0 $?
tar -tzf "$run.tar.gz" >"$T/list"
expect_line "the archive holds the doctor file" "/00-doctor\.txt$" "$T/list"

new_run changed
echo "a name" >>"$file"
check changed
expect_code "kit check fails a changed file" 1 $?
expect_line "the failure names the file" '^check: 01-permission-claude@pty\.txt: the file changed' "$T/out"
(cd "$T/changed" && kitc "$T/k" edit 01-permission-claude@pty.txt "a free text") >"$T/out2" 2>&1
expect_code "kit edit refuses a free reason" 2 $?
(cd "$T/changed" && kitc "$T/k" edit 01-permission-claude@pty.txt project 1) >"$T/out2" 2>&1
expect_code "kit edit exits 0" 0 $?
expect_line "kit edit adds an edit line" '^edit	01-permission-claude@pty\.txt	project 1	[0-9a-f]{64}$' "$run/manifest.tsv"
check changed
expect_code "kit check passes after kit edit" 0 $?
(cd "$T/changed" && kitc "$T/k" edit no-such.txt project) >"$T/out2" 2>&1
expect_code "kit edit of a missing file is bad use" 2 $?
if command -v python3 >/dev/null 2>&1; then
  if python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["edits"][0]["reason"] == "project 1"' "$run/manifest.json"; then
    pass "manifest.json has the edit"
  else
    fail "manifest.json has the edit" "python3 cannot read it"
  fi
fi

new_run extra
echo "x" >"$run/notes.txt"
check extra
expect_code "kit check fails a file that is not in the manifest" 1 $?
expect_line "the failure names the extra file" '^check: notes\.txt: the file is not in the manifest' "$T/out"

new_run nofile
rm "$file"
check nofile
expect_code "kit check fails a missing step file" 1 $?

new_run home
echo "$H/project/a.txt" >>"$file"
(cd "$T/home" && kitc "$T/k" edit 01-permission-claude@pty.txt path) >/dev/null 2>&1
check home
expect_code "kit check fails the home folder" 1 $?
expect_line "the failure names the home folder" 'holds the home folder$' "$T/out"
if grep -Fq "$H" "$T/out"; then fail "the failure does not print the home folder" "it does"; else pass "the failure does not print the home folder"; fi

new_run wrap
# A screen wraps a long path: the home folder is on two lines.
printf '%s\n%s\n' "$(printf '%s' "$H" | cut -c1-8)" "$(printf '%s' "$H/x" | cut -c9-)" >>"$file"
(cd "$T/wrap" && kitc "$T/k" edit 01-permission-claude@pty.txt path) >/dev/null 2>&1
check wrap
expect_code "kit check finds a home folder over a line break" 1 $?

new_run secret
echo "key: abcd1234efgh5678" >>"$file"
(cd "$T/secret" && kitc "$T/k" edit 01-permission-claude@pty.txt other) >/dev/null 2>&1
(cd "$T/secret" && HOME=$H TEST_KIT_API_KEY=abcd1234efgh5678 kitc "$T/k" check) >"$T/out" 2>&1
expect_code "kit check fails the value of an API key variable" 1 $?
expect_line "the failure names the variable, not the value" 'holds the value of TEST_KIT_API_KEY$' "$T/out"
expect_no_line "the failure does not print the value" 'abcd1234efgh5678' "$T/out"

new_run pid
sleep 60 &
p=$!
bg_pid "$p"
(KIT_DIR=$T/k/probes/agent && . "$T/k/probes/agent/lib.sh" && kit_add_pid "$run" "$p" session-test)
check pid
expect_code "kit check fails a pid of the run that still runs" 1 $?
expect_line "the failure names the pid" "^check: the process $p \(session-test\)" "$T/out"
kill "$p" 2>/dev/null
wait "$p" 2>/dev/null
check pid
expect_code "kit check passes when the pid has stopped" 0 $?

new_run mode
chmod 0755 "$run"
check mode
expect_code "kit check fails a run folder with mode 0755" 1 $?

# A probe step: each part must pass tools/check-probe-output.sh.
cat >"$T/k/probes/agent/steps/probe.sh" <<'EOF'
#!/bin/sh
{ echo "header"; echo "################ claude"; echo "### 1. Probe"; echo "os: linux"; } >"$KIT_OUT"
EOF
new_run probe
(cd "$T/probe" && HOME=$H kitc "$T/k" step probe@none) >/dev/null 2>&1
check probe
expect_code "kit check fails a probe part with too few sections" 1 $?
expect_line "the failure names the probe" '^check: 02-probe@none\.txt: probes/claude/unix\.sh: ' "$T/out"

(cd "$T" && AGENT_SIGNALS_RUN="$T/no-such" kitc "$T/k" check) >"$T/out" 2>&1
expect_code "kit check with no run is bad use" 2 $?

done_tests
