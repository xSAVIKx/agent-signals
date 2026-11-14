# shellcheck shell=sh
# shellcheck disable=SC2154 # _fail comes from lib.sh.
# The ebpf check of "kit trace" (probes/agent/trace.sh, step 4b): the start
# of bpftrace, its ready check, its skips, its stop, the hang-up time of
# session.sh, and the build of the events. Linux only.
#
# By default, the test puts a stub sudo first in PATH (it drops -n and runs
# the rest with exec; NO_SUDO=1 makes it exit 1) and sets KIT_BPFTRACE to
# fake-bpftrace.py, which polls /proc. A missing tmux is then a skip.
#
# KIT_TEST_EBPF=real uses the real bpftrace (or KIT_BPFTRACE when it is
# set) and the real sudo. Then a missing tmux, bpftrace or "sudo -n" is a
# failure, and the test also checks the events that only the kernel sees:
# an open, a connect, a dns call and the time of the first exec. When a
# case fails, the test prints the stderr of "kit trace" through
# tools/scrub.sh.
. "${ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}/tools/agent-kit-tests/lib.sh"

if [ "$(uname -s)" != Linux ]; then
  echo "pass: skip not Linux"
  done_tests
fi
real=
[ "${KIT_TEST_EBPF:-}" = real ] && real=1
if ! command -v tmux >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
  if [ -n "$real" ]; then
    fail "real mode: the tools" "no tmux or no python3"
  else
    echo "pass: skip no tmux or no python3"
  fi
  done_tests
fi
. "$ROOT/tools/agent-kit-tests/core-lib.sh"
. "$ROOT/tools/agent-kit-tests/steps-lib.sh"

# The stub sudo and a copy of the fake tracer. The copy is in $T, so that
# the check of lib.sh sees a fake tracer that stays.
mkdir -p "$T/sbin"
cat >"$T/sbin/sudo" <<'EOF'
#!/bin/sh
[ -n "${NO_SUDO:-}" ] && exit 1
[ "${1:-}" = -n ] && shift
exec "$@"
EOF
chmod 755 "$T/sbin/sudo"
cp "$ROOT/tools/agent-kit-tests/fake-bpftrace.py" "$T/fake-bpftrace.py"
chmod 755 "$T/fake-bpftrace.py"
if [ -n "$real" ]; then
  bt=${KIT_BPFTRACE:-$(command -v bpftrace 2>/dev/null)}
  if [ -z "$bt" ] || [ ! -f "$bt" ]; then
    fail "real mode: bpftrace" "no bpftrace"
    done_tests
  fi
  if ! sudo -n true </dev/null >/dev/null 2>&1; then
    fail "real mode: sudo -n" "sudo -n true fails"
    done_tests
  fi
  echo "pass: real mode with $bt"
else
  PATH=$T/sbin:$PATH
  KIT_BPFTRACE=$T/fake-bpftrace.py
  export PATH KIT_BPFTRACE
fi

# The checker: "q.py FILE EXPR" evaluates EXPR with the document as d and
# exits 0 when the value is true.
cat >"$T/q.py" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
ev = d["events"]
st = {s["state"]: s["t"] for s in reversed(d["states"])}
sys.exit(0 if eval(sys.argv[2]) else 1)
PYEOF
# want NAME FILE EXPR: pass when EXPR is true for FILE.
want() {
  if python3 -I "$T/q.py" "$2" "$3" 2>/dev/null; then pass "$1"; else fail "$1" "false: $3"; fi
}

# show_err FILE: in the real mode, print the stderr of "kit trace" through
# the scrub, for the log of the runner.
show_err() {
  [ -n "$real" ] && [ -f "$1" ] || return 0
  echo "  stderr of kit trace:"
  sh "$ROOT/tools/scrub.sh" "$1" 2>/dev/null | sed 's/^/  | /'
}

# private NAME DIR: pass when no file below DIR holds $T, the account name
# or the host name (as in test-trace.sh).
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

# ebpf_pids: the pid files of $run/pids/ with an ebpf label.
ebpf_pids() {
  for _f in "$run"/pids/*; do
    [ -f "$_f" ] || continue
    case $(cut -f1 "$_f") in "trace ebpf" | "trace ebpf stop") echo "${_f##*/}" ;; esac
  done
}
# folder_of FILE: the trace folder of the output of "kit trace".
folder_of() { sed -n 's/^trace: //p' "$1" | tail -n 1; }
# kitf ARGS: "kit ARGS" with the stub sudo and the fake tracer, also in
# the real mode.
kitf() {
  (PATH=$T/sbin:$PATH && KIT_BPFTRACE=$T/fake-bpftrace.py && export PATH KIT_BPFTRACE && kitx "$@")
}

