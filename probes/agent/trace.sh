#!/bin/sh
# kit trace NAME@BACKEND [--checks LIST] [ARGS]: run one step of the
# current run with recorders, and write a trace of it.
#
# LIST is a comma list of the checks terminal, network and files. The
# default is all three. The check ebpf is not in this kit yet. An unknown
# check or option is bad use. --checks comes before NAME or just after it.
# ARGS go to "kit step".
#
# The order:
#   1. Find the run. When RUN/.trace exists, another trace runs: exit 2.
#   2. Make RUN/.trace (the raw folder). Write t0 (the start in epoch
#      milliseconds) and the file "checks" (LIST).
#   3. network: start trace-proxy.py (the pid label "trace proxy"), and
#      wait 10 s at most for proxy.port.
#   4. files, on Linux: make the work root (kit_work_root RUN) and the
#      home root (RUN/home, or HOME with the home "real"). Start
#      trace-files.py (the pid label "trace files") on these two folders,
#      with --top the temp folder (TMPDIR, else /tmp), and wait 30 s at
#      most for its ready file. The watcher writes its events in a new
#      folder in the temp folder. A folder that exists before the watch
#      starts is not watched there, so the watcher does not see its own
#      writes. Not on Linux, or with no inotify, the file
#      skipped.tsv gets a line for files.
#   5. Run "kit step NAME@BACKEND ARGS" with KIT_TRACE (the raw folder) and
#      KIT_TRACE_CHECKS (LIST) in the environment, and TMPDIR set to a
#      folder in the raw folder. Keep its exit code and its output lines.
#   6. Stop each session of the trace that still runs. Stop the recorders
#      by pid: TERM, then KILL after 5 s. Remove their pid files.
#   7. Write the meta file: the run facts of manifest.tsv, the agent and
#      the step of the step line, the agent version from "kit doctor"
#      (which never runs the agent), the runner image, the machine and
#      the mode.
#   8. Run trace-build.py into RUN/.trace/out. Scrub each output file with
#      tools/scrub.sh into RUN/traces/NN-NAME@BACKEND/. NN is one more than
#      the highest number in RUN/traces/. Delete RUN/.trace. A build or a
#      scrub that fails gives the line "trace: NAME@BACKEND fail REASON"
#      and exit 1.
#   9. Print the output lines of the step, then the line
#      "trace: RUN/traces/NN-NAME@BACKEND". Exit with the code of the step.
#
# The terminal record: only a run with the home "fixture" keeps the cast,
# because its prompts are fixed. With another home, skipped.tsv gets the
# line "terminal<tab>not-fixture-home", and trace-build.py deletes the
# cast. When the terminal check has no cast and no reason, skipped.tsv
# gets "terminal<tab>no-cast".
#
# A recorder that does not start gives "trace: NAME@BACKEND fail REASON"
# and exit 1 before the step runs. A signal (INT, TERM) stops the step and
# its sessions, stops the recorders, and deletes RUN/.trace.
# Exit codes: the code of the step, 1 fail, 2 bad use, 3 no python3.
set -u
. "$(dirname "$0")/lib.sh"

usage() { kit_die "$KIT_USAGE" "usage: kit trace NAME@BACKEND [--checks LIST] [ARGS]"; }

# set_checks LIST: check LIST and set checks to its words in the fixed
# order terminal, network, files.
checks=
set_checks() {
  [ -n "$1" ] || kit_die "$KIT_USAGE" "--checks needs a list: terminal, network, files"
  _old=$IFS
  IFS=,
  for _w in $1; do
    case $_w in
      terminal | network | files) ;;
      ebpf) kit_die "$KIT_USAGE" "the ebpf check is not in this kit yet" ;;
      *) kit_die "$KIT_USAGE" "unknown check: '$_w'. Use terminal, network, files" ;;
    esac
  done
  IFS=$_old
  case $1 in ,* | *, | *,,*) kit_die "$KIT_USAGE" "unknown check: an empty word in '$1'" ;; esac
  checks=
  for _w in terminal network files; do
    kit_has_word "$1" "$_w" && checks=${checks:+$checks,}$_w
  done
}

arg=
picked=
while [ "$#" -gt 0 ]; do
  case $1 in
    --checks)
      [ "$#" -ge 2 ] || usage
      set_checks "$2"
      picked=1
      shift 2
      ;;
    -*) kit_die "$KIT_USAGE" "unknown option: $1" ;;
    *)
      arg=$1
      shift
      break
      ;;
  esac
done
[ -n "$arg" ] || usage
if [ "$#" -ge 1 ] && [ "$1" = --checks ]; then
  [ "$#" -ge 2 ] || usage
  set_checks "$2"
  picked=1
  shift 2
fi
[ -n "$picked" ] || checks=terminal,network,files

