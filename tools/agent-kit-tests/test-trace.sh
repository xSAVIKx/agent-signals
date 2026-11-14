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
# work root and RUN/home do not exist yet. WATCH caps each wait of a step.
# With 3 s, the idle wait after the trust question of the stub ended too
# early on a busy CPU (fail no-idle, seen on the one-CPU runners).
WATCH=6
export WATCH
kitx start --home fixture --out "$D" >"$T/log" 2>&1
expect_code "kit start exits 0" 0 $?
run=$(run_of "$D")
# trace_code NAME WANT CODE FILE...: expect_code, and after a wrong exit
# code, the output of the trace and the log of its step file, so that a CI
# failure shows its cause. Write $T/mark before the trace: only a step file
# newer than the mark is the step of this trace.
trace_code() {
  _n=$1 _w=$2 _c=$3
  shift 3
  expect_code "$_n" "$_w" "$_c"
  [ "$_c" = "$_w" ] && return 0
  for _f in "$@"; do
    [ -f "$_f" ] && tail -n 30 "$_f" | sed "s/^/  out| /"
  done
  _s=$(find "$run" -maxdepth 1 -name '[0-9]*.txt' -newer "$T/mark" 2>/dev/null | sort | tail -n 1)
  [ -n "$_s" ] && sed -n '/^result:/p; /^#* *log$/,/^#/p' "$_s" | head -n 40 | sed "s/^/  step| /"
  return 0
}
# The stub shows its current folder, as the welcome box of an agent does.
# It also shows a cut form "/…/TAIL", as Claude Code draws a long folder.
stub_set STUB_TRUST=yes 'STUB_WELCOME="cwd $PWD cut /…/${PWD#*/out/}"'
: >"$T/mark"
kitx trace permission-claude@tmux >"$T/t1" 2>"$T/t1.err"
trace_code "trace: exit 0" 0 $? "$T/t1" "$T/t1.err"
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
# The files that the kit writes are not files of the agent: the settings
# files of the fake model, the home and the work folder of the session,
# and the deletes when the session stops.
want "kit files: no settings file of the fake model" "$j" 'not any(p.startswith(("~", "WORK")) and p.endswith(("settings.json", ".claude.json", ".new")) for e in ev for p in (e.get("path", ""), e.get("from", "")))'
want "kit files: no event for the home or the work folder itself" "$j" 'not any(e.get("path") in ("~", "WORK") for e in ev)'
want "kit files: no delete of the file of the stub" "$j" 'not any(e["kind"] == "delete" and e.get("path") == "WORK/stub-work.txt" for e in ev)'
want "kit files: no mark file" "$j" '"kit-trace-mark" not in json.dumps(d)'
if python3 -I -c '
import json, sys
for line in open(sys.argv[1], encoding="utf-8"):
    json.loads(line)' "$tr1/terminal.cast" 2>/dev/null; then
  pass "trace: each line of the scrubbed cast is valid JSON"
else
  fail "trace: each line of the scrubbed cast is valid JSON" "a bad line"
fi

# Only the terminal check.
: >"$T/mark"
kitx trace permission-claude@tmux --checks terminal >"$T/t2" 2>&1
trace_code "terminal only: exit 0" 0 $? "$T/t2"
j=$run/traces/02-permission-claude@tmux/trace.json
expect_file "terminal only: the folder number is 02" "$j"
want "terminal only: summary.hosts is null" "$j" 'd["summary"]["hosts"] is None and d["summary"]["files"] is None and d["summary"]["model_requests"] is None'
want "terminal only: meta.checks is terminal" "$j" 'd["meta"]["checks"] == ["terminal"]'

# The TMPDIR of the operator does not change the temp folder of the
# agent: the agent starts with no TMPDIR and writes to /tmp.
mkdir -p "$T/optmp"
: >"$T/mark"
(TMPDIR=$T/optmp && export TMPDIR && kitx trace permission-claude@tmux --checks files) >"$T/t2b" 2>&1
trace_code "operator TMPDIR: exit 0" 0 $? "$T/t2b"
j=$run/traces/03-permission-claude@tmux/trace.json
want "operator TMPDIR: summary.files.tmp holds the temp file of the stub" "$j" 'len(d["summary"]["files"]["tmp"]) > 0 and all(p.startswith("TMP/") for p in d["summary"]["files"]["tmp"])'
want "operator TMPDIR: no path names the folder" "$j" '"optmp" not in json.dumps(d)'

