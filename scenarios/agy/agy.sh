# Shared functions for the agy scenarios. Source this file after
# scenarios/lib.sh; do not run it.

# shellcheck shell=sh

AGY_DIR_REL=.gemini/antigravity-cli

# agy_wizard: pass the first-run wizard and the trust question, when they
# show. The terms page has a box that opts in to the collection of
# interaction data, checked by default. Clear it. Stop if it is still
# checked. Never opt in.
agy_wizard() {
  wait_for 'Navigate · enter Confirm|Terms of Service|Do you trust|for shortcuts|^>' 40 || true
  sleep 2
  if screen | grep -q 'Navigate · enter Confirm' && screen | grep -q '\[Next\]'; then
    send_key Enter
    sleep 2
  fi
  if screen | grep -q 'Terms of Service & Data Use'; then
    screen | grep -q '\[x\] Yes, I agree' && send_key Enter
    sleep 1
    screen | grep -q '\[ \] Yes, I agree' || die "the data box is still checked"
    send_key Down
    sleep 0.5
    send_key Right
    sleep 0.5
    send_key Enter
    sleep 5
  fi
  # The trust question. Its first option trusts the folder.
  if screen | grep -q 'Do you trust'; then
    send_key Enter
    sleep 5
  fi
}

# agy_hooks FILE: write a hooks.json that records each event. Each hook
# runs $SCN_DIR/hook.py, which appends one JSON line to $SCN_OUT/hooks.jsonl
# with the time, the event, the hook name and the payload. The hook prints
# nothing, as an observer that does not decide.
#
# The tool events use the grouped shape of the agy documentation (in the
# binary): {"<name>": {"PreToolUse": [{"matcher": "...", "hooks": [...]}]}}.
# Four names test four matchers: "*", "", the names of the file tools
# (write_file, read_file), and names that agy 1.4.7 does not use.
agy_hooks() {
  cat >"$SCN_DIR/hook.py" <<'PY'
import json, os, sys, time
event, name, out = sys.argv[1], sys.argv[2], sys.argv[3]
raw = sys.stdin.read()
try:
    payload = json.loads(raw)
except ValueError:
    payload = {"not-json": len(raw)}
env = sorted(k for k in os.environ if any(
    w in k.upper() for w in ("ANTIGRAVITY", "GEMINI", "AGY", "JETSKI")))
with open(out, "a") as f:
    f.write(json.dumps({"t": round(time.time(), 3), "event": event,
                        "hook": name, "env": env, "payload": payload}) + "\n")
PY
  python3 - "$1" "$SCN_DIR/hook.py" "$SCN_OUT/hooks.jsonl" <<'PY'
import json, sys
path, script, out = sys.argv[1:4]
def handler(event, name):
    return {"type": "command", "timeout": 10,
            "command": "python3 '%s' %s %s '%s'" % (script, event, name, out)}
flat = {e: [handler(e, "flat")] for e in
        ("SessionStart", "PreInvocation", "PostInvocation", "Stop")}
hooks = {"flat": flat}
for name, matcher in (("star", "*"), ("empty", ""),
                      ("named", "write_file|read_file"),
                      ("other", "write_to_file|view_file|code_action|list_dir")):
    hooks["tool-" + name] = {
        e: [{"matcher": matcher, "hooks": [handler(e, "tool-" + name)]}]
        for e in ("PreToolUse", "PostToolUse")}
json.dump(hooks, open(path, "w"), indent=1)
PY
}