# The step: the same checks as "kit step", before anything changes.
name=${arg%%@*}
case $name in '' | *[!a-z0-9-]*) kit_die "$KIT_USAGE" "bad step name: $name" ;; esac
kit_step_field "$name" kind >/dev/null || kit_die "$KIT_USAGE" "unknown step: $name. Run 'kit plan'"
blist=$(kit_step_field "$name" backends)
case $arg in
  *@*) backend=${arg#*@} ;;
  *)
    case $blist in
      *,*) kit_die "$KIT_USAGE" "give a backend: $name@<one of $blist>" ;;
      *) backend=$blist ;;
    esac
    ;;
esac
case $backend in '' | *[!a-z]*) kit_die "$KIT_USAGE" "bad backend: $backend" ;; esac
kit_has_word "$blist" "$backend" || kit_die "$KIT_USAGE" "the step $name has no backend $backend. Use one of: $blist"
kit_has_word "$(kit_step_field "$name" os)" "$(kit_os)" || kit_die "$KIT_USAGE" "the step $name is not for $(kit_os)"
command -v python3 >/dev/null 2>&1 || kit_die "$KIT_MISSING" "kit trace needs python3"

run=$(kit_run_dir) || exit "$KIT_USAGE"
why=$(kit_run_problem "$run")
[ -z "$why" ] || kit_die "$KIT_USAGE" "the run folder cannot take a trace: $why"
raw=$run/.trace
# mkdir is the lock: only one trace runs in a run.
mkdir "$raw" 2>/dev/null || kit_die "$KIT_USAGE" "another trace runs in this run ($raw exists)"
chmod 700 "$raw"

home=$(kit_manifest_value "$run" home)
work=$(kit_work_root "$run")
top=${TMPDIR:-/tmp}
top=${top%/}
[ -n "$top" ] || top=/
step_pid=
fdir=
made_work=
made_home=

# tree PID: PID and each process below it, one pid on each line.
tree() {
  ps -A -o pid= -o ppid= 2>/dev/null | awk -v r="$1" '
    { kid[$2] = kid[$2] " " $1 }
    END {
      q[1] = r; n = 1
      for (i = 1; i <= n; i++) {
        print q[i]
        m = split(kid[q[i]], k, " ")
        for (j = 1; j <= m; j++) q[++n] = k[j]
      }
    }'
}

# end_step: stop the step, when it runs, and each process below it. The
# step script stops its own session when it gets TERM.
end_step() {
  [ -n "$step_pid" ] || return 0
  kit_pid_runs "$step_pid" || return 0
  _t=$(tree "$step_pid")
  # shellcheck disable=SC2086
  kill $_t 2>/dev/null
  _n=0
  while [ "$_n" -lt 200 ]; do
    _left=
    for _p in $_t; do kit_pid_runs "$_p" && _left=1 && break; done
    [ -n "$_left" ] || break
    sleep 0.1
    _n=$((_n + 1))
  done
  for _p in $_t; do kit_pid_runs "$_p" && kill -9 "$_p" 2>/dev/null; done
  wait "$step_pid" 2>/dev/null
  return 0
}

# end_sessions: stop each session of this trace (sessions.tsv) that still
# runs. KIT_TRACE is set, so the stop writes its state.
end_sessions() {
  [ -f "$raw/sessions.tsv" ] || return 0
  cut -f1 "$raw/sessions.tsv" | sort -u | while IFS= read -r _s; do
    [ -n "$_s" ] && [ -f "$run/sessions/$_s/backend" ] || continue
    [ -f "$run/sessions/$_s/stopped" ] && continue
    sh "$KIT_DIR/session.sh" stop "$_s" >/dev/null 2>&1
  done
  return 0
}

# end_recorders: stop the pids of RUN/pids/ with a trace label (TERM, then
# KILL after 5 s), and remove their pid files.
end_recorders() {
  set --
  for _f in "$run"/pids/*; do
    [ -f "$_f" ] || continue
    case $(awk -F '\t' 'NR == 1 { print $1 }' "$_f") in
      "trace proxy" | "trace files") set -- "$@" "${_f##*/}" ;;
    esac
  done
  [ "$#" -gt 0 ] || return 0
  for _p in "$@"; do kit_pid_ours "$run" "$_p" && kill "$_p" 2>/dev/null; done
  _n=0
  while [ "$_n" -lt 50 ]; do
    _left=
    for _p in "$@"; do kit_pid_ours "$run" "$_p" && _left=1 && break; done
    [ -n "$_left" ] || break
    sleep 0.1
    _n=$((_n + 1))
  done
  for _p in "$@"; do
    kit_pid_ours "$run" "$_p" && kill -9 "$_p" 2>/dev/null
    wait "$_p" 2>/dev/null
    rm -f "$run/pids/$_p"
  done
  return 0
}

