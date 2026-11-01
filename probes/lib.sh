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

# The helpers below name their variables with a leading "_". A probe uses
# short names such as a, c, f and s, and a POSIX shell has no local
# variables, so a helper must not change them.

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
  for _c in "$@"; do
    _p=$(command -v "$_c" 2>/dev/null || true)
    if [ -n "$_p" ]; then
      echo "command: $_c -> $_p"
      echo "resolved: $(resolve "$_p")"
      _v=$("$_c" --version 2>&1 </dev/null | head -n 1)
      case $_v in *sage:*|*"unknown option"*) _v=$("$_c" -V 2>&1 </dev/null | head -n 1) ;; esac
      echo "version: $_v"
    else
      echo "command: $_c not found"
    fi
  done
}

# resolve PATH: follow symbolic links. macOS has no readlink -f before 13.
resolve() {
  _f=$1
  _n=0
  while [ -L "$_f" ] && [ "$_n" -lt 20 ]; do
    _l=$(readlink "$_f")
    case $_l in
      /*) _f=$_l ;;
      *) _f=$(dirname "$_f")/$_l ;;
    esac
    _n=$((_n + 1))
  done
  echo "$_f"
}

# pids REGEX: the pids of processes whose command line matches REGEX, not
# this probe, its children or the processes that started it. The one-line
# start runs the kit as "sh -s -- --guided STEP AGENT", and that command
# line holds the agent name.
pids() {
  _skip=" $$ "
  _p=$$
  while _p=$(ps -o ppid= -p "$_p" 2>/dev/null | tr -d ' ') && [ "${_p:-0}" -gt 1 ]; do
    _skip="$_skip$_p "
  done
  ps -axo pid=,args= 2>/dev/null | awk -v skip="$_skip" -v re="$1" '
    { pid = $1; sub(/^ *[0-9]+ +/, "") }
    index(skip, " " pid " ") == 0 && $0 ~ re && $0 !~ /probes\// && $0 !~ /^(awk|grep|ps) / { print pid }' | sort -n
}

# ps_line PID: pid, ppid, tty, start time, and the command. The command
# keeps the program, the flags (words that start with -) and the words that
# hold a /. Other words become <arg>, because they can be names or prompt
# text.
ps_line() {
  _s=$(ps -o pid=,ppid=,tty=,lstart= -p "$1" 2>/dev/null) || return 0
  _a=$(ps -o args= -p "$1" 2>/dev/null | awk '{
    out = $1
    for (i = 2; i <= NF; i++) out = out " " (($i ~ /^-/ || $i ~ /\//) ? $i : "<arg>")
    print out
  }')
  echo "$_s $_a" | cut -c1-240
}

# chain PID: the parent chain of PID up to process 1.
chain() {
  _q=$1
  while [ -n "$_q" ] && [ "$_q" -gt 1 ]; do
    ps -o pid=,ppid=,tty=,comm= -p "$_q" 2>/dev/null
    _q=$(ps -o ppid= -p "$_q" 2>/dev/null | tr -d ' ')
  done
}

# children PID: PID and all its descendants.
children() {
  [ "${1:-0}" -gt 0 ] || return 0
  echo "$1"
  for _c in $(pgrep -P "$1" 2>/dev/null); do children "$_c"; done
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
    for _f in /proc/"$1"/fd/*; do readlink "$_f" 2>/dev/null; done
  else
    lsof -n -P -p "$1" -Fn 2>/dev/null | sed -n 's/^n//p'
  fi | grep -E -- "$2" | sort -u
}

# layout DIR DEPTH: names, sizes and modification times below DIR, to
# DEPTH levels, with no content. Folders with many entries show a count.
layout() {
  [ -d "$1" ] || { echo "not found: $1"; return 0; }
  find "$1" -maxdepth "$2" 2>/dev/null | sort | head -n 200 | while read -r _f; do
    if [ -d "$_f" ]; then
      echo "d $(find "$_f" -maxdepth 1 | wc -l | tr -d ' ') $_f"
    else
      echo "f $(wc -c <"$_f" 2>/dev/null | tr -d ' ') $(mtime "$_f") $_f"
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
# value. No values. For a dict value it prints the sub-keys, at most 20. A
# sub-key that holds @, /, \, : or . is a name or a path, and so is each
# sub-key of enabledPlugins, extraKnownMarketplaces, mcpServers,
# marketplaces and plugins. Such a sub-key shows as <name>, with a count.
json_keys() {
  need python3 || return 0
  python3 - "$1" <<'EOF'
import json, re, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:
    print("not json:", type(e).__name__)
    sys.exit(0)
NAMES = {"enabledPlugins", "extraKnownMarketplaces", "mcpServers", "marketplaces", "plugins"}
def sub_keys(parent, v):
    names = [k for k in v if parent in NAMES or re.search(r"[@/\\:.]", k)]
    shown = sorted(k for k in v if k not in names)[:20]
    if names:
        shown.append("<name> x %d" % len(names))
    return ",".join(shown)
if isinstance(d, dict):
    for k in sorted(d):
        v = d[k]
        t = type(v).__name__
        if isinstance(v, dict):
            t = "dict(" + sub_keys(k, v) + ")"
        print(" ", k, t)
else:
    print(" ", type(d).__name__)
EOF
}

# toml_tables FILE: the table names of a TOML file, in the order of the
# file, with no keys and no values. A name that holds a project path or the
# name of a server or a plugin shows in a general form, with a count:
#   [projects."/work/shop"]             -> [projects.<path>] x 1
#   [hooks.state."<path>:pre_tool_use"] -> [hooks.state.<path>] x 1
#   [mcp_servers.docs.env]              -> [mcp_servers.<name>.env] x 1
#   [plugins."lint@acme"]               -> [plugins.<name>] x 1
# Any other quoted part becomes <name>. Format-TomlTable in lib.ps1 has the
# same rule.
toml_tables() {
  [ -f "$1" ] || { echo "not found: $1"; return 0; }
  awk '
  function fmt(t,    op, cl, n, i, ch, j, tok, part, out, skip) {
    sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t)
    op = "["; if (substr(t, 1, 2) == "[[") op = "[["
    t = substr(t, length(op) + 1)
    if (substr(t, length(t)) != "]") return "<other>"
    cl = "]"; if (length(t) >= 2 && substr(t, length(t) - 1) == "]]") cl = "]]"
    t = substr(t, 1, length(t) - length(cl))
    n = 0; i = 1
    while (i <= length(t)) {
      ch = substr(t, i, 1)
      if (ch == "\"" || ch == "'\''") {
        j = i + 1
        while (j <= length(t) && substr(t, j, 1) != ch) { if (ch == "\"" && substr(t, j, 1) == "\\") j++; j++ }
        if (j > length(t)) { i++; continue }
        part[++n] = "<q>"; i = j + 1; continue
      }
      if (ch == "." || ch == " " || ch == "\t") { i++; continue }
      j = i
      while (j <= length(t) && substr(t, j, 1) !~ /[. \t"'\'']/) j++
      part[++n] = substr(t, i, j - i); i = j
    }
    if (n == 0) return "<other>"
    skip = 0
    if (n >= 2 && part[1] == "projects") { out = "projects.<path>"; skip = 2 }
    else if (n >= 3 && part[1] == "hooks" && part[2] == "state") { out = "hooks.state.<path>"; skip = 3 }
    else if (n >= 2 && part[1] ~ /^(mcp_servers|plugins|marketplaces|profiles|model_providers)$/) { out = part[1] ".<name>"; skip = 2 }
    for (i = skip + 1; i <= n; i++) {
      tok = part[i]; if (tok == "<q>") tok = "<name>"
      out = (out == "") ? tok : out "." tok
    }
    return op out cl
  }
  /^[ \t]*\[/ {
    line = $0; sub(/[ \t]+#.*$/, "", line)
    t = fmt(line)
    if (!(t in c)) o[++k] = t
    c[t]++
  }
  END {
    if (!k) print "tables: none"
    for (i = 1; i <= k; i++) {
      t = o[i]
      if (c[t] > 1 || t ~ /</) print "table: " t " x " c[t]; else print "table: " t
    }
  }' "$1"
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
# VSCODE_ names show the terminal program. VTE_VERSION, GNOME_TERMINAL_SCREEN
# and KONSOLE_VERSION show a Linux desktop terminal.
terminal_env() {
  _list='^(TERM|TERM_PROGRAM|TERM_PROGRAM_VERSION|TERMINAL_EMULATOR|VTE_VERSION|GNOME_TERMINAL_SCREEN|KONSOLE_VERSION|TMUX_PANE|WT_SESSION|VSCODE_PID|VSCODE_INJECTION|ZELLIJ|KITTY_WINDOW_ID|WEZTERM_PANE|ITERM_SESSION_ID|__CFBundleIdentifier)='
  if [ "$PROBE_OS" = linux ]; then
    tr '\0' '\n' <"/proc/$1/environ" 2>/dev/null
  else
    # ps eww prints the environment after the command, for own processes.
    ps eww -o command= -p "$1" 2>/dev/null | tr ' ' '\n'
  fi | grep -E "$_list" | sort -u
  [ "$PROBE_OS" = linux ] && tr '\0' '\n' <"/proc/$1/environ" 2>/dev/null | grep -q '^TMUX=' && echo "TMUX=<set>"
  return 0
}
