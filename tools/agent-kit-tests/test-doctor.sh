# shellcheck shell=sh
# kit doctor: the facts of the machine, the agents and their versions from
# the install paths, and the orchestrator agent. The doctor runs no agent.
. "$ROOT/tools/agent-kit-tests/lib.sh"

# A copy of the fake home. tar keeps the symbolic links, and cp -R can
# fail in a sandbox.
H=$T/home
mkdir -p "$H"
(cd "$ROOT/tools/testdata/agent-kit/doctor-home" && tar cf - .) | (cd "$H" && tar xf -)
P=$H/.local/bin:$H/.npm-global/bin:$PATH
mkdir "$T/work"

# doctor OUT [VAR=VALUE ...]: run kit doctor with the fake home, no
# terminal on stdin, and no run folder.
doctor() {
  _o=$1
  shift
  (cd "$T/work" && env HOME="$H" PATH="$P" DOCTOR_MARKER="$T/marker" AGENT_SIGNALS_RUN= "$@" \
    sh "$ROOT/probes/agent/kit.sh" doctor </dev/null >"$_o" 2>"$_o.err")
}

doctor "$T/out"
expect_code "doctor exits 0" 0 $?
expect_line "doctor prints os" '^os: (linux|macos)$' "$T/out"
expect_line "doctor prints os_version" '^os_version: .' "$T/out"
expect_line "doctor prints cpu" '^cpu: .' "$T/out"
expect_line "doctor prints shell" '^shell: .' "$T/out"
for t in tmux python3 pyte uv flock lsof script; do
  expect_line "doctor prints tool $t" "^tool: $t (missing|/.*)$" "$T/out"
done
expect_no_line "doctor prints no psmux on Unix" '^tool: psmux' "$T/out"

# test_doctor_versions_from_paths
expect_line "claude version from versions/" '^agent: claude ~/\.local/share/claude/versions/2\.1\.316 2\.1\.316$' "$T/out"
expect_line "cursor version from versions/" '^agent: cursor ~/\.local/share/cursor-agent/versions/2026\.10\.22-27dcf5f/cursor-agent 2026\.10\.22-27dcf5f$' "$T/out"
expect_line "codex version from package.json" '^agent: codex ~/\.npm-global/lib/node_modules/@openai/codex/bin/codex\.js 0\.166\.0$' "$T/out"
expect_line "gemini version from package.json" '^agent: gemini ~/.npm-global/lib/node_modules/@google/gemini-cli/dist/index\.js 0\.66\.0$' "$T/out"
expect_line "copilot version from package.json" '^agent: copilot ~/.npm-global/lib/node_modules/@github/copilot/npm-loader\.js 1\.0\.105$' "$T/out"
expect_line "opencode version from package.json" '^agent: opencode ~/.npm-global/lib/node_modules/opencode-ai/bin/opencode 1\.19\.5$' "$T/out"
expect_line "agy with no version in the path is unknown" '^agent: agy ~/\.local/bin/agy unknown$' "$T/out"
expect_no_line "each agent line has a known form" '^agent: [a-z]+ ($|[^~/m])' "$T/out"
expect_line "doctor prints the orchestrator" '^orchestrator: [a-z]+ [0-9-]+$' "$T/out"
expect_line "doctor prints the orchestrator terminal" '^orchestrator_terminal: .' "$T/out"

expect_line "doctor prints the sandbox" '^orchestrator_sandbox: .' "$T/out"

# The sandbox variables of Codex.
doctor "$T/out5" CODEX_SANDBOX=seatbelt CODEX_SANDBOX_NETWORK_DISABLED=1
expect_line "doctor prints CODEX_SANDBOX" '^orchestrator_sandbox: CODEX_SANDBOX=seatbelt$' "$T/out5"
expect_line "doctor prints CODEX_SANDBOX_NETWORK_DISABLED" '^orchestrator_sandbox: CODEX_SANDBOX_NETWORK_DISABLED=1$' "$T/out5"

# Git Bash on Windows: the doctor names kit.ps1.
doctor "$T/out6" DOCTOR_UNAME=MINGW64_NT-10.0-26100
expect_code "doctor under Git Bash exits 0" 0 $?
expect_line "doctor under Git Bash prints windows-gitbash" '^os: windows-gitbash$' "$T/out6"
expect_line "doctor under Git Bash names kit.ps1" '^hint: run probes/agent/kit\.ps1 with powershell -NoProfile -ExecutionPolicy Bypass -File$' "$T/out6"
expect_no_line "doctor under Git Bash prints no agent" '^agent:' "$T/out6"

