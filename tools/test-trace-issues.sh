#!/bin/sh
# Test tools/trace-issues.py (subcommands collect and plan) against the
# data in tools/testdata/trace-issues/:
#   run/    two collect files of claude 2.1.320 fixture (two images)
#   prev/   the collect file of claude 2.1.319 that made issues.json
#   next/   a run of claude 2.1.320 with one more program
#   wide/   one summary with 150 opened files in 150 folders
#   issues.json  the issue list with the issue of claude 2.1.319
# Run: sh tools/test-trace-issues.sh
set -eu
dir=$(cd "$(dirname "$0")" && pwd)
data=$dir/testdata/trace-issues
script=$dir/trace-issues.py
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
url=https://github.com/example/repo/actions/runs/1

ok() { echo "pass: $1"; }
bad() { echo "fail: $1"; fail=1; }

# check NAME PYTHON-CODE [ARGS]: run the code with the args in sys.argv;
# an exception or an assert is a fail.
check() {
  _name=$1
  _code=$2
  shift 2
  if python3 -I -c "$_code" "$@" >"$tmp/check.out" 2>&1; then
    ok "$_name"
  else
    bad "$_name"
    sed 's/^/  /' "$tmp/check.out"
  fi
}

plan() {
  python3 -I "$script" plan --summaries "$1" --issues "$2" --run-url "$url" --out "$3"
}

# A python prelude: load a JSON file, and decode the DATA line of a body.
pre='
import base64, json, re, sys, zlib
def load(p):
    with open(p, encoding="utf-8") as f:
        return json.load(f)
def data(body):
    m = re.findall(r"^<!-- trace-data: ([A-Za-z0-9+/=]+) -->$", body, re.M)
    assert m, "no DATA line"
    assert len(m[-1]) <= 40000, len(m[-1])
    return json.loads(zlib.decompress(base64.b64decode(m[-1])))
'

# 1. collect: one item with only the 8 keys, from the listed trace only.
run=$tmp/run
mkdir -p "$run/traces/a-permission" "$run/traces/b-permission"
cp "$dir/testdata/trace/ebpf.json" "$run/traces/a-permission/trace.json"
cp "$dir/testdata/trace/ebpf.json" "$run/traces/b-permission/trace.json"
printf 'a-permission\n../escape\n' >"$tmp/passed.txt"
if python3 -I "$script" collect "$run" --only "$tmp/passed.txt" --out "$tmp/collect.json"; then
  check "collect writes one item with only the 8 keys" "$pre"'
items = load(sys.argv[1])
assert len(items) == 1, items
keys = sorted(items[0])
assert keys == sorted(["agent", "agent_version", "mode", "runner_image", "step", "checks", "skipped", "summary"]), keys
assert items[0]["agent_version"] == "2.1.319"
assert items[0]["summary"]["dns"] == ["api.example.com"]
' "$tmp/collect.json"
else
  bad "collect exits 0"
fi
if python3 -I "$script" collect "$run" --only "$tmp/missing.txt" --out "$tmp/empty.json" &&
  [ "$(cat "$tmp/empty.json")" = "[]" ]; then
  ok "collect with no LIST writes an empty list"
else
  bad "collect with no LIST writes an empty list"
fi

# 2. plan: no issue for 2.1.320 gives one open action.
if plan "$data/run" "$data/issues.json" "$tmp/open.json"; then
  check "plan gives one open action with the title and the labels" "$pre"'
acts = load(sys.argv[1])
assert len(acts) == 1, acts
a = acts[0]
assert a["action"] == "open", a
assert a["title"] == "trace: claude 2.1.320 (fixture)", a["title"]
assert a["labels"] == ["trace", "fixture"], a["labels"]
' "$tmp/open.json"
  check "the body has both images, new since 2.1.319 and a DATA line" "$pre"'
