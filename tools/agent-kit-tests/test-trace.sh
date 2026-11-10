# shellcheck shell=sh
# The command "kit trace" (probes/agent/trace.sh): the recorders, the step,
# the build and the scrub, with the stub agent. Linux only.
. "${ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}/tools/agent-kit-tests/lib.sh"

if [ "$(uname -s)" != Linux ]; then
  echo "pass: skip not Linux"
  done_tests
fi
if ! command -v tmux >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
  echo "pass: skip no tmux or no python3"
  done_tests
fi
. "$ROOT/tools/agent-kit-tests/core-lib.sh"
. "$ROOT/tools/agent-kit-tests/steps-lib.sh"

# The checker: "q.py FILE EXPR" evaluates EXPR with the document as d and
# exits 0 when the value is true.
cat >"$T/q.py" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
ev = d["events"]
sys.exit(0 if eval(sys.argv[2]) else 1)
PYEOF
# want NAME FILE EXPR: pass when EXPR is true for FILE.
want() {
  if python3 -I "$T/q.py" "$2" "$3" 2>/dev/null; then pass "$1"; else fail "$1" "false: $3"; fi
}

# private NAME DIR: pass when no file below DIR holds $T, and no file holds
# the account name or the host name as a word. The meta keys with a fixed
# set of words are not read for the names: on a CI runner, the account
# name is "runner", and the meta value "machine" is "runner" too. The meta
# keys with free text are read.
me=$(id -un)
host=$(hostname 2>/dev/null || uname -n)
private() {
  _bad=
  if grep -rlF -- "$T" "$2" >/dev/null 2>&1; then _bad="the test folder"; fi
  find "$2" -type f >"$T/files.list"
  while IFS= read -r _f; do
    if ! python3 -I -c '
import json, re, sys
path, names = sys.argv[1], sys.argv[2:]
text = open(path, encoding="utf-8", errors="replace").read()
if path.endswith(".json"):
    d = json.loads(text)
    for k in ("machine", "mode", "home", "backend", "agent", "os"):
        d["meta"].pop(k, None)
    text = json.dumps(d)
for n in names:
    if n and re.search(r"(^|[^A-Za-z0-9_-])" + re.escape(n) + r"([^A-Za-z0-9_-]|$)", text, re.I):
        sys.exit(1)' "$_f" "$me" "$host" "${host%%.*}"; then
      _bad="${_bad:+$_bad, }a name in ${_f##*/}"
    fi
  done <"$T/files.list"
  if [ -z "$_bad" ]; then pass "$1"; else fail "$1" "$_bad"; fi
}

# The schema check of a trace folder, on a temp root. Skipped when go is
# missing.
validate() {
  if ! command -v go >/dev/null 2>&1; then
    echo "pass: skip the schema check, go is not on PATH"
    return 0
  fi
  _r=$T/vroot
  rm -rf "$_r"
  mkdir -p "$_r/schema" "$_r/corpus" "$_r/facts" "$_r/traces/claude/unknown/01-permission@tmux"
  for _f in "$ROOT"/schema/*; do cp "$_f" "$_r/schema/"; done
  cp "$2"/* "$_r/traces/claude/unknown/01-permission@tmux/"
  if (cd "$ROOT/tools" && go run ./cmd/validate "$_r") >"$T/validate.log" 2>&1; then
    pass "$1"
  else
    fail "$1" "$(head -c 400 "$T/validate.log")"
  fi
}

# trace_pids: the pid files of $run/pids/ with a trace label.
trace_pids() {
  for _f in "$run"/pids/*; do
    [ -f "$_f" ] || continue
    case $(cut -f1 "$_f") in "trace "*) echo "${_f##*/}" ;; esac
  done
}