# The ebpf check with no bpftrace: a skip, not a failure. The folder number
# is 04.
: >"$T/mark"
(KIT_BPFTRACE=$T/none && export KIT_BPFTRACE && kitx trace permission-claude@tmux --checks terminal,ebpf) >"$T/t3" 2>&1
trace_code "ebpf, no bpftrace: exit 0" 0 $? "$T/t3"
j=$run/traces/04-permission-claude@tmux/trace.json
want "ebpf, no bpftrace: the skip no-bpftrace" "$j" '{"check": "ebpf", "reason": "no-bpftrace"} in d["meta"]["skipped"] and d["meta"]["checks"] == ["terminal"]'

# Bad use.
kitx trace permission-claude@tmux --checks terminal,disk >"$T/t3" 2>&1
expect_code "an unknown check: exit 2" 2 $?
kitx trace --bogus permission-claude@tmux >"$T/t3" 2>&1
expect_code "an unknown option: exit 2" 2 $?
kitx trace >"$T/t3" 2>&1
expect_code "no step: exit 2" 2 $?
kitx trace no-such-step@tmux >"$T/t3" 2>&1
expect_code "an unknown step: exit 2" 2 $?
if [ ! -e "$run/.trace" ] && [ ! -e "$run/traces/05-permission-claude@tmux" ]; then pass "bad use: no trace folder"; else fail "bad use: no trace folder" "a folder exists"; fi

# A step that fails: the agent shows no idle screen.
cp "$B/claude" "$T/stub-claude"
cp "$T/other/claude" "$B/claude"
kitx trace permission-claude@tmux >"$T/t4" 2>&1
rc4=$?
expect_code "failed step: exit 1" 1 "$rc4"
[ "$rc4" = 1 ] || sed "s/^/  | /" "$T/t4"
cp "$T/stub-claude" "$B/claude"
expect_line "failed step: the step line" '^step: permission-claude@tmux fail no-idle' "$T/t4"
j=$run/traces/05-permission-claude@tmux/trace.json
expect_file "failed step: trace.json exists" "$j"
want "failed step: the state start" "$j" '"start" in [s["state"] for s in d["states"]]'
if [ -z "$(trace_pids)" ]; then pass "failed step: no trace pid stays"; else fail "failed step: no trace pid stays" "$(trace_pids)"; fi

# A step that skips before a session starts: the terminal check gets the
# reason no-cast. The agent must not be on PATH.
if [ -z "$(PATH="$B:$SYS_PATH" command -v codex)" ]; then
  (cd "$D" && HOME=$H PATH="$B:$SYS_PATH" AGENT_SIGNALS_WATCH=3 sh "$ROOT/probes/agent/kit.sh" trace permission-codex@tmux </dev/null) >"$T/t5" 2>&1
  expect_code "skipped step: exit 3" 3 $?
  j=$run/traces/06-permission-codex@tmux/trace.json
  want "skipped step: terminal no-cast" "$j" '{"check": "terminal", "reason": "no-cast"} in d["meta"]["skipped"] and d["terminal"] is None'
  want "skipped step: the step name is the meta step" "$j" 'd["meta"]["step"] == "permission-codex@tmux"'
else
  echo "pass: skip the skipped step, codex is on the system PATH"
fi

# A second trace while a trace runs: exit 2.
: >"$T/mark"
(WATCH=10 && export WATCH && kitx trace permission-claude@tmux) >"$T/t6" 2>&1 &
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
trace_code "the first trace: exit 0" 0 $? "$T/t6"
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