# tidy: delete the folders that this trace made and that stay empty.
tidy() {
  [ -n "$fdir" ] && rm -rf "$fdir"
  fdir=
  [ -n "$made_work" ] && kit_work_tidy "$work"
  [ -n "$made_home" ] && rmdir "$run/home" 2>/dev/null
  made_work=
  made_home=
  return 0
}

# The EXIT trap: after a signal or an error, stop all and delete the raw
# folder. dash runs no EXIT trap on a signal, so a signal exits first.
finished=
cleanup() {
  [ -z "$finished" ] || return 0
  end_step
  end_sessions
  end_recorders
  tidy
  rm -rf "$raw"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# fail REASON: the trace failed. Print the output of the step, when there
# is one, and the fail line. The EXIT trap deletes the raw folder.
fail() {
  [ -f "$raw/step.out" ] && cat "$raw/step.out"
  echo "trace: $name@$backend fail $1"
  exit "$KIT_FAIL"
}

kit_ms >"$raw/t0"
printf '%s\n' "$checks" >"$raw/checks"

# 3. The network check.
if kit_has_word "$checks" network; then
  python3 -I "$KIT_DIR/trace-proxy.py" --log "$raw/proxy.jsonl" --port-file "$raw/proxy.port" \
    </dev/null >/dev/null 2>"$raw/proxy.err" &
  kit_add_pid "$run" "$!" "trace proxy"
  _n=0
  while [ ! -s "$raw/proxy.port" ] && [ "$_n" -lt 100 ]; do
    sleep 0.1
    _n=$((_n + 1))
  done
  [ -s "$raw/proxy.port" ] || fail no-proxy
fi

# 4. The file check. The folders must exist before the watch starts.
if kit_has_word "$checks" files; then
  if [ "$(uname -s)" != Linux ]; then
    printf 'files\tnot-linux\n' >>"$raw/skipped.tsv"
  else
    if [ "$home" = real ]; then
      hroot=$HOME
    else
      hroot=$run/home
      [ -d "$hroot" ] || made_home=1
    fi
    [ -d "$work" ] || made_work=1
    mkdir -p "$hroot" "$work" || fail no-folder
    fdir=$(mktemp -d "$top/as-trace.XXXXXX") || fail no-temp-folder
    python3 -I "$KIT_DIR/trace-files.py" --out "$fdir/files.jsonl" --ready "$fdir/ready" \
      --top "$top" "$hroot" "$work" </dev/null >/dev/null 2>"$raw/files.err" &
    fpid=$!
    kit_add_pid "$run" "$fpid" "trace files"
    _n=0
    while [ ! -e "$fdir/ready" ] && [ "$_n" -lt 300 ] && kit_pid_runs "$fpid"; do
      sleep 0.1
      _n=$((_n + 1))
    done
    if [ ! -e "$fdir/ready" ]; then
      if ! kit_pid_runs "$fpid"; then
        wait "$fpid"
        _rc=$?
        rm -f "$run/pids/$fpid"
        [ "$_rc" -eq 3 ] || fail no-file-watch
        printf 'files\tno-inotify\n' >>"$raw/skipped.tsv"
      else
        fail no-file-watch
      fi
    fi
  fi
fi

# 5. The step.
KIT_TRACE=$raw
KIT_TRACE_CHECKS=$checks
export KIT_TRACE KIT_TRACE_CHECKS
before=$(awk -F '\t' '$1 == "step"' "$run/manifest.tsv" | wc -l | tr -d ' ')
# The kit itself gets a temp folder in the raw folder, so that the file
# check does not record the temp files of the kit. The agent does not get
# it: "kit session start" gives the agent a clean environment.
mkdir "$raw/tmp" || fail no-temp-folder
# "exec" makes step_pid the pid of step.sh.
(
  TMPDIR=$raw/tmp
  export TMPDIR
  exec sh "$KIT_DIR/step.sh" "$name@$backend" "$@"
) </dev/null >"$raw/step.out" &
step_pid=$!
wait "$step_pid"
code=$?
step_pid=

# 6. Stop the sessions that stay, and the recorders.
end_sessions
end_recorders
if [ -n "$fdir" ]; then
  [ -f "$fdir/files.jsonl" ] && mv "$fdir/files.jsonl" "$raw/files.jsonl"
fi
tidy
skipped_has() { [ -f "$raw/skipped.tsv" ] && awk -F '\t' -v c="$1" '$1 == c { f = 1 } END { exit f ? 0 : 1 }' "$raw/skipped.tsv"; }
if kit_has_word "$checks" terminal; then
  if [ "$home" != fixture ]; then
    skipped_has terminal || printf 'terminal\tnot-fixture-home\n' >>"$raw/skipped.tsv"
  elif [ ! -s "$raw/terminal.cast" ]; then
    skipped_has terminal || printf 'terminal\tno-cast\n' >>"$raw/skipped.tsv"
  fi
fi

# 7. The meta file. The step line is new only when "kit step" added it.
after=$(awk -F '\t' '$1 == "step"' "$run/manifest.tsv" | wc -l | tr -d ' ')
step=$name@$backend
if [ "$after" -gt "$before" ]; then
  _f=$(awk -F '\t' -v n="$name" -v b="$backend" '$1 == "step" && $2 == n && $3 == b { f = $7 } END { print f }' "$run/manifest.tsv")
  case $_f in '' | -) ;; *) step=$_f ;; esac