# WATCH caps each wait of a step. 3 s was too short for the idle wait on a
# busy CPU.
WATCH=6
export WATCH
kitx start --home fixture --out "$D" >"$T/log" 2>&1
expect_code "kit start exits 0" 0 $?
run=$(run_of "$D")
stub_set STUB_TRUST=yes STUB_SPAWN=yes STUB_LEAVE=yes

# The full trace with all checks. While it runs, the test keeps a copy of
# the raw ebpf.txt and sessions.tsv: the trace deletes its raw folder at
# the end. KIT_TEST_EBPF_RAW=DIR copies them to DIR after the trace.
kitx trace permission-claude@tmux --checks terminal,network,files,ebpf >"$T/t1" 2>"$T/t1.err" &
tpid=$!
bg_pid "$tpid"
while kill -0 "$tpid" 2>/dev/null; do
  for f in ebpf.txt ebpf.err sessions.tsv; do
    [ -s "$run/.trace/$f" ] && cat "$run/.trace/$f" >"$T/raw-$f.tmp" 2>/dev/null && mv "$T/raw-$f.tmp" "$T/raw-$f"
  done
  sleep 0.2
done
wait "$tpid"
rc=$?
if [ -n "${KIT_TEST_EBPF_RAW:-}" ]; then
  mkdir -p "$KIT_TEST_EBPF_RAW"
  for f in ebpf.txt ebpf.err sessions.tsv; do
    [ -f "$T/raw-$f" ] && cat "$T/raw-$f" >"$KIT_TEST_EBPF_RAW/$f"
  done
fi
expect_code "ebpf: exit 0" 0 "$rc"
[ "$rc" = 0 ] || { sed "s/^/  out| /" "$T/t1"; sh "$ROOT/tools/scrub.sh" "$T/t1.err" 2>/dev/null | tail -n 20 | sed "s/^/  err| /"; }
tr1=$(folder_of "$T/t1")
j=$tr1/trace.json
expect_file "ebpf: trace.json exists" "$j"
expect_line "ebpf: the command is on stderr" '^kit: the ebpf check runs: sudo -n env ' "$T/t1.err"
validate "ebpf: trace.json passes the schema check" "$tr1"
want "ebpf: meta.checks holds ebpf" "$j" 'd["meta"]["checks"] == ["terminal", "network", "files", "ebpf"]'
want "ebpf: an exec of bin/claude" "$j" 'any(e["kind"] == "exec" and e["path"].endswith("/bin/claude") for e in ev)'
want "ebpf: one process left, python3" "$j" 'len(d["summary"]["processes_left"]) == 1 and "python3" in d["summary"]["processes_left"][0]["program"]'
# This case failed one time on ubuntu-26.04-arm: print the list then.
python3 -I -c '
import json, sys
p = json.load(open(sys.argv[1], encoding="utf-8"))["summary"]["processes_left"]
if not (len(p) == 1 and "python3" in p[0]["program"]):
    for x in p or []:
        print("  left| %s %s %s" % (x.get("pid"), x.get("ppid"), x.get("program")))' "$j" 2>/dev/null
want "ebpf: meta.ebpf_lost is an integer" "$j" 'isinstance(d["meta"]["ebpf_lost"], int)'
if [ -n "$real" ]; then
  want "real: an open for write in WORK" "$j" 'any(e["kind"] == "open" and e["mode"] == "w" and e["path"].startswith("WORK/") for e in ev)'
  want "real: a connect to 127.0.0.1 port 9" "$j" 'any(e["kind"] == "connect" and e["host"] == "127.0.0.1" and e["port"] == 9 for e in ev)'
  want "real: a dns call for localhost" "$j" 'any(e["kind"] == "dns" and e["name"] == "localhost" for e in ev)'
  want "real: the first exec of the stub is within 3000 ms of the start" "$j" 'abs([e["t"] for e in ev if e["kind"] == "exec" and e["path"].endswith("/bin/claude")][0] - st["start"]) <= 3000'
  # The facts for the report of the runner: no path, only counts.
  python3 -I -c '
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
kinds = {}
for e in d["events"]:
    kinds[e["kind"]] = kinds.get(e["kind"], 0) + 1