body = load(sys.argv[1])[0]["body"]
assert "| ubuntu-24.04 | ubuntu-24.04-arm |" in body, body
new = body.split("new since 2.1.319", 1)[1].split("\n## ", 1)[0]
assert "`statsig.anthropic.com:443`" in new, new
assert "`api.anthropic.com:443`" not in new, new
d = data(body)
assert d["items"]["hosts"]["statsig.anthropic.com:443"] == ["ubuntu-24.04-arm"], d
assert body.splitlines()[0].startswith("trace: claude 2.1.320 (fixture)"), body
assert "trace-summary-claude-linux-x64" in body.splitlines()[0]
' "$tmp/open.json"
  check "a backtick shows as a quote, and an @ item is in a code span" "$pre"'
body = load(sys.argv[1])[0]["body"]
assert "`/usr/bin/we'"'"'ird`" in body, body
assert "`@scope.example`" in body, body
for line in body.splitlines():
    if "@scope" in line:
        assert "`@scope.example`" in line, line
' "$tmp/open.json"
  check "a file item is the folder cut after the area and two parts" "$pre"'
body = load(sys.argv[1])[0]["body"]
assert "`~/.claude/projects`" in body, body
assert "`/usr/lib`" in body, body
assert "node_modules" not in body, body
assert "session.jsonl" not in body, body
' "$tmp/open.json"
  # 3. The same run again, with that body as an open issue: no action.
  python3 -I -c "$pre"'
a = load(sys.argv[1])[0]
issues = load(sys.argv[2])
issues.append({"number": 7, "title": a["title"], "body": a["body"], "state": "OPEN"})
with open(sys.argv[3], "w", encoding="utf-8") as f:
    json.dump(issues, f)
' "$tmp/open.json" "$data/issues.json" "$tmp/issues2.json"
  if plan "$data/run" "$tmp/issues2.json" "$tmp/again.json" && [ "$(cat "$tmp/again.json")" = "[]" ]; then
    ok "plan again with the body as an issue gives no action"
  else
    bad "plan again with the body as an issue gives no action"
  fi
  # A closed issue counts too: no open action.
  sed 's/"OPEN"/"CLOSED"/' "$tmp/issues2.json" >"$tmp/issues3.json"
  if plan "$data/run" "$tmp/issues3.json" "$tmp/closed.json" && [ "$(cat "$tmp/closed.json")" = "[]" ]; then
    ok "a closed issue is not opened again"
  else
    bad "a closed issue is not opened again"
  fi
  # 4. A run with one new program gives one update action.
  if plan "$data/next" "$tmp/issues2.json" "$tmp/update.json"; then
    check "a new program gives one update action that names it" "$pre"'
acts = load(sys.argv[1])
assert len(acts) == 1, acts
a = acts[0]
assert a["action"] == "update" and a["number"] == 7, a
assert "`/usr/bin/rg`" in a["comment"], a["comment"]
assert "`/usr/bin/git`" not in a["comment"], a["comment"]
assert sys.argv[2] in a["comment"]
d = data(a["body"])
assert "/usr/bin/rg" in d["items"]["programs"], d
assert "statsig.anthropic.com:443" in d["items"]["hosts"], d
' "$tmp/update.json" "$url"
  else
    bad "plan with a new program exits 0"
  fi
else
  bad "plan exits 0"
fi

# 5. A table with 150 rows shows 100 rows.
if plan "$data/wide" "$data/issues.json" "$tmp/wide.json"; then
  check "a table with 150 rows shows 100 and 50 more in the artifact" "$pre"'
body = load(sys.argv[1])[0]["body"]
rows = [l for l in body.splitlines() if l.startswith("| `/opt/d")]
assert len(rows) == 100, len(rows)
assert "50 more in the artifact" in body, body
' "$tmp/wide.json"
else
  bad "plan on 150 folders exits 0"
fi

# 6. 5000 opened folders: the body and DATA stay in their limits.
mkdir -p "$tmp/huge"
python3 -I -c '
import json, sys, hashlib
src = json.load(open(sys.argv[1], encoding="utf-8"))
s = src[0]
s["agent_version"] = "4.0.0"
s["summary"]["opened"]["other"] = ["/opt/%s/%s/f" % (hashlib.sha256(str(i).encode()).hexdigest(), i) for i in range(5000)]
s["summary"]["files"]["other"] = ["/var/%s/%s/f" % (hashlib.sha1(str(i).encode()).hexdigest(), i) for i in range(5000)]
json.dump(src, open(sys.argv[2], "w", encoding="utf-8"))
' "$data/wide/summary-claude-linux-x64.json" "$tmp/huge/summary-claude-linux-x64.json"
if plan "$tmp/huge" "$data/issues.json" "$tmp/huge.json"; then
  check "5000 folders: body below 65536, DATA in its limit, dropped kinds named" "$pre"'
