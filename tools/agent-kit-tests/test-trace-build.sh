# shellcheck shell=sh
# The build of trace.json: trace-build.py.
. "${ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}/tools/agent-kit-tests/lib.sh"

build=$ROOT/probes/agent/trace-build.py
raw0=$ROOT/tools/testdata/trace/raw
H=$T/helpers
mkdir "$H"

# The checker: "q.py FILE EXPR" evaluates EXPR with the document as d and
# exits 0 when the value is true.
cat >"$H/q.py" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
ev = d["events"]
sys.exit(0 if eval(sys.argv[2]) else 1)
PYEOF

cat >"$H/meta.json" <<'JEOF'
{"agent": "claude", "agent_version": "2.1.319", "kit": "0.1.0", "os": "linux",
 "os_version": "6.12", "cpu": "x86_64", "runner_image": null,
 "machine": "real", "backend": "tmux", "mode": "fixture",
 "home": "fixture", "step": "permission", "date": "2026-11-09"}
JEOF
sed 's/"home": "fixture"/"home": "real"/' "$H/meta.json" >"$H/meta-real.json"
sed 's/"mode": "fixture"/"mode": "login"/' "$H/meta.json" >"$H/meta-login.json"

# mkraw NAME: copy the raw test folder to $T/NAME/.trace.
mkraw() {
  mkdir -p "$T/$1/.trace"
  for _f in "$raw0"/*; do cp "$_f" "$T/$1/.trace/"; done
}
# run_build NAME META: build into $T/NAME/out, the names are fixed.
run_build() {
  (
    TMPDIR=/tmp/example
    SCRUB_USER=alice
    SCRUB_HOST=build01.corp.internal
    export TMPDIR SCRUB_USER SCRUB_HOST
    python3 -I "$build" --raw "$T/$1/.trace" --meta "$2" --out "$T/$1/out"
  ) >"$T/$1.log" 2>&1
}
# want NAME NAMEDIR EXPR: pass when EXPR is true for $T/NAMEDIR/out/trace.json.
want() {
  if python3 -I "$H/q.py" "$T/$2/out/trace.json" "$3"; then pass "$1"; else fail "$1" "false: $3"; fi
}

# The main run.
mkraw main
# A file event under the run folder, but not under a home or a work folder.
printf '{"t": 1700000002000, "kind": "create", "path": "%s/main/sessions/a/x", "dir": false}\n' "$T" >>"$T/main/.trace/files.jsonl"
run_build main "$H/meta.json"
expect_code "build: exit 0" 0 $?

want "times: integers from 0" main 'all(isinstance(e["t"], int) and e["t"] >= 0 for e in ev) and all(isinstance(s["t"], int) and s["t"] >= 0 for s in d["states"])'
want "events are sorted by t" main '[e["t"] for e in ev] == sorted(e["t"] for e in ev)'
want "states: 8 states" main '[s["state"] for s in d["states"]][:3] == ["start", "idle", "prompt"] and len(d["states"]) == 8'
want "provenance is measured" main 'd["provenance"] == "measured"'
want "hex run in a name" main 'any(e.get("path") == "~/.claude/x-<hex>.json" for e in ev)'
want "work path is WORK/" main 'any(e.get("path") == "WORK/note.txt" for e in ev)'
want "tmp path is TMP/" main 'any(e.get("path") == "TMP/agent.lock" for e in ev)'
want "uuid and digits in a name" main 'any(e.get("path") == "~/.cache/agent-<uuid>-<n>/s" for e in ev)'
want "a file event under the run folder is dropped" main 'not any("sessions" in e.get("path", "") for e in ev)'
want "a file event under SOCKDIR is dropped" main 'not any("sock" in e.get("path", "") or e.get("path") == "TMP/sock-a/ready" for e in ev)'
want "account name becomes dev" main 'any(e.get("path") == "~/.cache/dev-notes/a.txt" for e in ev)'
want "full host name becomes host" main 'any(e.get("path") == "~/.cache/host/b.txt" for e in ev)'
want "short host name with a domain becomes host" main 'any(e.get("path") == "~/.cache/host/c.txt" for e in ev)'
want "no account or host name stays" main '"alice" not in json.dumps(d) and "build01" not in json.dumps(d).lower() and "corp.internal" not in json.dumps(d)'
want "a fixture home keeps a folder of the person" main 'any(e.get("path") == "~/Documents/plan.txt" for e in ev)'
want "duplicate create lines give one event" main 'sum(1 for e in ev if e["kind"] == "create" and e["path"] == "WORK/note.txt") == 1'
want "move has from and path" main 'any(e["kind"] == "move" and e["from"] == "WORK/note.txt" and e["path"] == "WORK/note.md" for e in ev)'
want "an overflow line is not an event" main 'all(e["kind"] in ("create", "write", "delete", "move", "proxy", "model") for e in ev)'
want "limit line sets files_limit" main 'd["meta"]["files_limit"] is True'
want "files by area" main 'd["summary"]["files"]["work"] == ["WORK/before.txt", "WORK/late.txt", "WORK/note.md", "WORK/note.txt"] and d["summary"]["files"]["tmp"] == ["TMP/agent.lock"] and d["summary"]["files"]["other"] == []'
want "files: no duplicates, sorted" main 'all(v == sorted(set(v)) for v in d["summary"]["files"].values())'
want "hosts: two lines of one host give connections 2" main '[h for h in d["summary"]["hosts"] if h["host"] == "api.example.com"][0]["connections"] == 2 and [h for h in d["summary"]["hosts"] if h["host"] == "api.example.com"][0]["up"] == 2148'
want "hosts: one item for each host and port" main 'len(d["summary"]["hosts"]) == 2'
want "proxy event has up, down and end" main 'any(e["kind"] == "proxy" and e["up"] == 2048 and e["down"] == 8192 and e["end"] == 6000 and e["status"] == "ok" for e in ev)'
want "model event: method, route with no query, model_kind" main 'any(e["kind"] == "model" and e["method"] == "POST" and e["route"] == "/v1/messages" and e["model_kind"] == "tool" for e in ev)'
want "model event: GET has the kind -" main 'any(e["kind"] == "model" and e["method"] == "GET" and e["model_kind"] == "-" for e in ev)'
want "model: a line that is not a request is not an event" main 'd["summary"]["model_requests"] == 2'
want "model: no query text in the output" main '"secret" not in json.dumps(d)'
want "timeline of dialog holds the event 1 s before" main '[x for x in d["summary"]["timeline"] if x["state"] == "dialog"][0]["near"] and any(n["text"] == "create WORK/before.txt" for n in [x for x in d["summary"]["timeline"] if x["state"] == "dialog"][0]["near"])'
want "timeline of dialog has no event 3 s after" main 'not any(n["text"] == "write WORK/late.txt" for n in [x for x in d["summary"]["timeline"] if x["state"] == "dialog"][0]["near"])'
want "timeline: 20 events at most" main 'all(len(x["near"]) <= 20 for x in d["summary"]["timeline"])'
want "timeline text of a proxy event" main 'any(n["text"] == "proxy api.example.com:443" for x in d["summary"]["timeline"] for n in x["near"])'
want "checks list the raw files" main 'd["meta"]["checks"] == ["terminal", "network", "files"]'
want "skipped is read from skipped.tsv" main 'd["meta"]["skipped"] == [{"check": "ebpf", "reason": "the kernel check did not run"}]'
want "terminal is the cast name" main 'd["terminal"] == "terminal.cast"'
if cmp -s "$T/main/.trace/terminal.cast" "$T/main/out/terminal.cast"; then pass "the cast is copied"; else fail "the cast is copied" "no equal file"; fi
want "programs and processes_left are null" main 'd["summary"]["programs"] is None and d["summary"]["processes_left"] is None'

# The schema check, on a temp root. Skipped when go is missing.
if command -v go >/dev/null 2>&1; then
  R=$T/root
  mkdir -p "$R/schema" "$R/corpus" "$R/facts" "$R/traces/claude/2.1.319/01-permission@tmux"
  for _f in "$ROOT"/schema/*; do cp "$_f" "$R/schema/"; done
  cp "$T/main/out/trace.json" "$T/main/out/terminal.cast" "$R/traces/claude/2.1.319/01-permission@tmux/"
  if (cd "$ROOT/tools" && go run ./cmd/validate "$R") >"$T/validate.log" 2>&1; then
    pass "the trace passes the schema check"
  else
    fail "the trace passes the schema check" "$(head -c 400 "$T/validate.log")"
  fi
else
  echo "pass: skip the schema check, go is not on PATH"
fi

# A real home: a folder of the person is private, a hidden folder stays.
mkraw real
run_build real "$H/meta-real.json"
expect_code "real home: exit 0" 0 $?
want "real home: ~/<private> for a folder of the person" real 'any(e.get("path") == "~/<private>" for e in ev) and not any("Documents" in e.get("path", "") for e in ev)'
want "real home: a hidden folder stays" real 'any(e.get("path") == "~/.config/agent/state.json" for e in ev)'
want "real home: no terminal" real 'd["terminal"] is None and "terminal" not in d["meta"]["checks"]'
if [ ! -e "$T/real/out/terminal.cast" ]; then pass "real home: no cast in the output"; else fail "real home: no cast in the output" "file exists"; fi
if [ ! -e "$T/real/.trace/terminal.cast" ]; then pass "real home: the raw cast is deleted"; else fail "real home: the raw cast is deleted" "file exists"; fi

# The login mode: no cast.
mkraw login
run_build login "$H/meta-login.json"
want "login mode: no terminal" login 'd["terminal"] is None'
if [ ! -e "$T/login/out/terminal.cast" ]; then pass "login mode: no cast in the output"; else fail "login mode: no cast in the output" "file exists"; fi

# A terminal line in skipped.tsv wins over a cast.
mkraw skip
printf 'terminal\trecorder-failed\n' >>"$T/skip/.trace/skipped.tsv"
run_build skip "$H/meta.json"
want "skipped terminal: terminal is null" skip 'd["terminal"] is None and "terminal" not in d["meta"]["checks"] and {"check": "terminal", "reason": "recorder-failed"} in d["meta"]["skipped"]'
if [ ! -e "$T/skip/out/terminal.cast" ]; then pass "skipped terminal: no cast in the output"; else fail "skipped terminal: no cast in the output" "file exists"; fi

# No proxy.jsonl: the network check did not run.
mkraw noproxy
rm "$T/noproxy/.trace/proxy.jsonl"
run_build noproxy "$H/meta.json"
want "no proxy.jsonl: hosts is null" noproxy 'd["summary"]["hosts"] is None'
want "no proxy.jsonl: network is not in checks" noproxy '"network" not in d["meta"]["checks"]'
want "no proxy.jsonl: model_requests is null and no model event" noproxy 'd["summary"]["model_requests"] is None and not any(e["kind"] == "model" for e in ev)'

# The network check is not selected: no model event.
mkraw nosel
printf 'terminal,files\n' >"$T/nosel/.trace/checks"
run_build nosel "$H/meta.json"
want "network not selected: model_requests is null" nosel 'd["summary"]["model_requests"] is None and not any(e["kind"] == "model" for e in ev)'

# No files.jsonl: the file check did not run.
mkraw nofiles
rm "$T/nofiles/.trace/files.jsonl"
run_build nofiles "$H/meta.json"
want "no files.jsonl: files is null and not in checks" nofiles 'd["summary"]["files"] is None and "files" not in d["meta"]["checks"] and d["meta"]["files_limit"] is False'

# A proxy line that is open still has the counts and the end.
mkraw open
printf '{"start": 1700000004000, "end": 1700000006500, "host": "h.example.com", "port": 443, "up": 0, "down": 0, "status": "open", "method": "CONNECT"}\n' >>"$T/open/.trace/proxy.jsonl"
run_build open "$H/meta.json"
want "proxy open: up, down and end are integers" open 'any(e["kind"] == "proxy" and e["status"] == "open" and e["end"] == 6500 and e["up"] == 0 and e["down"] == 0 for e in ev)'

# No t0: exit 1.
mkraw not0
rm "$T/not0/.trace/t0"
run_build not0 "$H/meta.json"
expect_code "no t0: exit 1" 1 $?
if [ ! -e "$T/not0/out/trace.json" ]; then pass "no t0: no trace.json"; else fail "no t0: no trace.json" "file exists"; fi

done_tests
