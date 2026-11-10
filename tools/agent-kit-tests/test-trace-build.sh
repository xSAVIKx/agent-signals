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
# run_build NAME META [HOST]: build into $T/NAME/out, the names are fixed.
run_build() {
  (
    TMPDIR=/tmp/example
    SCRUB_USER=alice
    SCRUB_HOST=${3-build01.corp.internal}
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

# The scrub keeps the placeholder ~/<private> of the build.
(
  SCRUB_HOME=/Users/alice SCRUB_USER=alice SCRUB_HOST=build01.corp.internal
  export SCRUB_HOME SCRUB_USER SCRUB_HOST
  sh "$ROOT/tools/scrub.sh" "$T/real/out/trace.json" >"$T/real/scrubbed.json" 2>/dev/null
)
if grep -F '"path": "~/<private>"' "$T/real/scrubbed.json" >/dev/null 2>&1; then pass "real home: ~/<private> survives the scrub"; else fail "real home: ~/<private> survives the scrub" "no such line"; fi

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

# A throwaway home and a missing home do not keep the cast.
mkraw throwaway
sed 's/"home": "fixture"/"home": "throwaway"/' "$H/meta.json" >"$H/meta-throw.json"
run_build throwaway "$H/meta-throw.json"
want "throwaway home: no terminal" throwaway 'd["terminal"] is None and "terminal" not in d["meta"]["checks"]'
if [ ! -e "$T/throwaway/out/terminal.cast" ]; then pass "throwaway home: no cast in the output"; else fail "throwaway home: no cast in the output" "file exists"; fi
mkraw nohome
sed 's/"home": "fixture",//' "$H/meta.json" >"$H/meta-nohome.json"
run_build nohome "$H/meta-nohome.json"
want "missing home: no terminal" nohome 'd["terminal"] is None'
if [ ! -e "$T/nohome/out/terminal.cast" ]; then pass "missing home: no cast in the output"; else fail "missing home: no cast in the output" "file exists"; fi

# A proxy host that is the host name of the machine is scrubbed.
mkraw phost
for _h in build01.corp.internal build01 BUILD01.lan; do
  printf '{"start": 1700000001000, "end": 1700000001100, "host": "%s", "port": 443, "up": 1, "down": 2, "status": "ok", "method": "CONNECT"}\n' "$_h" >>"$T/phost/.trace/proxy.jsonl"
done
run_build phost "$H/meta.json"
want "proxy host: the machine name becomes host" phost 'not any("build01" in h["host"].lower() for h in d["summary"]["hosts"]) and [h for h in d["summary"]["hosts"] if h["host"] == "host"][0]["connections"] == 3 and "build01" not in json.dumps(ev).lower()'

# Moves out of the watched folders, and a source that was dropped.
mkraw moves
printf '{"t": 1700000001500, "kind": "move", "path": "/tmp/example/sock-a/y", "from": "/work/example/proj/gone.txt", "dir": false}\n' >>"$T/moves/.trace/files.jsonl"
printf '{"t": 1700000001600, "kind": "move", "path": "/work/example/proj/in.txt", "from": "/tmp/example/sock-a/z", "dir": false}\n' >>"$T/moves/.trace/files.jsonl"
run_build moves "$H/meta.json"
want "move into a dropped folder is a delete of the source" moves 'any(e["kind"] == "delete" and e["path"] == "WORK/gone.txt" for e in ev) and not any(e["kind"] == "move" and e["path"].endswith("sock-a/y") for e in ev)'
want "move from a dropped folder has from ?" moves 'any(e["kind"] == "move" and e["from"] == "?" and e["path"] == "WORK/in.txt" for e in ev)'
want "from ? is not in summary.files" moves '"?" not in [p for v in d["summary"]["files"].values() for p in v]'

# Routes: no userinfo, query, fragment or parameter.
mkraw routes
{
  printf '1700000002100 POST http://user:pw@h.example.com/v1/a;x=secret1 req-0002 tool\n'
  printf '1700000002200 POST /v1/b#frag-secret2 req-0003 tool\n'
  printf '1700000002300 POST /v1/c?k=secret3;secret4 req-0004 tool\n'
} >>"$T/routes/.trace/model-a.log"
run_build routes "$H/meta.json"
want "routes: userinfo, parameters, fragment and query are cut" routes 'sorted(e["route"] for e in ev if e["kind"] == "model")[:4] == ["/v1/b", "/v1/c", "/v1/messages", "/v1/models"] and any(e.get("route") == "http://h.example.com/v1/a" for e in ev) and "secret" not in json.dumps(d) and "pw" not in json.dumps(ev)'

# A Cursor line has no request id: "MS POST RPC KIND".
mkraw cursor
printf '1700000002400 POST /agent.v1.AgentService/Run start\n' >"$T/cursor/.trace/model-b.log"
run_build cursor "$H/meta.json"
want "cursor: the kind is the fourth word" cursor 'any(e["kind"] == "model" and e["route"] == "/agent.v1.AgentService/Run" and e["model_kind"] == "start" for e in ev)'

# A time that is not finite is a bad line, not a crash.
mkraw inf
printf '{"t": 1e999, "kind": "create", "path": "/work/example/proj/inf.txt", "dir": false}\n' >>"$T/inf/.trace/files.jsonl"
run_build inf "$H/meta.json"
want "inf: the build gives a document" inf 'isinstance(ev, list)'
want "inf: the row is not an event and not in the summary" inf 'not any(e.get("path") == "WORK/inf.txt" for e in ev) and "WORK/inf.txt" not in [p for v in d["summary"]["files"].values() for p in v]'

# The account name has no case. An empty SCRUB_USER is no variable.
mkraw case
printf '{"t": 1700000001700, "kind": "create", "path": "/home/example/.cache/ALICE-x/a", "dir": false}\n' >>"$T/case/.trace/files.jsonl"
run_build case "$H/meta.json"
want "account name has no case" case 'any(e.get("path") == "~/.cache/dev-x/a" for e in ev)'
(
  SCRUB_USER=
  SCRUB_HOST=
  export SCRUB_USER SCRUB_HOST
  python3 -I "$build" --raw "$T/case/.trace" --meta "$H/meta.json" --out "$T/case/out2"
) >"$T/case2.log" 2>&1
expect_code "empty SCRUB_USER and SCRUB_HOST: exit 0" 0 $?

# A host name that is a word of a placeholder does not change it.
mkraw wordhost
printf '{"t": 1700000001800, "kind": "create", "path": "/work/example/proj/work.txt", "dir": false}\n' >>"$T/wordhost/.trace/files.jsonl"
run_build wordhost "$H/meta.json" work
want "short host name work: placeholders stay" wordhost 'all(e["path"].startswith(("WORK/", "~/", "TMP/")) for e in ev if "path" in e) and any(e.get("path") == "WORK/host" for e in ev)'

# More than 20 events near a state: 20, the nearest.
mkraw many
_k=0
while [ "$_k" -lt 30 ]; do
  printf '{"t": %s, "kind": "create", "path": "/work/example/proj/m%s", "dir": false}\n' $((1700000004200 + _k * 11)) "$_k" >>"$T/many/.trace/files.jsonl"
  _k=$((_k + 1))
done
run_build many "$H/meta.json"
want "timeline: 20 events, the nearest" many '(lambda n: len(n) == 20 and "create WORK/m0" in n and "create WORK/m18" in n and "create WORK/m19" not in n and "create WORK/before.txt" not in n and [e["t"] for e in n_raw] == sorted(e["t"] for e in n_raw))([x["text"] for x in n_raw]) if (n_raw := [x for x in d["summary"]["timeline"] if x["state"] == "dialog"][0]["near"]) else False'

# A home in a work folder, and a work folder in a home.
mkraw nested
printf 'b\t/work/example/proj/home-b\t/work/example/proj\t1\t\n' >>"$T/nested/.trace/sessions.tsv"
printf 'c\t/home/example2\t/home/example2/w\t2\t\n' >>"$T/nested/.trace/sessions.tsv"
for _p in /work/example/proj/home-b/.cfg /work/example/proj/other /home/example2/w/f /home/example2/.cfg2; do
  printf '{"t": 1700000001900, "kind": "write", "path": "%s", "dir": false}\n' "$_p" >>"$T/nested/.trace/files.jsonl"
done
run_build nested "$H/meta.json"
want "nested: the longest prefix wins" nested 'all(any(e.get("path") == p for e in ev) for p in ["~/.cfg", "WORK/other", "WORK/f", "~/.cfg2"])'

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