print("  facts: ebpf_lost=%s kinds=%s" % (d["meta"]["ebpf_lost"], json.dumps(kinds, sort_keys=True)))' "$j" 2>/dev/null
  # The open counters of the script: entries and returns.
  grep '^counters' "$T/raw-ebpf.txt" 2>/dev/null | sed 's/^/  facts: /'
  # After a failure: the scrubbed open paths that are not system paths,
  # and the connect events.
  if [ "$_fail" != 0 ]; then
    python3 -I -c '
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
for e in d["events"]:
    if e["kind"] == "connect" or (e["kind"] == "open" and not e["path"].startswith(("/usr/", "/lib", "/etc/"))):
        print("  event:", json.dumps({k: e.get(k) for k in ("kind", "pid", "path", "mode", "ok", "host", "port", "family")}))' "$j" 2>/dev/null | head -n 40
    # The raw lines of the agent pid, and each raw line about stub-work.
    apid=$(cut -f4 "$T/raw-sessions.tsv" 2>/dev/null | head -n 1)
    echo "  raw: agent pid '$apid', $(wc -l <"$T/raw-ebpf.txt" 2>/dev/null) lines"
    grep -i 'lost' "$T/raw-ebpf.err" 2>/dev/null | head -n 5 | sed 's/^/  raw err| /'
    awk -F '\t' '{ n[$2]++ } END { for (w in n) printf "  raw: %s %d\n", w, n[w] }' "$T/raw-ebpf.txt" 2>/dev/null | sort
    awk -F '\t' '{ n[$3]++ } END { for (p in n) print n[p], p }' "$T/raw-ebpf.txt" 2>/dev/null | sort -rn | head -n 5 | sed 's/^/  raw: lines of pid: /'
    awk -F '\t' -v a="$apid" '($3 == a && $2 != "fork" && $NF !~ /^\/(dev\/null|tmp\/tmp\.[A-Za-z0-9]+)$/) || /stub-work/' "$T/raw-ebpf.txt" 2>/dev/null |
      sed "s|$T|\$T|g" | head -n 60 | sed 's/^/  raw| /'
  fi
fi
if [ "$_fail" != 0 ]; then show_err "$T/t1.err"; fi
private "ebpf: no file in RUN/traces holds the test folder or a name" "$run/traces"
if [ -z "$(ebpf_pids)" ]; then pass "ebpf: no ebpf pid stays in RUN/pids"; else fail "ebpf: no ebpf pid stays in RUN/pids" "$(ebpf_pids)"; fi
stub_set STUB_TRUST=yes

# The skips. Each skip gives exit 0 and the other checks.
# skip_case NAME OUT REASON: the trace of OUT has the skip REASON and no
# ebpf in meta.checks.
skip_case() {
  _j=$(folder_of "$2")/trace.json
  want "$1: the skip $3" "$_j" '{"check": "ebpf", "reason": "'"$3"'"} in d["meta"]["skipped"] and "ebpf" not in d["meta"]["checks"] and "terminal" in d["meta"]["checks"]'
}
(NO_SUDO=1 && export NO_SUDO && kitf trace permission-claude@tmux --checks terminal,ebpf) >"$T/t2" 2>"$T/t2.err"
expect_code "no sudo: exit 0" 0 $?
skip_case "no sudo" "$T/t2" no-sudo

(KIT_BPFTRACE=$T/none && export KIT_BPFTRACE && kitx trace permission-claude@tmux --checks terminal,ebpf) >"$T/t3" 2>"$T/t3.err"
expect_code "no bpftrace: exit 0" 0 $?
skip_case "no bpftrace" "$T/t3" no-bpftrace

(FAKE_BPFTRACE=fail && export FAKE_BPFTRACE && kitf trace permission-claude@tmux --checks terminal,ebpf) >"$T/t4" 2>"$T/t4.err"
expect_code "bpftrace fails: exit 0" 0 $?
skip_case "bpftrace fails" "$T/t4" bpftrace-failed
expect_line "bpftrace fails: stderr holds its error" '^kit: ERROR: test$' "$T/t4.err"
if [ -z "$(ebpf_pids)" ]; then pass "bpftrace fails: no ebpf pid stays"; else fail "bpftrace fails: no ebpf pid stays" "$(ebpf_pids)"; fi