# The fixture run. The first trace comes just after "kit start", so the
# work root and RUN/home do not exist yet.
WATCH=3
export WATCH
kitx start --home fixture --out "$D" >"$T/log" 2>&1
expect_code "kit start exits 0" 0 $?
run=$(run_of "$D")
# The stub shows its current folder, as the welcome box of an agent does.
# It also shows a cut form "/…/TAIL", as Claude Code draws a long folder.
stub_set STUB_TRUST=yes 'STUB_WELCOME="cwd $PWD cut /…/${PWD#*/out/}"'
kitx trace permission-claude@tmux >"$T/t1" 2>"$T/t1.err"
expect_code "trace: exit 0" 0 $?
tr1=$run/traces/01-permission-claude@tmux
j=$tr1/trace.json
expect_line "trace: the step line" '^step: permission-claude@tmux ok' "$T/t1"
expect_line "trace: the trace line comes last" "^trace: .*/traces/01-permission-claude@tmux\$" "$T/t1"
if [ "$(tail -n 1 "$T/t1")" = "trace: $run/traces/01-permission-claude@tmux" ]; then pass "trace: the last line names the folder"; else fail "trace: the last line names the folder" "$(tail -n 1 "$T/t1")"; fi
expect_file "trace: trace.json exists" "$j"
validate "trace: trace.json passes the schema check" "$tr1"
want "trace: meta.checks is terminal, network, files" "$j" 'd["meta"]["checks"] == ["terminal", "network", "files"]'
want "trace: meta of the run and the step" "$j" 'd["meta"]["agent"] == "claude" and d["meta"]["backend"] == "tmux" and d["meta"]["mode"] == "fixture" and d["meta"]["home"] == "fixture" and d["meta"]["machine"] in ("real", "runner") and d["meta"]["step"].endswith("-permission-claude@tmux.txt")'
want "trace: the states hold start, dialog and stop" "$j" '{"start", "dialog", "stop"} <= {s["state"] for s in d["states"]}'
want "trace: summary.files.work holds the file of the stub" "$j" '"WORK/stub-work.txt" in d["summary"]["files"]["work"]'
want "trace: summary.hosts is a list" "$j" 'isinstance(d["summary"]["hosts"], list)'
want "trace: terminal is the cast" "$j" 'd["terminal"] == "terminal.cast"'
if grep -F 'stub idle' "$tr1/terminal.cast" >/dev/null 2>&1; then pass "trace: the cast holds stub idle"; else fail "trace: the cast holds stub idle" "no text"; fi
if grep -F 'cwd /work/example' "$tr1/terminal.cast" >/dev/null 2>&1; then pass "trace: the cwd in the cast is scrubbed"; else fail "trace: the cwd in the cast is scrubbed" "no text cwd /work/example"; fi
if grep -F 'cut /work/example/permission-claude-tmux' "$tr1/terminal.cast" >/dev/null 2>&1 &&
  ! grep -F 'agent-signals-run-' "$tr1/terminal.cast" >/dev/null 2>&1; then
  pass "trace: the cut cwd in the cast is scrubbed"
else
  fail "trace: the cut cwd in the cast is scrubbed" "$(grep -o 'cut [^ ]*' "$tr1/terminal.cast" | head -n 1)"
fi
want "trace: summary.files.tmp holds the temp file of the stub" "$j" 'len(d["summary"]["files"]["tmp"]) > 0 and all(p.startswith("TMP/") for p in d["summary"]["files"]["tmp"])'
if [ ! -e "$run/.trace" ]; then pass "trace: no RUN/.trace stays"; else fail "trace: no RUN/.trace stays" "it exists"; fi
if [ -z "$(trace_pids)" ]; then pass "trace: no trace pid stays in RUN/pids"; else fail "trace: no trace pid stays in RUN/pids" "$(trace_pids)"; fi

