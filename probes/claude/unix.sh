#!/bin/sh
# Read-only probe of Claude Code sessions on Linux and macOS.
#
# It reads process data, open file names, the pid files in
# ~/.claude/sessions, the layout of ~/.claude, and the record types of the
# newest transcript. It reads no conversation text.
# Run: sh probes/claude/unix.sh > claude-probe.txt 2>&1
# The output holds real paths. Send it through tools/scrub.sh first.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=probes/lib.sh
. "$here/lib.sh"

header claude/unix.sh 1 claude
c=$HOME/.claude
p=$(pids '(^|/)claude( |$)')

section "Processes: pid ppid tty start command"
[ -n "$p" ] || none
for x in $p; do ps_line "$x"; done

section "Parent chain and terminal of each process"
[ -n "$p" ] || none
for x in $p; do
  echo "== $x"
  chain "$x"
  terminal_env "$x"
done

section "Folder and open Claude files of each process"
[ -n "$p" ] || none
for x in $p; do
  echo "== $x cwd: $(cwd "$x")"
  open_files "$x" '\.claude|/claude-[0-9]+/'
done

section "Pid file of each process: keys, status, tmux form"
[ -n "$p" ] || none
for x in $p; do
  f=$c/sessions/$x.json
  echo "== $x"
  ls "$c/sessions/$x".*.key >/dev/null 2>&1 && echo "key file: yes" || echo "key file: no"
  if [ -f "$f" ]; then
    json_keys "$f"
    need python3 >/dev/null && python3 -c '
import json, re, sys
d = json.load(open(sys.argv[1]))
print("  status:", d.get("status"), "| kind:", d.get("kind"), "| version:", d.get("version"))
print("  tmux form:", re.sub(r"[A-Za-z0-9_.-]+", "x", d.get("tmux") or "") or "empty")
print("  procStart:", d.get("procStart"))
' "$f"
    # The start time of the process in other forms, to compare with
    # procStart.
    echo "  ps lstart: $(ps -o lstart= -p "$x" 2>/dev/null)"
    echo "  ps lstart TZ=UTC: $(TZ=UTC ps -o lstart= -p "$x" 2>/dev/null)"
    if [ "$PROBE_OS" = macos ] && need python3 >/dev/null; then
      python3 - "$x" <<'PY'
import ctypes, ctypes.util, struct, sys
# sysctl CTL_KERN KERN_PROC KERN_PROC_PID: struct kinfo_proc. On macOS
# arm64 and x64, p_starttime (a struct timeval) is at offset 0.
libc = ctypes.CDLL(ctypes.util.find_library("c"))
mib = (ctypes.c_int * 4)(1, 14, 1, int(sys.argv[1]))
buf = ctypes.create_string_buffer(1024)
size = ctypes.c_size_t(len(buf))
if libc.sysctl(mib, 4, buf, ctypes.byref(size), None, 0) != 0 or size.value == 0:
    print("  sysctl p_starttime: not available")
else:
    sec, usec = struct.unpack_from("<qi", buf.raw, 0)
    print("  sysctl p_starttime: %d.%06d" % (sec, usec))
PY
    elif [ "$PROBE_OS" = linux ]; then
      echo "  /proc stat start ticks: $(awk '{print $22}' "/proc/$x/stat" 2>/dev/null)"
    fi
  else
    echo "pid file: none"
  fi
done

section "Layout of ~/.claude (two levels)"
layout "$c" 1
echo "sessions:"
layout "$c/sessions" 1 | head -n 20
echo "projects: $(find "$c/projects" -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ') folders"

section "Newest transcript: record types of the last 20 lines (no text)"
t=$(newest "$c"/projects/*/*.jsonl)
if [ -n "$t" ]; then
  echo "transcript: $t"
  jsonl_types "$t" 20
else
  none
fi

section "Hooks and settings"
for s in "$c/settings.json" "$c/settings.local.json"; do
  if [ -f "$s" ]; then
    echo "== $s"
    json_keys "$s"
    need python3 >/dev/null && python3 -c '
import json, sys
h = json.load(open(sys.argv[1])).get("hooks") or {}
print("  hook events:", sorted(h) if isinstance(h, dict) else type(h).__name__)
' "$s"
  else
    echo "not found: $s"
  fi
done

section "Temporary task folders"
for d in "${TMPDIR:-/tmp}"/claude-* /tmp/claude-*; do
  [ -d "$d" ] && echo "$d: $(find "$d" -maxdepth 1 | wc -l | tr -d ' ') entries"
done | sort -u
exit 0
