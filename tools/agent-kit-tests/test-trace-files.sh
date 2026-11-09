# shellcheck shell=sh
# The file check: trace-files.py (inotify, Linux only).
[ "$(uname -s)" = Linux ] || {
  echo "pass: skip not Linux"
  exit 0
}
. "${ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}/tools/agent-kit-tests/lib.sh"

watch=$ROOT/probes/agent/trace-files.py
H=$T/helpers
mkdir "$H"

# wait_file FILE: wait up to 10 s for FILE.
wait_file() {
  _n=0
  while [ ! -s "$1" ] && [ "$_n" -lt 200 ]; do
    sleep 0.05
    _n=$((_n + 1))
  done
  [ -s "$1" ]
}

# The checker. "count FILE KIND PATH [FROM]" prints the number of lines
# with this kind and path (FROM is "-" for no "from" check). "has FILE"
# KIND PATH waits up to 10 s for one such line.
cat >"$H/chk.py" <<'PYEOF'
import json, sys, time
f, kind, path = sys.argv[1:4]
src = sys.argv[4] if len(sys.argv) > 4 else "-"
wait = len(sys.argv) > 5 and sys.argv[5] == "wait"
end = time.time() + (10 if wait else 0)
while True:
    n = 0
    try:
        rows = [json.loads(l) for l in open(f)]
    except (OSError, ValueError):
        rows = []
    for r in rows:
        if r["kind"] == kind and (path == "*" or r.get("path", "") == path) and (src == "-" or r.get("from") == src):
            n += 1
    if n or time.time() >= end:
        print(n)
        break
    time.sleep(0.05)
PYEOF

# The tree maker: many folders under one folder, with one call.
cat >"$H/many.py" <<'PYEOF'
import os, sys
base = sys.argv[1]
os.makedirs(base)
for i in range(8200):
    os.mkdir("%s/d%d" % (base, i))
PYEOF

# The writer: many small writes to one file in one process.
cat >"$H/burst.py" <<'PYEOF'
import sys
with open(sys.argv[1], "w") as f:
    for _ in range(200):
        f.write("x")
        f.flush()
PYEOF

# has_ev FILE KIND PATH [FROM]: wait for the line, return 0 when found.
has_ev() {
  [ "$(python3 -I "$H/chk.py" "$1" "$2" "$3" "${4:--}" wait)" -ge 1 ]
}
# count_ev FILE KIND PATH: the number of lines now.
count_ev() {
  python3 -I "$H/chk.py" "$1" "$2" "$3"
}

# check_has NAME FILE KIND PATH [FROM]
check_has() {
  if has_ev "$2" "$3" "$4" "${5:--}"; then pass "$1"; else fail "$1" "no $3 line for $4"; fi
}
# check_none NAME FILE KIND PATH
check_none() {
  _c=$(count_ev "$2" "$3" "$4")
  if [ "$_c" -eq 0 ]; then pass "$1"; else fail "$1" "$_c $3 lines for $4"; fi
}
# check_one NAME FILE KIND PATH: exactly one line.
check_one() {
  has_ev "$2" "$3" "$4" >/dev/null
  _c=$(count_ev "$2" "$3" "$4")
  if [ "$_c" -eq 1 ]; then pass "$1"; else fail "$1" "$_c $3 lines for $4"; fi
}

# No inotify: exit 3.
python3 -I -c '
import ctypes, runpy, sys
ctypes.CDLL = lambda *a, **k: object()
script, out, ready, top = sys.argv[1:5]
sys.argv = ["trace-files.py", "--out", out, "--ready", ready, top]
runpy.run_path(script, run_name="__main__")' "$watch" "$T/n.out" "$T/n.ready" "$T" >/dev/null 2>&1
expect_code "no inotify: exit 3" 3 $?
if [ ! -e "$T/n.ready" ]; then pass "no inotify: no ready file"; else fail "no inotify: no ready file" "file exists"; fi

# The main run.
mkdir -p "$T/w" "$T/t/old" "$T/outside/m/n/o"
: >"$T/t/old/x"
: >"$T/outside/m/n/o/deep.txt"
mkdir -p "$T/outside/tgt"
ln -s "$T/outside/tgt" "$T/w/lnk0"
python3 -I "$watch" --out "$T/f1.jsonl" --ready "$T/f1.ready" --top "$T/t" "$T/w" &
wpid=$!
bg_pid "$wpid"
if wait_file "$T/f1.ready"; then pass "ready file is written"; else fail "ready file is written" "no file"; fi
f=$T/f1.jsonl