(FAKE_BPFTRACE=silent KIT_EBPF_READY_TURNS=4 && export FAKE_BPFTRACE KIT_EBPF_READY_TURNS &&
  kitf trace permission-claude@tmux --checks terminal,ebpf) >"$T/t5" 2>"$T/t5.err"
expect_code "no ready: exit 0" 0 $?
skip_case "no ready" "$T/t5" no-ready
if [ -z "$(ebpf_pids)" ]; then pass "no ready: no ebpf pid stays"; else fail "no ready: no ebpf pid stays" "$(ebpf_pids)"; fi

# bpftrace ends after the ready check and before the end of the step: a
# skip, so that the trace does not show an incomplete record as a full one.
(FAKE_BPFTRACE=short && export FAKE_BPFTRACE && kitf trace permission-claude@tmux --checks terminal,ebpf) >"$T/t6" 2>"$T/t6.err"
expect_code "tracer ends early: exit 0" 0 $?
skip_case "tracer ends early" "$T/t6" tracer-ended
expect_line "tracer ends early: stderr says so" '^kit: bpftrace ended before the end of the step' "$T/t6.err"
expect_line "tracer ends early: stderr holds its error" '^kit: ERROR: short$' "$T/t6.err"
if [ -z "$(ebpf_pids)" ]; then pass "tracer ends early: no ebpf pid stays"; else fail "tracer ends early: no ebpf pid stays" "$(ebpf_pids)"; fi

# The fake tracer: a zombie has ended. The parent of the zombie does not
# wait for it, so the pid stays in /proc with the state Z.
sleep 300 &
zstop=$!
bg_pid "$zstop"
FAKE_BPFTRACE_READY=$T/z.ready python3 -I "$T/fake-bpftrace.py" -B line none "$$" "$zstop" >"$T/z.txt" 2>"$T/z.err" &
zfake=$!
bg_pid "$zfake"
# Start the child after the first scan of the fake: 10 s at most.
i=0
while [ ! -e "$T/z.ready" ] && [ "$i" -lt 100 ]; do
  sleep 0.1
  i=$((i + 1))
done
[ -e "$T/z.ready" ] || fail "fake tracer: the first scan ends" "no ready file in 10 s"
# The child lives 0.3 s, then stays a zombie until its parent ends at 3 s.
# The fake stops at 1.5 s, while the zombie is still in /proc.
python3 -I -c '
import os, sys, time
kid = os.fork()
if kid == 0:
    time.sleep(0.3)
    os._exit(0)
with open(sys.argv[1], "w") as f:
    f.write("%d\n" % kid)
time.sleep(3)' "$T/z.pid" &
zpar=$!
bg_pid "$zpar"
sleep 1.5
kill "$zstop"
wait "$zstop" 2>/dev/null
wait "$zfake" 2>/dev/null
wait "$zpar" 2>/dev/null
zpid=$(cat "$T/z.pid" 2>/dev/null)
if [ -n "$zpid" ] && awk -F '\t' -v p="$zpid" '$2 == "exit" && $3 == p { f = 1 } END { exit f ? 0 : 1 }' "$T/z.txt"; then
  pass "fake tracer: a zombie gives an exit line"
else
  fail "fake tracer: a zombie gives an exit line" "pid '$zpid'"
fi

# KIT_TRACE_KEEP_RAW=1: the trace folder gets raw/, with the scrubbed raw
# files. trace-build.py can build a trace again from that copy.
(KIT_TRACE_KEEP_RAW=1 && export KIT_TRACE_KEEP_RAW &&
  kitx trace permission-claude@tmux --checks terminal,network,files,ebpf) >"$T/t6" 2>"$T/t6.err"
expect_code "keep raw: exit 0" 0 $?
tr6=$(folder_of "$T/t6")
expect_file "keep raw: raw/ebpf.txt exists" "$tr6/raw/ebpf.txt"
expect_file "keep raw: raw/sessions.tsv exists" "$tr6/raw/sessions.tsv"
if grep -rlF -- "$T" "$tr6/raw" >/dev/null 2>&1; then
  fail "keep raw: no file in raw/ holds the test folder" "$(grep -rlF -- "$T" "$tr6/raw" | sed 's|.*/||' | tr '\n' ' ')"
  # The first lines that hold it, with the folder as $T.
  grep -rhF -- "$T" "$tr6/raw" | head -n 8 | awk -v t="$T" '{ while ((i = index($0, t)) > 0) $0 = substr($0, 1, i - 1) "$T" substr($0, i + length(t)); print "  leak| " $0 }'