# Only the terminal check.
kitx trace permission-claude@tmux --checks terminal >"$T/t2" 2>&1
expect_code "terminal only: exit 0" 0 $?
j=$run/traces/02-permission-claude@tmux/trace.json
expect_file "terminal only: the folder number is 02" "$j"
want "terminal only: summary.hosts is null" "$j" 'd["summary"]["hosts"] is None and d["summary"]["files"] is None and d["summary"]["model_requests"] is None'
want "terminal only: meta.checks is terminal" "$j" 'd["meta"]["checks"] == ["terminal"]'

# The TMPDIR of the operator does not change the temp folder of the
# agent: the agent starts with no TMPDIR and writes to /tmp.
mkdir -p "$T/optmp"
(TMPDIR=$T/optmp && export TMPDIR && kitx trace permission-claude@tmux --checks files) >"$T/t2b" 2>&1
expect_code "operator TMPDIR: exit 0" 0 $?
j=$run/traces/03-permission-claude@tmux/trace.json
want "operator TMPDIR: summary.files.tmp holds the temp file of the stub" "$j" 'len(d["summary"]["files"]["tmp"]) > 0 and all(p.startswith("TMP/") for p in d["summary"]["files"]["tmp"])'
want "operator TMPDIR: no path names the folder" "$j" '"optmp" not in json.dumps(d)'

# Bad use.
kitx trace permission-claude@tmux --checks ebpf >"$T/t3" 2>&1
expect_code "ebpf: exit 2" 2 $?
expect_line "ebpf: the text" 'the ebpf check is not in this kit yet' "$T/t3"
kitx trace permission-claude@tmux --checks terminal,disk >"$T/t3" 2>&1
expect_code "an unknown check: exit 2" 2 $?
kitx trace --bogus permission-claude@tmux >"$T/t3" 2>&1
expect_code "an unknown option: exit 2" 2 $?
kitx trace >"$T/t3" 2>&1
expect_code "no step: exit 2" 2 $?
kitx trace no-such-step@tmux >"$T/t3" 2>&1
expect_code "an unknown step: exit 2" 2 $?
if [ ! -e "$run/.trace" ] && [ ! -e "$run/traces/04-permission-claude@tmux" ]; then pass "bad use: no trace folder"; else fail "bad use: no trace folder" "a folder exists"; fi

# A step that fails: the agent shows no idle screen.
cp "$B/claude" "$T/stub-claude"
cp "$T/other/claude" "$B/claude"
kitx trace permission-claude@tmux >"$T/t4" 2>&1
expect_code "failed step: exit 1" 1 $?
cp "$T/stub-claude" "$B/claude"
expect_line "failed step: the step line" '^step: permission-claude@tmux fail no-idle' "$T/t4"
j=$run/traces/04-permission-claude@tmux/trace.json
expect_file "failed step: trace.json exists" "$j"
want "failed step: the state start" "$j" '"start" in [s["state"] for s in d["states"]]'
if [ -z "$(trace_pids)" ]; then pass "failed step: no trace pid stays"; else fail "failed step: no trace pid stays" "$(trace_pids)"; fi

# A step that skips before a session starts: the terminal check gets the
# reason no-cast. The agent must not be on PATH.
if [ -z "$(PATH="$B:$SYS_PATH" command -v codex)" ]; then
  (cd "$D" && HOME=$H PATH="$B:$SYS_PATH" AGENT_SIGNALS_WATCH=3 sh "$ROOT/probes/agent/kit.sh" trace permission-codex@tmux </dev/null) >"$T/t5" 2>&1
  expect_code "skipped step: exit 3" 3 $?
  j=$run/traces/05-permission-codex@tmux/trace.json
  want "skipped step: terminal no-cast" "$j" '{"check": "terminal", "reason": "no-cast"} in d["meta"]["skipped"] and d["terminal"] is None'
  want "skipped step: the step name is the meta step" "$j" 'd["meta"]["step"] == "permission-codex@tmux"'
else
  echo "pass: skip the skipped step, codex is on the system PATH"
fi

