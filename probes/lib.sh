# Shared functions for the probes on Linux and macOS. Source this file; do
# not run it.
#
# A probe only reads. It prints numbered sections ("### N. title"). A
# section that has no data prints "not found". A section that needs a tool
# that is missing prints "not installed: <tool>". The output holds real
# paths. Send it through tools/scrub.sh before it leaves the machine.

# shellcheck shell=sh

PROBE_OS=$(uname -s | tr '[:upper:]' '[:lower:]')
case $PROBE_OS in
  darwin) PROBE_OS=macos ;;
esac
PROBE_SECTION=0

# section TITLE: print the next section header.
section() {
  PROBE_SECTION=$((PROBE_SECTION + 1))
  echo
  echo "### $PROBE_SECTION. $1"
}

none() { echo "not found"; }

# need TOOL: return 0 when TOOL is installed, else print a line and
# return 1.
need() {
  command -v "$1" >/dev/null 2>&1 && return 0
  echo "not installed: $1"
  return 1
}

# header NAME VERSION AGENT_COMMAND...: section 1, the facts of the run.
header() {
  name=$1
  version=$2
  shift 2
  section "Probe"
  echo "probe: $name $version"
  echo "os: $PROBE_OS $(uname -r)"
  [ "$PROBE_OS" = macos ] && echo "macos: $(sw_vers -productVersion 2>/dev/null)"
  [ -r /etc/os-release ] && echo "distribution: $(. /etc/os-release && echo "$PRETTY_NAME")"
  echo "cpu: $(uname -m)"
  echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  for c in "$@"; do
    p=$(command -v "$c" 2>/dev/null || true)
    if [ -n "$p" ]; then
      echo "command: $c -> $p"
      echo "resolved: $(resolve "$p")"
      v=$("$c" --version 2>&1 </dev/null | head -n 1)
      case $v in *sage:*) v=$("$c" -V 2>&1 </dev/null | head -n 1) ;; esac
      echo "version: $v"
    else
      echo "command: $c not found"
    fi
  done
}