# test_doctor_runs_no_agent
if ls "$T"/marker.* >/dev/null 2>&1; then
  fail "doctor runs no agent" "markers: $(ls "$T"/marker.*)"
else
  pass "doctor runs no agent"
fi
# The control: a fake agent that runs writes its marker.
env DOCTOR_MARKER="$T/control" "$H/.local/bin/claude" >/dev/null
if [ -f "$T/control.claude" ]; then pass "a fake agent that runs writes a marker"; else fail "a fake agent that runs writes a marker" "no marker"; fi

# An agent that is not on PATH is missing. The PATH has no fake home.
(cd "$T/work" && env HOME="$H" PATH=/usr/bin:/bin AGENT_SIGNALS_RUN= sh "$ROOT/probes/agent/kit.sh" doctor </dev/null >"$T/out2" 2>&1)
expect_code "doctor with no agents exits 0" 0 $?
if PATH=/usr/bin:/bin command -v agy >/dev/null 2>&1; then
  pass "agy missing (skip: agy is in /usr/bin or /bin)"
else
  expect_line "agy missing" '^agent: agy missing$' "$T/out2"
fi

# test_doctor_finds_the_orchestrator: the kit runs as a child of a stub
# process named claude.
mkdir "$T/stub"
cat >"$T/stub/claude" <<EOF
#!/bin/sh
echo \$\$ >"$T/stub.pid"
sh "$ROOT/probes/agent/kit.sh" doctor </dev/null >"$T/out3" 2>&1
rc=\$?
exit \$rc
EOF
chmod 755 "$T/stub/claude"
(cd "$T/work" && env HOME="$H" PATH="$P" AGENT_SIGNALS_RUN= "$T/stub/claude")
expect_code "doctor under the stub exits 0" 0 $?
sp=$(cat "$T/stub.pid" 2>/dev/null)
expect_line "doctor finds the orchestrator" "^orchestrator: claude $sp\$" "$T/out3"

# With no run, the doctor writes no file.
expect_no_line "with no run the doctor writes no file" 'wrote' "$T/out.err"
if [ -n "$(find "$T/work" -name '*doctor*')" ]; then fail "no 00-doctor.txt with no run" "a file exists"; else pass "no 00-doctor.txt with no run"; fi

# With a run, the doctor writes 00-doctor.txt, scrubbed.
mkdir -m 700 "$T/run"
doctor "$T/out4" AGENT_SIGNALS_RUN="$T/run"
expect_code "doctor with a run exits 0" 0 $?
if [ -f "$T/run/00-doctor.txt" ]; then pass "doctor writes 00-doctor.txt"; else fail "doctor writes 00-doctor.txt" "no file"; fi
expect_line "00-doctor.txt has the agent lines" '^agent: claude ~/\.local/share/claude/versions/2\.1\.316 2\.1\.316$' "$T/run/00-doctor.txt"
if grep -qF "$H" "$T/run/00-doctor.txt"; then fail "00-doctor.txt is scrubbed" "it holds the home folder"; else pass "00-doctor.txt is scrubbed"; fi
if grep -qF "$H" "$T/out4"; then fail "stdout is scrubbed" "it holds the home folder"; else pass "stdout is scrubbed"; fi
if cmp -s "$T/out4" "$T/run/00-doctor.txt"; then pass "stdout is the text of 00-doctor.txt"; else fail "stdout is the text of 00-doctor.txt" "they differ"; fi
if [ -n "$(find "$T/run" -mindepth 1 ! -name 00-doctor.txt)" ]; then fail "the run has no raw file" "$(ls "$T/run")"; else pass "the run has no raw file"; fi

# The manifest line, from the helper of doctor.sh.
line=$(sh "$ROOT/probes/agent/doctor.sh" --manifest-line "$T/run" 2026-11-04T10:00:00Z 2026-11-04T10:00:01Z)
case $line in
  "step	doctor	none	ok	2026-11-04T10:00:00Z	2026-11-04T10:00:01Z	00-doctor.txt	"[0-9a-f]*) pass "doctor_manifest_line has the step form" ;;
  *) fail "doctor_manifest_line has the step form" "got '$line'" ;;
esac

done_tests