# KILL of "kit trace": no trap runs. The recorders see that their parent
# is gone and stop. The file watcher deletes its folder in /tmp. The next
# "kit trace" removes RUN/.trace.
(cd "$D" && HOME=$H PATH="$B:$PATH" AGENT_SIGNALS_WATCH=30 exec sh "$ROOT/probes/agent/kit.sh" trace permission-claude@tmux </dev/null) >"$T/tk" 2>&1 &
kpid=$!
bg_pid "$kpid"
n=0
while ! grep -q 'dialog' "$run/.trace/states.tsv" 2>/dev/null && [ "$n" -lt 300 ]; do
  sleep 0.1
  n=$((n + 1))
done
rec=$(trace_pids)
fdir=$(cat "$run/.trace/files-dir" 2>/dev/null)
# The children of kit trace: the recorders and the step.
kids=$(ps -A -o pid= -o ppid= | awk -v p="$kpid" '$2 == p { print $1 }' | tr '\n' ' ')
for p in $kids; do bg_pid "$p"; done
if [ -n "$rec" ] && [ -n "$fdir" ] && [ -d "$fdir" ]; then pass "KILL: the recorders and the watcher folder exist"; else fail "KILL: the recorders and the watcher folder exist" "rec '$rec' dir '$fdir'"; fi
kill -9 "$kpid"
wait "$kpid" 2>/dev/null
n=0
while [ "$n" -lt 50 ]; do
  left=
  for p in $rec; do kill -0 "$p" 2>/dev/null && left=1; done
  [ -n "$left" ] || break
  sleep 0.1
  n=$((n + 1))
done
if [ -z "$left" ]; then pass "KILL: the recorders stop when kit trace is gone"; else fail "KILL: the recorders stop when kit trace is gone" "a recorder runs"; fi
if [ -n "$fdir" ] && [ ! -e "$fdir" ]; then pass "KILL: the watcher deletes its folder with the real paths"; else fail "KILL: the watcher deletes its folder with the real paths" "$fdir exists"; fi
# The step runs on with no parent. RUN/.trace/step names it, and the next
# trace stops it by its pid.
spid=$(cut -f1 "$run/.trace/step" 2>/dev/null)
case " $kids " in
  *" $spid "*) pass "KILL: RUN/.trace/step names the step" ;;
  *) fail "KILL: RUN/.trace/step names the step" "'$spid' not in '$kids'" ;;