# resolve PATH: follow symbolic links. macOS has no readlink -f before 13.
resolve() {
  f=$1
  n=0
  while [ -L "$f" ] && [ "$n" -lt 20 ]; do
    l=$(readlink "$f")
    case $l in
      /*) f=$l ;;
      *) f=$(dirname "$f")/$l ;;
    esac
    n=$((n + 1))
  done
  echo "$f"
}

# pids REGEX: the pids of processes whose command line matches REGEX, not
# this probe and not its children.
pids() {
  ps -axo pid=,args= 2>/dev/null | awk -v me="$$" -v re="$1" '
    { pid = $1; sub(/^ *[0-9]+ +/, "") }
    pid != me && $0 ~ re && $0 !~ /probes\// && $0 !~ /^(awk|grep|ps) / { print pid }' | sort -n
}

# ps_line PID: pid, ppid, tty, start time, and the command. The command
# keeps the program, the flags (words that start with -) and the words that
# hold a /. Other words become <arg>, because they can be names or prompt
# text.
ps_line() {
  s=$(ps -o pid=,ppid=,tty=,lstart= -p "$1" 2>/dev/null) || return 0
  a=$(ps -o args= -p "$1" 2>/dev/null | awk '{
    out = $1
    for (i = 2; i <= NF; i++) out = out " " (($i ~ /^-/ || $i ~ /\//) ? $i : "<arg>")
    print out
  }')
  echo "$s $a" | cut -c1-240
}

# chain PID: the parent chain of PID up to process 1.
chain() {
  q=$1
  while [ -n "$q" ] && [ "$q" -gt 1 ]; do
    ps -o pid=,ppid=,tty=,comm= -p "$q" 2>/dev/null
    q=$(ps -o ppid= -p "$q" 2>/dev/null | tr -d ' ')
  done
}

# children PID: PID and all its descendants.
children() {
  [ "${1:-0}" -gt 0 ] || return 0
  echo "$1"
  for c in $(pgrep -P "$1" 2>/dev/null); do children "$c"; done
}

# cwd PID: the working folder of PID.
cwd() {
  if [ "$PROBE_OS" = linux ]; then
    readlink "/proc/$1/cwd" 2>/dev/null
  else
    lsof -n -P -a -p "$1" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p'
  fi
}

# open_files PID REGEX: the files that PID holds open whose path matches
# REGEX. Linux reads /proc. macOS uses lsof -n -P (no DNS, no port names).
open_files() {
  if [ "$PROBE_OS" = linux ]; then
    for f in /proc/"$1"/fd/*; do readlink "$f" 2>/dev/null; done
  else
    lsof -n -P -p "$1" -Fn 2>/dev/null | sed -n 's/^n//p'
  fi | grep -E -- "$2" | sort -u
}

# layout DIR DEPTH: names, sizes and modification times below DIR, to
# DEPTH levels, with no content. Folders with many entries show a count.
layout() {
  [ -d "$1" ] || { echo "not found: $1"; return 0; }
  find "$1" -maxdepth "$2" 2>/dev/null | sort | head -n 200 | while read -r f; do
    if [ -d "$f" ]; then
      echo "d $(find "$f" -maxdepth 1 | wc -l | tr -d ' ') $f"
    else
      echo "f $(wc -c <"$f" 2>/dev/null | tr -d ' ') $(mtime "$f") $f"
    fi
  done
}

# mtime FILE: the modification time as a Unix time.
mtime() {
  if [ "$PROBE_OS" = linux ]; then stat -c %Y "$1"; else stat -f %m "$1"; fi 2>/dev/null
}

# newest GLOB...: the newest file that matches.
newest() {
  # shellcheck disable=SC2068
  ls -t $@ 2>/dev/null | head -n 1
}

# json_keys FILE: the top-level keys of a JSON file, with the type of each
# value. No values.
json_keys() {
  need python3 || return 0
  python3 - "$1" <<'EOF'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:
    print("not json:", type(e).__name__)
    sys.exit(0)
if isinstance(d, dict):
    for k in sorted(d):
        v = d[k]
        t = type(v).__name__
        if isinstance(v, dict):
            t = "dict(" + ",".join(sorted(v)[:20]) + ")"
        print(" ", k, t)
else:
    print(" ", type(d).__name__)
EOF
}

# jsonl_types FILE [N]: the record types of the last N lines (default 20):
# "type", "payload.type" and the types of message content. No text.
jsonl_types() {
  need python3 || return 0
  tail -n "${2:-20}" "$1" | python3 -c '
import json, sys
for line in sys.stdin:
    try:
        d = json.loads(line)
    except ValueError:
        print("  not-json")
        continue
    if not isinstance(d, dict):
        print("  " + type(d).__name__)
        continue
    p = d.get("payload") if isinstance(d.get("payload"), dict) else {}
    m = d.get("message") if isinstance(d.get("message"), dict) else {}
    c = m.get("content") if isinstance(m.get("content"), list) else []
    kinds = [x.get("type") for x in c if isinstance(x, dict)]
    print(" ", d.get("type") or d.get("role") or "-", p.get("type", ""), kinds or "")
'
}

# sqlite_tables FILE: the table names of a SQLite file, read-only. A file
# that a process holds open can fail; then say so.
sqlite_tables() {
  need sqlite3 || return 0
  sqlite3 -readonly "file:$1?mode=ro" '.tables' 2>&1 | head -n 20
}

# terminal_env PID: the terminal variables of PID. Only the names in the
# list below, because the environment can hold secrets. TMUX and TMUX_PANE
# show the pane; TERM_PROGRAM, TERMINAL_EMULATOR, WT_SESSION and the
# VSCODE_ names show the terminal program.
terminal_env() {
  list='^(TERM|TERM_PROGRAM|TERM_PROGRAM_VERSION|TERMINAL_EMULATOR|TMUX_PANE|WT_SESSION|VSCODE_PID|VSCODE_INJECTION|ZELLIJ|KITTY_WINDOW_ID|WEZTERM_PANE|ITERM_SESSION_ID|__CFBundleIdentifier)='
  if [ "$PROBE_OS" = linux ]; then
    tr '\0' '\n' <"/proc/$1/environ" 2>/dev/null
  else
    # ps eww prints the environment after the command, for own processes.
    ps eww -o command= -p "$1" 2>/dev/null | tr ' ' '\n'
  fi | grep -E "$list" | sort -u
  [ "$PROBE_OS" = linux ] && tr '\0' '\n' <"/proc/$1/environ" 2>/dev/null | grep -q '^TMUX=' && echo "TMUX=<set>"
  return 0
}