# agy_hook_summary NAME: for each hook line, print the time, the event,
# the hook name, the payload keys and a few short values that are not
# content: the tool name, terminationReason, fullyIdle, invocationNum.
agy_hook_summary() {
  [ -f "$SCN_OUT/hooks.jsonl" ] || { echo "no hook fired" >"$SCN_OUT/$1.hooks"; return 0; }
  python3 - "$SCN_OUT/hooks.jsonl" >"$SCN_OUT/$1.hooks" <<'PY'
import json, sys
for line in open(sys.argv[1]):
    d = json.loads(line)
    p = d["payload"]
    extra = []
    tc = p.get("toolCall") if isinstance(p.get("toolCall"), dict) else None
    if tc:
        extra.append("tool=%s args=%s" % (tc.get("name"), sorted((tc.get("args") or {}).keys())))
    for k in ("terminationReason", "fullyIdle", "invocationNum", "executionNum",
              "initialNumSteps", "stepIdx"):
        if k in p:
            extra.append("%s=%s" % (k, p[k]))
    if "error" in p:
        extra.append("error=%s" % ("empty" if not p["error"] else "set"))
    print(d["t"], d["event"], d["hook"], "keys=" + ",".join(sorted(p)), " ".join(extra),
          "conv=" + str(p.get("conversationId", ""))[:8])
PY
}