fi
agent=$(kit_step_field "$name" agent)
agent=${agent:-none}
# A run folder that does not exist: the doctor then writes no file in the
# run and adds no line to its manifest.
version=$(
  AGENT_SIGNALS_RUN=$raw/no-run
  export AGENT_SIGNALS_RUN
  sh "$KIT_DIR/doctor.sh" 2>/dev/null </dev/null |
    awk -v a="$agent" '$1 == "agent:" && $2 == a { v = (NF >= 4) ? $NF : "unknown" } END { print v }'
)
image=
machine=real
if [ "${GITHUB_ACTIONS:-}" = true ]; then
  machine=runner
  image=$(printf '%s %s' "${ImageOS:-}" "${ImageVersion:-}" | sed 's/^ *//; s/ *$//')
fi
mode=login
[ "$home" = fixture ] && mode=fixture
python3 -I -c '
import json, sys
keys = ["agent", "agent_version", "kit", "os", "os_version", "cpu",
        "runner_image", "machine", "backend", "mode", "home", "step", "date"]
meta = dict(zip(keys, sys.argv[2:]))
meta["runner_image"] = meta["runner_image"] or None
with open(sys.argv[1], "w", encoding="utf-8") as f:
    json.dump(meta, f, ensure_ascii=False)
' "$raw/meta.json" "$agent" "${version:-unknown}" "$(kit_manifest_value "$run" kit)" \
  "$(kit_manifest_value "$run" os)" "$(kit_manifest_value "$run" os_version)" \
  "$(kit_manifest_value "$run" cpu)" "$image" "$machine" "$backend" "$mode" "$home" \
  "$step" "$(date -u +%Y-%m-%d)" || fail meta

# 8. The build and the scrub.
python3 -I "$KIT_DIR/trace-build.py" --raw "$raw" --meta "$raw/meta.json" --out "$raw/out" \
  >"$raw/build.log" 2>&1 || {
  sed 's/^/kit: /' "$raw/build.log" >&2
  fail build
}
# The scrub joins the lines of a path that an agent wrapped: a line that
# starts with white space can continue the line before it. Each line of
# trace.json with indent 2 starts with white space, so the scrub would
# read the full file as one block, which is very slow. So the scrub gets
# trace.json with no indent, and the end puts the indent back.
python3 -I -c '
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    d = json.load(f)
with open(sys.argv[1], "w", encoding="utf-8") as f:
    json.dump(d, f, indent=0, ensure_ascii=False)
    f.write("\n")
' "$raw/out/trace.json" || fail build
mkdir -p "$raw/scrubbed"
for f in "$raw"/out/*; do
  [ -f "$f" ] || continue
  # The run folder, the kit folder and the work root can hold names.
  SCRUB_EXTRA="$run
$KIT_ROOT
$work" sh "$KIT_ROOT/tools/scrub.sh" "$f" >"$raw/scrubbed/${f##*/}" 2>"$raw/scrub.log" || fail scrub
done
# The scrub can change a word of the meta, for example the machine
# "runner" when the account name is "runner". The kit wrote the meta, and
# manifest.json holds the same facts, so the meta of the build stays.
python3 -I -c '
import json, sys
path, meta_path = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as f:
    d = json.load(f)
with open(meta_path, encoding="utf-8") as f:
    meta = json.load(f)
d["meta"].update(meta)
with open(path, "w", encoding="utf-8") as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
    f.write("\n")
' "$raw/scrubbed/trace.json" "$raw/meta.json" || fail scrub
mkdir -p "$run/traces"
n=$(for d in "$run"/traces/[0-9]*-*; do [ -d "$d" ] && basename "$d"; done |
  awk -F - '$1 ~ /^[0-9]+$/ { k = $1 + 0; if (k > n) n = k } END { print n + 1 }')
dest=$run/traces/$(printf '%02d' "$n")-$name@$backend
mkdir "$dest" || fail no-trace-folder
mv "$raw"/scrubbed/* "$dest/" || fail no-trace-folder

# 9. The end.
cat "$raw/step.out"
finished=1
rm -rf "$raw"
echo "trace: $dest"
exit "$code"