# A second trace while a trace runs: exit 2.
(WATCH=6 && export WATCH && kitx trace permission-claude@tmux) >"$T/t6" 2>&1 &
first=$!
bg_pid "$first"
n=0
while [ ! -s "$run/.trace/t0" ] && [ "$n" -lt 100 ]; do
  sleep 0.1
  n=$((n + 1))
done
kitx trace permission-claude@tmux --checks terminal >"$T/t7" 2>&1
expect_code "a second trace: exit 2" 2 $?
wait "$first"
expect_code "the first trace: exit 0" 0 $?
if [ ! -e "$run/.trace" ]; then pass "the first trace deletes RUN/.trace"; else fail "the first trace deletes RUN/.trace" "it exists"; fi

# TERM while the step runs: the trace stops the step, its session and the
# recorders, and deletes RUN/.trace. "exec" makes $! the pid of trace.sh.
(cd "$D" && HOME=$H PATH="$B:$PATH" AGENT_SIGNALS_WATCH=30 exec sh "$ROOT/probes/agent/kit.sh" trace permission-claude@tmux </dev/null) >"$T/t9" 2>&1 &
tpid=$!
bg_pid "$tpid"
n=0
while ! grep -q 'dialog' "$run/.trace/states.tsv" 2>/dev/null && [ "$n" -lt 300 ]; do
  sleep 0.1
  n=$((n + 1))
done
kill -TERM "$tpid"
wait "$tpid"
expect_code "TERM: exit 143" 143 $?
if [ ! -e "$run/.trace" ]; then pass "TERM: no RUN/.trace stays"; else fail "TERM: no RUN/.trace stays" "it exists"; fi
if [ -z "$(trace_pids)" ]; then pass "TERM: no trace pid stays"; else fail "TERM: no trace pid stays" "$(trace_pids)"; fi
if [ -z "$(pids_run)" ]; then pass "TERM: no pid of RUN/pids runs"; else fail "TERM: no pid of RUN/pids runs" "$(pids_run)"; fi
if [ -f "$run/sessions/permission-claude-tmux/stopped" ]; then pass "TERM: the session is stopped"; else fail "TERM: the session is stopped" "no file stopped"; fi
private "fixture run: no file in RUN/traces holds the test folder or a name" "$run/traces"

# The real home: HOME is a folder of the test.
R=$T/realhome
mkdir -p "$R"
D2=$T/out2
mkdir -m 0700 "$D2"
kitr() {
  (cd "$D2" && HOME=$R PATH="$B:$PATH" AGENT_SIGNALS_WATCH=3 \
    KITSH=$ROOT/probes/agent/kit.sh "$T/orch/claude" "$@" </dev/null)
}
kitr start --home real --out "$D2" >"$T/log" 2>&1
expect_code "real home: kit start exits 0" 0 $?
run=$(run_of "$D2")
kitr trace permission-claude@tmux >"$T/t8" 2>&1
expect_code "real home: exit 0" 0 $?
tr8=$run/traces/01-permission-claude@tmux
j=$tr8/trace.json
want "real home: home paths start with ~" "$j" 'any(e.get("path", "").startswith("~/.claude/") for e in ev) and all(not e.get("path", "").startswith("/") for e in ev if e["kind"] != "proxy")'
want "real home: no terminal" "$j" 'd["terminal"] is None and "terminal" not in d["meta"]["checks"]'
want "real home: login mode, the terminal is skipped" "$j" 'd["meta"]["mode"] == "login" and {"check": "terminal", "reason": "not-fixture-home"} in d["meta"]["skipped"]'
if [ ! -e "$tr8/terminal.cast" ]; then pass "real home: no cast"; else fail "real home: no cast" "file exists"; fi
if grep -rlF -- "$R" "$tr8" >/dev/null 2>&1; then fail "real home: the home path is in no file" "found"; else pass "real home: the home path is in no file"; fi
private "real home: no file in RUN/traces holds the test folder or a name" "$run/traces"

done_tests