mkdir -p "$T/w/a/b"
echo CONTENT-MARK-one >"$T/w/a/b/c.txt"
check_has "create a" "$f" create "$T/w/a"
check_has "create b" "$f" create "$T/w/a/b"
check_has "create c.txt" "$f" create "$T/w/a/b/c.txt"
# The first write can come before the watch of b. Write once more.
echo again >>"$T/w/a/b/c.txt"
check_has "write c.txt" "$f" write "$T/w/a/b/c.txt"
mv "$T/w/a/b/c.txt" "$T/w/a/b/d.txt"
check_has "move c.txt to d.txt" "$f" move "$T/w/a/b/d.txt" "$T/w/a/b/c.txt"
rm "$T/w/a/b/d.txt"
check_has "delete d.txt" "$f" delete "$T/w/a/b/d.txt"
if python3 -I -c '
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1])]
by = {r["path"]: r for r in rows if r["kind"] == "create"}
assert by[sys.argv[2] + "/w/a"]["dir"] is True
assert by[sys.argv[2] + "/w/a/b/c.txt"]["dir"] is False
assert all(set(r) <= {"t", "kind", "path", "dir", "from"} for r in rows)' "$f" "$T"; then
  pass "the dir flag and the keys"
else
  fail "the dir flag and the keys" "bad line"
fi

# --top: no watch for old folders, a watch for new ones.
echo CONTENT-MARK-two >>"$T/t/old/x"
mkdir "$T/t/new"
echo y >"$T/t/new/y"
check_has "top: create new" "$f" create "$T/t/new"
check_has "top: create new/y" "$f" create "$T/t/new/y"
check_has "top: write new/y" "$f" write "$T/t/new/y"
check_none "top: no line for old/x" "$f" write "$T/t/old/x"
check_none "top: no create for old/x" "$f" create "$T/t/old/x"

# A top folder that moves: it had no watch, so it is a new folder.
mv "$T/t/old" "$T/t/old2"
check_has "top move: move line" "$f" move "$T/t/old2" "$T/t/old"
check_has "top move: scan creates the old entry" "$f" create "$T/t/old2/x"
echo late >>"$T/t/old2/x"
check_has "top move: the folder has a watch" "$f" write "$T/t/old2/x"

# A symlink to a folder is not followed, before the start or after it.
ln -s "$T/outside/tgt" "$T/w/lnk1"
echo s >"$T/outside/tgt/sf"
echo s >"$T/w/lnk0/sf2"
echo s >"$T/w/lnk1/sf3"
: >"$T/w/sentinel"
has_ev "$f" create "$T/w/sentinel" >/dev/null
sleep 0.3
for p in "$T/outside/tgt/sf" "$T/w/lnk0/sf" "$T/w/lnk0/sf2" "$T/w/lnk1/sf3"; do
  check_none "symlink: no create for $p" "$f" create "$p"
  check_none "symlink: no write for $p" "$f" write "$p"
done
check_one "symlink: create of the link itself" "$f" create "$T/w/lnk1"

# A tree from one mkdir -p, and files at once in a fast loop.
mkdir -p "$T/w/r/s/t/u"
i=0
while [ "$i" -lt 30 ]; do
  : >"$T/w/r/s/t/u/f$i"
  i=$((i + 1))
done
for d in r r/s r/s/t r/s/t/u; do
  check_one "tree: one create for $d" "$f" create "$T/w/$d"
done
has_ev "$f" create "$T/w/r/s/t/u/f29" >/dev/null
miss=0
i=0
while [ "$i" -lt 30 ]; do
  [ "$(count_ev "$f" create "$T/w/r/s/t/u/f$i")" -eq 1 ] || miss=$((miss + 1))
  i=$((i + 1))
done
if [ "$miss" -eq 0 ]; then pass "tree: one create for each of 30 files"; else fail "tree: one create for each of 30 files" "$miss files with no line or two lines"; fi

# A folder tree that moves in: the scan.
mv "$T/outside/m" "$T/w/m"
for p in m m/n m/n/o m/n/o/deep.txt; do
  check_one "move in: one create for $p" "$f" create "$T/w/$p"
done
echo z >"$T/w/m/n/o/after.txt"
check_has "move in: a watch below the new folder" "$f" create "$T/w/m/n/o/after.txt"

# A move inside the tree keeps the watches of a folder.
mv "$T/w/m" "$T/w/m2"
check_has "move of a folder: move line" "$f" move "$T/w/m2" "$T/w/m"
echo q >"$T/w/m2/n/o/late.txt"
check_has "move of a folder: the watch follows" "$f" create "$T/w/m2/n/o/late.txt"