# agy_locks NAME: test each presence lock with flock -n from this process
# (exit 1: another process holds it), and list the kernel locks
# (/proc/locks) on the files in presence/ and conversations/. Read only.
agy_locks() {
  d=$SCN_HOME/$AGY_DIR_REL
  {
    for f in "$d"/presence/* "$d"/conversations/*; do
      [ -f "$f" ] || continue
      ino=$(stat -c %i "$f")
      r=-
      case $f in
        *.lock)
          if flock -n "$f" true; then r=0; else r=$?; fi
          ;;
      esac
      k=$(awk -v i="$ino" '{ n = split($6, a, ":"); if (a[n] == i) print $2, $3, $4 }' /proc/locks | sort | uniq -c | tr -s ' ' | tr '\n' ';')
      echo "$(echo "$f" | sed "s#$SCN_DIR#<sandbox>#") size=$(wc -c <"$f" | tr -d ' ') flock-n=$r kernel=[$k]"
    done
  } >"$SCN_OUT/$1.locks"
}

# agy_records NAME: for each line of transcript.jsonl, print the record
# type, the top-level keys, the keys one level down, and each short
# upper-case value (an enum name). No text of the conversation.
agy_records() {
  find "$SCN_HOME/$AGY_DIR_REL/brain" -path '*/logs/transcript.jsonl' -type f 2>/dev/null |
    while read -r f; do
      python3 - "$f" <<'PY'
import json, re, sys
enum = re.compile(r"^[A-Z][A-Z0-9_]{2,60}$")
def walk(v, path, out):
    if isinstance(v, dict):
        for k, x in v.items():
            walk(x, path + "." + k, out)
    elif isinstance(v, list):
        for x in v:
            walk(x, path + "[]", out)
    elif isinstance(v, str) and enum.match(v):
        out.add("%s=%s" % (path, v))
for n, line in enumerate(open(sys.argv[1]), 1):
    d = json.loads(line)
    keys = []
    for k, v in d.items():
        keys.append(k + ("{" + ",".join(sorted(v)) + "}" if isinstance(v, dict) else ""))
    out = set()
    walk(d, "", out)
    print(n, d.get("type"), "keys=" + " ".join(sorted(keys)), "enums=" + " ".join(sorted(out)))
PY
    done >"$SCN_OUT/$1.records"
}

# agy_summaries NAME: copy conversation_summaries.db (with its -wal and
# -shm) to a scratch folder, and print the tables, their columns, and
# each column value that is a short upper-case name or a small number.
# The copy keeps the reader away from the live file.
agy_summaries() {
  src=$SCN_HOME/$AGY_DIR_REL/conversation_summaries.db
  [ -f "$src" ] || { echo "no summaries db" >"$SCN_OUT/$1.summaries"; return 0; }
  c=$SCN_DIR/copy
  rm -rf "$c"
  mkdir -p "$c"
  for x in "" -wal -shm; do [ -f "$src$x" ] && cp "$src$x" "$c/s.db$x"; done
  python3 - "$c/s.db" >"$SCN_OUT/$1.summaries" 2>&1 <<'PY' || true
import re, sqlite3, sys
db = sqlite3.connect(sys.argv[1])
enum = re.compile(r"^[A-Z][A-Z0-9_]{2,60}$")
for (t,) in db.execute("select name from sqlite_master where type='table'"):
    cols = [r[1] for r in db.execute("pragma table_info('%s')" % t)]
    print("table", t, "columns=" + ",".join(cols))
    for row in db.execute("select * from '%s'" % t):
        vals = []
        for k, v in zip(cols, row):
            if isinstance(v, int) or (isinstance(v, str) and enum.match(v)):
                vals.append("%s=%s" % (k, v))
            elif isinstance(v, bytes):
                vals.append("%s=<%d bytes>" % (k, len(v)))
        print("  row", " ".join(vals))
PY
  rm -rf "$c"
}

# agy_poll_start: poll the files below ~/.gemini/antigravity-cli every
# 0.5 s, and append a line for each new, changed or deleted file: the
# time, the size, the modification time and the path. No content. When
# conversation_summaries.db changes, it also appends the status,
# not_fully_idle and step_count of each row, read from a copy.
agy_poll_start() {
  cat >"$SCN_DIR/poll.py" <<'PY'
import os, shutil, sqlite3, sys, time
root, out, stop = sys.argv[1], sys.argv[2], sys.argv[3]
skip = {"bin", "builtin", "cache"}
seen = {}
copy = os.path.join(os.path.dirname(stop), "pollcopy")

def status():
    # Read the run status from a copy of the summaries database, not
    # from the live file.
    src = os.path.join(root, "conversation_summaries.db")
    shutil.rmtree(copy, ignore_errors=True)
    os.makedirs(copy)
    for x in ("", "-wal", "-shm"):
        if os.path.exists(src + x):
            shutil.copy(src + x, os.path.join(copy, "s.db" + x))
    try:
        db = sqlite3.connect(os.path.join(copy, "s.db"))
        rows = db.execute("select status, not_fully_idle, step_count "
                          "from conversation_summaries").fetchall()
        db.close()
        return " ".join("%s,%s,%s" % r for r in rows) or "no-rows"
    except sqlite3.Error as e:
        return "error:" + str(e)[:40]
with open(out, "a", buffering=1) as f:
    while not os.path.exists(stop):
        now = {}
        for dp, dn, fn in os.walk(root):
            dn[:] = [x for x in dn if x not in skip]
            for n in fn:
                p = os.path.join(dp, n)
                try:
                    s = os.stat(p)
                except OSError:
                    continue
                now[p] = (s.st_size, s.st_mtime)
        t = "%.3f" % time.time()
        for p, v in now.items():
            if seen.get(p) != v:
                f.write("%s %d %.3f %s\n" % (t, v[0], v[1], os.path.relpath(p, root)))
        for p in set(seen) - set(now):
            f.write("%s deleted - %s\n" % (t, os.path.relpath(p, root)))
        if any(seen.get(p) != v for p, v in now.items()
               if "conversation_summaries" in p):
            f.write("%s status %s\n" % (t, status()))
        seen = now
        time.sleep(0.5)
PY
  python3 "$SCN_DIR/poll.py" "$SCN_HOME/$AGY_DIR_REL" "$SCN_OUT/poll.txt" "$SCN_DIR/poll.stop" &
}

agy_poll_stop() { : >"$SCN_DIR/poll.stop"; sleep 1; }

# agy_step NAME: record the screen, the processes, the open files, the
# files, the transcript record types, the locks and the hooks so far.
agy_step() {
  capture "$1"
  processes "$1" "$(agent_pid)"
  scn_open_files "$1" "$(agent_pid)"
  snapshot_files "$1" "$SCN_HOME/.gemini"
  record_types "$1" "$SCN_HOME/$AGY_DIR_REL/brain"
  agy_records "$1"
  agy_summaries "$1"
  agy_locks "$1"
  agy_hook_summary "$1"
  note "step $1"
}

# agy_exit: Ctrl+C twice, then wait for the pane to close.
agy_exit() {
  send_key C-c || true
  sleep 1
  send_key C-c || true
  n=0
  while tmux -L "$SCN_SOCK" has-session -t scn 2>/dev/null && [ "$n" -lt 20 ]; do
    sleep 0.5
    n=$((n + 1))
  done
}