body = load(sys.argv[1])[0]["body"]
assert len(body) < 65536, len(body)
d = data(body)
assert "opened" in d["dropped"], d["dropped"]
for k in d["dropped"]:
    assert k + ": not compared (too large)" in body, k
assert "opened" not in d["items"], list(d["items"])
' "$tmp/huge.json"
else
  bad "plan on 5000 folders exits 0"
fi

# 7. Versions sort by their runs of digits.
check "2.1.10 sorts above 2.1.9" '
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ti", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
assert m.version_key("2.1.10") > m.version_key("2.1.9")
assert sorted(["2.1.10", "2.1.9", "2.1.100"], key=m.version_key) == ["2.1.9", "2.1.10", "2.1.100"]
' "$script"
# The issue of 2.1.10 picks 2.1.9 as the version before, not 2.1.100.
mkdir -p "$tmp/v10"
python3 -I -c '
import json, sys
src = json.load(open(sys.argv[1], encoding="utf-8"))
src[0]["agent_version"] = "2.1.10"
json.dump(src, open(sys.argv[2], "w", encoding="utf-8"))
' "$data/prev/summary-claude-linux-x64.json" "$tmp/v10/summary-claude-linux-x64.json"
python3 -I -c "$pre"'
issues = load(sys.argv[1])
body = issues[0]["body"]
out = []
for n, v in ((11, "2.1.9"), (12, "2.1.100"), (13, "2.1.1")):
    out.append({"number": n, "title": "trace: claude %s (fixture)" % v, "body": body, "state": "CLOSED"})
json.dump(out, open(sys.argv[2], "w", encoding="utf-8"))
' "$data/issues.json" "$tmp/issues-v.json"
if plan "$tmp/v10" "$tmp/issues-v.json" "$tmp/v10.json"; then
  check "the version before 2.1.10 is 2.1.9" "$pre"'
body = load(sys.argv[1])[0]["body"]
assert "new since 2.1.9" in body, body
' "$tmp/v10.json"
else
  bad "plan on 2.1.10 exits 0"
fi
# No version before: first traced version.
printf '[]\n' >"$tmp/no-issues.json"
if plan "$data/run" "$tmp/no-issues.json" "$tmp/first.json"; then
  check "no version before gives first traced version" "$pre"'
body = load(sys.argv[1])[0]["body"]
assert "first traced version" in body, body
' "$tmp/first.json"
else
  bad "plan with no issues exits 0"
fi

# 8. No output holds a key of trace.json other than the summary keys and
# the meta keys of collect.
check "no output holds other keys or content of trace.json" "$pre"'
summary_keys = {"files", "hosts", "model_requests", "programs", "processes_left",
                "opened", "direct", "dns", "timeline"}
for item in load(sys.argv[1]):
    assert set(item["summary"]) <= summary_keys, sorted(item["summary"])
for p in sys.argv[1:]:
    with open(p, encoding="utf-8") as f:
        text = f.read()
    texts = [text]
    if p != sys.argv[1]:
        for a in json.loads(text):
            texts.append(json.dumps(data(a["body"])))
    for t in texts:
        # "terminal" is also a value of checks, so it is not in this list.
        for key in ("\"events\"", "\"states\"", "\"kit\"", "\"os_version\"", "\"backend\"",
                    "\"machine\"", "\"provenance\"", "/v1/messages", "model_kind"):
            assert key not in t, (p, key)
' "$tmp/collect.json" "$tmp/open.json" "$tmp/update.json" "$tmp/wide.json"

if [ "$fail" -ne 0 ]; then
  echo "test-trace-issues: fail" >&2
  exit 1
fi
echo "test-trace-issues: pass"
