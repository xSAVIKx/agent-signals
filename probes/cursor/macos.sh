#!/bin/sh
# Read-only probe of Cursor CLI sessions on macOS.
# It reads process data, open file names, terminal tab ttys, and the
# table layout of one chat database. It reads no chat text.
# Run: sh probes/cursor/macos.sh > cursor-probe.txt 2>&1
# The output holds real folder and project names. Do not commit it.
# Scrub it before a fact uses it (paths become /work/example).

pids=$(pgrep -f 'cursor-agent' | sort -n)

echo "### 1. Cursor processes: pid ppid tty start command"
for p in $pids; do
  ps -o pid=,ppid=,tty=,lstart=,command= -p "$p" | cut -c1-220
done

echo "### 2. Parent chain of each process (pid ppid tty name)"
for p in $pids; do
  echo "== $p"
  q=$p
  while [ -n "$q" ] && [ "$q" -gt 1 ]; do
    ps -o pid=,ppid=,tty=,comm= -p "$q"
    q=$(ps -o ppid= -p "$q" | tr -d ' ')
  done
done

echo "### 3. Folder and open Cursor files of each process"
for p in $pids; do
  echo "== $p"
  echo "cwd: $(lsof -n -P -a -p "$p" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')"
  lsof -n -P -p "$p" -Fn 2>/dev/null | sed -n 's/^n//p' | grep -E '/\.cursor/' | sort -u
done

# Caution: the first osascript call can open a macOS dialog that asks for
# Automation access to Terminal. The rest of the output does not need it.
echo "### 4. Terminal tabs and their ttys"
osascript -e 'tell application "Terminal" to get tty of every tab of every window' 2>&1
if [ -d /Applications/iTerm.app ]; then
  osascript -e 'tell application "iTerm2" to get tty of every session of every tab of every window' 2>&1
else
  echo "iTerm2: not installed"
fi

echo "### 5. Terminal programs that run now"
ps -axo comm= | grep -E -i 'Terminal|iTerm|Ghostty|WezTerm|kitty|Alacritty|Warp|Cursor Helper|Cursor$' | sort | uniq -c

echo "### 6. Hooks"
ls -la ~/.cursor/hooks.json 2>&1
agent --help 2>&1 | grep -i -E 'hook|resume|chat' | head -20

echo "### 7. Layout of the newest chat folder (no content)"
# A live store.db cannot be opened, and a copy would hold chat text.
# This section lists file names, sizes and times only.
f=$(ls -t ~/.cursor/chats/*/*/store.db 2>/dev/null | head -1)
if [ -z "$f" ]; then
  echo "not found"
else
  d=$(dirname "$f")
  echo "folder: $d"
  ls -la "$d"
  for j in "$d"/*.json; do
    [ -f "$j" ] || continue
    echo "json: $(basename "$j")"
    python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(sorted(d) if isinstance(d,dict) else type(d).__name__)' "$j"
  done
fi

echo "### 8. Newest transcript: record types of the last 5 lines (no text)"
t=$(ls -t ~/.cursor/projects/*/agent-transcripts/*/*.jsonl 2>/dev/null | head -1)
echo "transcript: $t"
[ -n "$t" ] && tail -5 "$t" | python3 -c '
import json,sys
for l in sys.stdin:
    try: d=json.loads(l)
    except Exception: print("bad line"); continue
    c=d.get("message",{}).get("content",[]) if isinstance(d.get("message"),dict) else []
    print(d.get("type") or d.get("role"), [x.get("type") for x in c if isinstance(x,dict)])'