else
  pass "keep raw: no file in raw/ holds the test folder"
fi
for f in terminal.cast proxy.jsonl files.jsonl; do
  if [ -e "$tr6/raw/$f" ]; then fail "keep raw: no $f in raw/" "it exists"; else pass "keep raw: no $f in raw/"; fi
done
mkdir -p "$T/rebuild"
cp -R "$tr6/raw" "$T/rebuild/.trace"
python3 -I -c '
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
json.dump(d["meta"], open(sys.argv[2], "w", encoding="utf-8"))' "$tr6/trace.json" "$T/rebuild/meta.json"
if python3 -I "$ROOT/probes/agent/trace-build.py" --raw "$T/rebuild/.trace" --meta "$T/rebuild/meta.json" \
  --out "$T/rebuild/out" >"$T/rebuild.log" 2>&1; then
  pass "keep raw: trace-build.py builds from raw/"
  want "keep raw: the new build has ebpf and programs" "$T/rebuild/out/trace.json" '"ebpf" in d["meta"]["checks"] and len(d["summary"]["programs"] or []) > 0'
else
  fail "keep raw: trace-build.py builds from raw/" "$(head -c 400 "$T/rebuild.log")"
fi
# The script ends with one line "counters" with no time: the build skips it.
if awk -F '\t' 'NF > 1 && $1 != "counters" && $1 !~ /^[0-9]+$/ { bad = 1 } END { exit bad }' "$tr6/raw/ebpf.txt"; then
  pass "keep raw: each event line of raw/ebpf.txt starts with the time"
else
  fail "keep raw: each event line of raw/ebpf.txt starts with the time" "a line has another first field"
fi
if [ -d "$tr1/raw" ]; then fail "no keep raw: no raw/ folder" "it exists"; else pass "no keep raw: no raw/ folder"; fi
if [ "$_fail" != 0 ]; then show_err "$T/t6.err"; fi