# A move out of the tree: delete.
mv "$T/w/m2" "$T/outside/m3"
check_has "move out: delete" "$f" delete "$T/w/m2"

# One write line for each file in each 100 ms.
python3 -I "$H/burst.py" "$T/w/burst.txt"
has_ev "$f" write "$T/w/burst.txt" >/dev/null
_c=$(count_ev "$f" write "$T/w/burst.txt")
if [ "$_c" -ge 1 ] && [ "$_c" -le 3 ]; then pass "write: 200 writes give at most 3 lines"; else fail "write: 200 writes give at most 3 lines" "$_c"; fi

# The time is epoch milliseconds.
if python3 -I -c '
import json, sys, time
now = time.time_ns() // 1000000
rows = [json.loads(l) for l in open(sys.argv[1])]
assert all(1700000000000 < r["t"] <= now for r in rows)' "$f"; then
  pass "t is epoch milliseconds"
else
  fail "t is epoch milliseconds" "bad t"
fi
expect_no_line "no limit line below the limit" '"limit"' "$f"
expect_no_line "no file content in the lines" 'CONTENT-MARK' "$f"

kill -TERM "$wpid"
wait "$wpid"
expect_code "term: the watch exits 0" 0 $?
if kill -0 "$wpid" 2>/dev/null; then fail "term: the watch stopped" "pid runs"; else pass "term: the watch stopped"; fi

# TERM at once after a write: the line is not lost.
mkdir "$T/w3"
python3 -I "$watch" --out "$T/f3.jsonl" --ready "$T/f3.ready" "$T/w3" &
wpid=$!
bg_pid "$wpid"
wait_file "$T/f3.ready" || fail "term: the ready file is written" "no file"
echo x >"$T/w3/q"
kill -TERM "$wpid"
wait "$wpid"
expect_code "term at once: the watch exits 0" 0 $?
n=$(count_ev "$T/f3.jsonl" write "$T/w3/q")
if [ "$n" -eq 1 ]; then pass "term at once: one write line"; else fail "term at once: one write line" "$n"; fi
n=$(count_ev "$T/f3.jsonl" create "$T/w3/q")
if [ "$n" -eq 1 ]; then pass "term at once: one create line"; else fail "term at once: one create line" "$n"; fi

# A DIR that holds a --top DIR: no watch for the old subfolders of the top.
mkdir -p "$T/c/top/sub" "$T/c/other/sub"
python3 -I "$watch" --out "$T/f4.jsonl" --ready "$T/f4.ready" --top "$T/c/top" "$T/c" &
wpid=$!
bg_pid "$wpid"
wait_file "$T/f4.ready" || fail "nested top: the ready file is written" "no file"
echo x >"$T/c/top/sub/f"
echo x >"$T/c/other/sub/g"
check_has "nested top: the other folder has a watch" "$T/f4.jsonl" create "$T/c/other/sub/g"
sleep 0.3
check_none "nested top: no create in the old subfolder" "$T/f4.jsonl" create "$T/c/top/sub/f"
check_none "nested top: no write in the old subfolder" "$T/f4.jsonl" write "$T/c/top/sub/f"
echo x >"$T/c/top/direct"
check_has "nested top: the top itself has a watch" "$T/f4.jsonl" create "$T/c/top/direct"
kill -TERM "$wpid"
wait "$wpid"
expect_code "nested top: the watch exits 0" 0 $?

# The limit: 8200 folders before the start.
python3 -I "$H/many.py" "$T/w2/many"
python3 -I "$watch" --out "$T/f2.jsonl" --ready "$T/f2.ready" "$T/w2" &
wpid=$!
bg_pid "$wpid"
_n=0
while [ ! -s "$T/f2.ready" ] && [ "$_n" -lt 600 ]; do
  sleep 0.05
  _n=$((_n + 1))
done
if [ -s "$T/f2.ready" ]; then pass "limit: the ready file is written"; else fail "limit: the ready file is written" "no file"; fi
f=$T/f2.jsonl
check_one "limit: one limit line" "$f" limit "*"
echo z >"$T/w2/z"
mkdir "$T/w2/n1" "$T/w2/n2" "$T/w2/n3"
check_has "limit: events still come" "$f" create "$T/w2/z"
check_has "limit: events for a new folder" "$f" create "$T/w2/n3"
n=$(grep -c '"kind": "limit"' "$f")
if [ "$n" -eq 1 ]; then pass "limit: still one limit line"; else fail "limit: still one limit line" "$n"; fi
kill -TERM "$wpid"
wait "$wpid"
expect_code "limit: the watch exits 0 on TERM" 0 $?

done_tests