esac
if kill -0 "$spid" 2>/dev/null; then pass "KILL: the step still runs"; else fail "KILL: the step still runs" "no pid"; fi
if [ -d "$run/.trace" ]; then pass "KILL: RUN/.trace stays"; else fail "KILL: RUN/.trace stays" "no folder"; fi
# The processes below the step, for example the step script, must stop too.
stree=$(ps -A -o pid= -o ppid= | awk -v r="$spid" '
  { kid[$2] = kid[$2] " " $1 }
  END { q[1] = r; n = 1
        for (i = 1; i <= n; i++) { if (i > 1) print q[i]; m = split(kid[q[i]], k, " "); for (j = 1; j <= m; j++) q[++n] = k[j] } }')
if [ -n "$stree" ]; then pass "KILL: the step has processes below it"; else fail "KILL: the step has processes below it" "none"; fi
# RUN/.trace changed less than one minute ago, but its owner file names a
# pid that does not run: the next trace does not wait for the grace time.
: >"$T/mark"
kitx trace permission-claude@tmux --checks terminal >"$T/tk2" 2>&1
trace_code "after KILL: the next trace exits 0" 0 $? "$T/tk2"
expect_line "after KILL: the next trace removes the old folder" '^kit: removed the folder of a stopped trace' "$T/tk2"
expect_line "after KILL: the next trace gives its folder" '^trace: .*/traces/[0-9]+-permission-claude@tmux$' "$T/tk2"
if [ ! -e "$run/.trace" ]; then pass "after KILL: no RUN/.trace stays"; else fail "after KILL: no RUN/.trace stays" "it exists"; fi
if [ -z "$(trace_pids)" ]; then pass "after KILL: no trace pid stays"; else fail "after KILL: no trace pid stays" "$(trace_pids)"; fi
left=
for p in $kids; do kill -0 "$p" 2>/dev/null && left="$left $p"; done
if [ -z "$left" ]; then pass "after KILL: the next trace stopped the old step"; else fail "after KILL: the next trace stopped the old step" "pids$left run"; fi
left=
for p in $stree; do kill -0 "$p" 2>/dev/null && left="$left $p"; done
if [ -z "$left" ]; then pass "after KILL: no process below the old step stays"; else fail "after KILL: no process below the old step stays" "pids$left run"; fi

# A RUN/.trace with no owner file: a new trace can be between its mkdir
# and its owner file. For one minute it counts as a trace that runs.
mkdir "$run/.trace"
kitx trace permission-claude@tmux --checks terminal >"$T/tn" 2>&1
expect_code "no owner: a young folder is a trace that runs, exit 2" 2 $?
expect_line "no owner: the text" 'another trace runs in this run' "$T/tn"
if [ -d "$run/.trace" ]; then pass "no owner: the young folder stays"; else fail "no owner: the young folder stays" "no folder"; fi
touch -t 202001010000 "$run/.trace"
kitx session stop --all >"$T/tn2" 2>&1
expect_code "no owner: stop --all exits 0" 0 $?
expect_line "no owner: an old folder is removed" '^kit: removed the folder of a stopped trace' "$T/tn2"
if [ ! -e "$run/.trace" ]; then pass "no owner: no RUN/.trace stays"; else fail "no owner: no RUN/.trace stays" "it exists"; fi

# An owner file with the pid 0 and no start time is a bad owner file: an
# old folder is removed (kill -0 0 always works).
mkdir "$run/.trace"
printf '0\t\n' >"$run/.trace/owner"
touch -t 202001010000 "$run/.trace"
kitx session stop --all >"$T/tz" 2>&1
expect_code "owner pid 0: stop --all exits 0" 0 $?
if [ ! -e "$run/.trace" ]; then pass "owner pid 0: an old folder is removed"; else fail "owner pid 0: an old folder is removed" "it exists"; fi
rm -rf "$run/.trace"

# "kit session stop --all" also removes what a stopped trace left: a
# recorder in RUN/pids/ (here a sleep with the label "trace files"), the
# watcher folder and RUN/.trace.
mkdir "$run/.trace"
sh -c 'exit 0' &
dead=$!
wait "$dead"
printf '%s\tnone\n' "$dead" >"$run/.trace/owner"
sleep 300 &
spid=$!
bg_pid "$spid"
printf 'trace files\t%s\n' "$(LC_ALL=C ps -o lstart= -p "$spid" | tr -s ' ' | sed 's/^ //; s/ $//')" >"$run/pids/$spid"
fdir=$(mktemp -d /tmp/as-trace.XXXXXX)
: >"$fdir/files.jsonl"
printf '%s\n' "$fdir" >"$run/.trace/files-dir"
kitx session stop --all >"$T/sa" 2>&1
expect_code "stop --all: exit 0" 0 $?
expect_line "stop --all: the line of the removed folder" '^kit: removed the folder of a stopped trace' "$T/sa"
if kill -0 "$spid" 2>/dev/null; then fail "stop --all: the recorder stops" "pid runs"; else pass "stop --all: the recorder stops"; fi
if [ ! -e "$fdir" ]; then pass "stop --all: the watcher folder is deleted"; else fail "stop --all: the watcher folder is deleted" "it exists"; fi
if [ ! -e "$run/.trace" ]; then pass "stop --all: RUN/.trace is deleted"; else fail "stop --all: RUN/.trace is deleted" "it exists"; fi
rm -rf "$fdir"

# A resume step starts the session two times. The fake model writes its
# settings files again on the second start. They are files of the kit.
# The guided watch of the step can fail in a test folder, so the exit
# code of the step is not checked. The trace is written in all cases.
stub_set
kitx trace resume-claude@tmux --checks files >"$T/t12" 2>&1
j=$(sed -n 's/^trace: //p' "$T/t12")/trace.json
expect_file "resume: trace.json exists" "$j"
want "resume: two starts" "$j" '[s["state"] for s in d["states"]].count("start") == 2'
want "resume: no settings file of the fake model" "$j" 'not any(p.startswith(("~", "WORK")) and p.endswith(("settings.json", ".claude.json", ".new")) for e in ev for p in (e.get("path", ""), e.get("from", "")))'
want "resume: the file of the stub stays" "$j" '"WORK/stub-work.txt" in d["summary"]["files"]["work"]'
stub_set STUB_TRUST=yes

private "fixture run: no file in RUN/traces holds the test folder or a name" "$run/traces"

# The real home: HOME is a folder of the test.
R=$T/realhome
mkdir -p "$R"
D2=$T/out2
mkdir -m 0700 "$D2"
kitr() {
  (cd "$D2" && HOME=$R PATH="$B:$PATH" AGENT_SIGNALS_WATCH=6 \
    KITSH=$ROOT/probes/agent/kit.sh "$T/orch/claude" "$@" </dev/null)
}
kitr start --home real --out "$D2" >"$T/log" 2>&1
expect_code "real home: kit start exits 0" 0 $?
run=$(run_of "$D2")
: >"$T/mark"
kitr trace permission-claude@tmux >"$T/t8" 2>&1
trace_code "real home: exit 0" 0 $? "$T/t8"
tr8=$run/traces/01-permission-claude@tmux
j=$tr8/trace.json
want "real home: home paths start with ~" "$j" 'any(e.get("path", "").startswith("~/.claude/") for e in ev) and all(not e.get("path", "").startswith("/") for e in ev if e["kind"] != "proxy")'
want "real home: no terminal" "$j" 'd["terminal"] is None and "terminal" not in d["meta"]["checks"]'
want "real home: login mode, the terminal is skipped" "$j" 'd["meta"]["mode"] == "login" and {"check": "terminal", "reason": "not-fixture-home"} in d["meta"]["skipped"]'
if [ ! -e "$tr8/terminal.cast" ]; then pass "real home: no cast"; else fail "real home: no cast" "file exists"; fi
if grep -rlF -- "$R" "$tr8" >/dev/null 2>&1; then fail "real home: the home path is in no file" "found"; else pass "real home: the home path is in no file"; fi
private "real home: no file in RUN/traces holds the test folder or a name" "$run/traces"

# A real home with more folders than the walk limit. The work root has its
# watches first, so the file of the stub in WORK is in the trace.
k=0
while [ "$k" -lt 80 ]; do
  mkdir -p "$R/folder$k"
  k=$((k + 1))
done
: >"$T/mark"
(KIT_TRACE_WATCH_LIMIT=64 && export KIT_TRACE_WATCH_LIMIT && kitr trace permission-claude@tmux) >"$T/t10" 2>&1
trace_code "real home, small limit: exit 0" 0 $? "$T/t10"
j=$run/traces/02-permission-claude@tmux/trace.json
want "real home, small limit: files_limit is true" "$j" 'd["meta"]["files_limit"] is True'
want "real home, small limit: the file of the stub in WORK" "$j" '"WORK/stub-work.txt" in d["summary"]["files"]["work"]'
want "real home, small limit: a file in ~/.claude" "$j" 'any(p.startswith("~/.claude/") for p in d["summary"]["files"]["home"])'

# A throwaway home: the mode none. The step needs a login, so it skips
# with exit 0.
D3=$T/out3
mkdir -m 0700 "$D3"
kitt() {
  (cd "$D3" && HOME=$H PATH="$B:$PATH" AGENT_SIGNALS_WATCH=6 \
    KITSH=$ROOT/probes/agent/kit.sh "$T/orch/claude" "$@" </dev/null)
}
kitt start --home throwaway --out "$D3" >"$T/log" 2>&1
expect_code "throwaway home: kit start exits 0" 0 $?
run=$(run_of "$D3")
: >"$T/mark"
kitt trace permission-claude@tmux >"$T/t11" 2>&1
trace_code "throwaway home: exit 0" 0 $? "$T/t11"
expect_line "throwaway home: the step skips with no-login" '^step: permission-claude@tmux skip no-login' "$T/t11"
j=$run/traces/01-permission-claude@tmux/trace.json
want "throwaway home: the mode is none" "$j" 'd["meta"]["mode"] == "none" and d["meta"]["home"] == "throwaway"'
validate "throwaway home: trace.json passes the schema check" "$run/traces/01-permission-claude@tmux"

done_tests