# tools/check-traces.sh: on a run with the trace of the keep raw case, and
# on a run with that trace and the trace of the no sudo case.
if command -v go >/dev/null 2>&1; then
  n6=${tr6##*/}
  n2=$(folder_of "$T/t2")
  n2=${n2##*/}
  mkdir -p "$T/cr1/traces" "$T/cr2/traces"
  cp -R "$tr6" "$T/cr1/traces/"
  cp -R "$tr6" "$(folder_of "$T/t2")" "$T/cr2/traces/"
  sh "$ROOT/tools/check-traces.sh" "$T/cr1" --passed "$T/passed1" >"$T/c1" 2>&1
  expect_code "check-traces: one good trace exits 0" 0 $?
  expect_line "check-traces: the ok line" "^check: $n6 ok\$" "$T/c1"
  if [ "$(cat "$T/passed1" 2>/dev/null)" = "$n6" ]; then
    pass "check-traces: the passed file holds the trace"
  else
    fail "check-traces: the passed file holds the trace" "$(cat "$T/passed1" 2>/dev/null)"
  fi
  sh "$ROOT/tools/check-traces.sh" "$T/cr2" --passed "$T/passed2" >"$T/c2" 2>&1
  expect_code "check-traces: a trace with no ebpf exits 1" 1 $?
  expect_line "check-traces: the fail line" "^check: $n2 fail " "$T/c2"
  if [ "$(cat "$T/passed2" 2>/dev/null)" = "$n6" ]; then
    pass "check-traces: the passed file holds only the good trace"
  else
    fail "check-traces: the passed file holds only the good trace" "$(cat "$T/passed2" 2>/dev/null)"
  fi
  mkdir -p "$T/cr3"
  sh "$ROOT/tools/check-traces.sh" "$T/cr3" --passed "$T/passed3" >"$T/c3" 2>&1
  expect_code "check-traces: no trace exits 1" 1 $?
  if [ -f "$T/passed3" ] && [ ! -s "$T/passed3" ]; then
    pass "check-traces: no trace gives an empty passed file"
  else
    fail "check-traces: no trace gives an empty passed file" "no file, or not empty"
  fi
  if [ "$_fail" != 0 ]; then sed 's/^/  | /' "$T/c1" "$T/c2"; fi
else
  echo "pass: skip check-traces.sh, go is not on PATH"
fi

# KILL of "kit trace" while the check runs. bpftrace stops when the pid of
# trace.sh ends. The next trace stops the sentinel. "exec" makes $! the
# pid of trace.sh.
(cd "$D" && HOME=$H PATH="$B:$PATH" AGENT_SIGNALS_WATCH=30 exec sh "$ROOT/probes/agent/kit.sh" trace --checks terminal,ebpf permission-claude@tmux </dev/null) >"$T/tk" 2>"$T/tk.err" &
kpid=$!
bg_pid "$kpid"
n=0
while ! grep -q 'dialog' "$run/.trace/states.tsv" 2>/dev/null && [ "$n" -lt 300 ]; do
  sleep 0.1
  n=$((n + 1))
done
if [ -f "$run/.trace/ebpf.txt" ]; then pass "KILL: ebpf.txt exists"; else fail "KILL: ebpf.txt exists" "no file"; fi
eps=$(ebpf_pids | tr '\n' ' ')
kids=$(ps -A -o pid= -o ppid= | awk -v p="$kpid" '$2 == p { print $1 }' | tr '\n' ' ')
for p in $kids; do bg_pid "$p"; done
if [ "$(echo $eps | wc -w | tr -d ' ')" = 2 ]; then pass "KILL: two ebpf pids run"; else fail "KILL: two ebpf pids run" "'$eps'"; fi
kill -9 "$kpid"
wait "$kpid" 2>/dev/null
kitx trace permission-claude@tmux --checks terminal >"$T/tk2" 2>&1
expect_code "after KILL: the next trace exits 0" 0 $?
expect_line "after KILL: the next trace removes the old folder" '^kit: removed the folder of a stopped trace' "$T/tk2"
left=
for p in $eps; do kill -0 "$p" 2>/dev/null && left="$left $p"; done
if [ -z "$left" ]; then pass "after KILL: no ebpf pid runs"; else fail "after KILL: no ebpf pid runs" "pids$left run"; fi
if [ -z "$(ebpf_pids)" ]; then pass "after KILL: no ebpf pid file stays"; else fail "after KILL: no ebpf pid file stays" "$(ebpf_pids)"; fi
if [ -z "$real" ]; then
  # The fake tracer has $T in its command line.
  if [ -z "$(ps -A -o args= | grep -F "$T/fake-bpftrace.py" | grep -v grep)" ]; then
    pass "after KILL: no fake tracer stays"
  else
    fail "after KILL: no fake tracer stays" "a process runs"
  fi
fi
if [ "$_fail" != 0 ]; then show_err "$T/tk.err"; fi

# session.sh: the hang-up time, only with the ebpf check.
# An empty list selects the terminal check, whose recorder reads t0.
mkdir -p "$T/kt1" "$T/kt2"
python3 -I -c 'import time; print(time.time_ns() // 1000000)' >"$T/kt2/t0"
(KIT_TRACE=$T/kt1 KIT_TRACE_CHECKS=ebpf && export KIT_TRACE KIT_TRACE_CHECKS &&
  kitx session start hs claude --via tmux && kitx session stop hs) >"$T/s1" 2>&1
expect_code "hang-up: start and stop exit 0" 0 $?
if [ "$(awk -F '\t' '$2 == "hs" && $1 ~ /^[0-9]+$/' "$T/kt1/hangup.tsv" 2>/dev/null | wc -l | tr -d ' ')" = 1 ]; then
  pass "hang-up: one line in hangup.tsv"
else
  fail "hang-up: one line in hangup.tsv" "$(cat "$T/kt1/hangup.tsv" 2>/dev/null)"
fi
(KIT_TRACE=$T/kt2 KIT_TRACE_CHECKS= && export KIT_TRACE KIT_TRACE_CHECKS &&
  kitx session start hs claude --via tmux && kitx session stop hs) >"$T/s2" 2>&1
rc=$?
expect_code "no ebpf: start and stop exit 0" 0 "$rc"
[ "$rc" = 0 ] || sed 's/^/  | /' "$T/s2"
if [ ! -e "$T/kt2/hangup.tsv" ]; then pass "no ebpf: no hangup.tsv"; else fail "no ebpf: no hangup.tsv" "it exists"; fi

done_tests
