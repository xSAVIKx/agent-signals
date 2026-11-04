# shellcheck shell=sh
# Shared functions of the agent kit. Source it from a command file:
#   . "$(dirname "$0")/lib.sh"
# A command file adds its own helpers to its own file. Add a helper here
# only when two or more commands use it.

# KIT_DIR: the folder probes/agent. KIT_ROOT: the folder that holds probes/.
# kit.sh exports both. A file that runs with no kit.sh before it gets them
# from its own path, so it must be in probes/agent/.
KIT_DIR=${KIT_DIR:-$(cd "$(dirname "$0")" && pwd)}
KIT_ROOT=${KIT_ROOT:-$(cd "$KIT_DIR/../.." && pwd)}

# Exit codes. The command files use them.
# shellcheck disable=SC2034
KIT_OK=0 KIT_FAIL=1 KIT_USAGE=2 KIT_MISSING=3 KIT_OPERATOR=4

# kit_die CODE TEXT: print "kit: TEXT" on stderr and exit with CODE.
kit_die() {
  _c=$1
  shift
  echo "kit: $*" >&2
  exit "$_c"
}

# kit_version: the version of the kit. A release kit has the file VERSION
# at its root. A clone reads the release manifest. Else "dev".
kit_version() {
  _v=
  if [ -r "$KIT_ROOT/VERSION" ]; then
    _v=$(head -n 1 "$KIT_ROOT/VERSION")
  elif [ -r "$KIT_ROOT/.release-please-manifest.json" ]; then
    _v=$(sed -n 's/.*"\.": *"\([^"]*\)".*/\1/p' "$KIT_ROOT/.release-please-manifest.json" | head -n 1)
  fi
  echo "${_v:-dev}"
}

# kit_os: linux or macos.
kit_os() {
  case $(uname -s) in
    Darwin) echo macos ;;
    *) echo linux ;;
  esac
}

# kit_run_dir: print the path of the current run folder. It reads, in
# this order: AGENT_SIGNALS_RUN, the file .agent-signals-run in the current
# folder, the file .agent-signals-run in KIT_ROOT. kit start writes both
# files, so a command in a new shell with a new current folder finds the
# run. With no run, it exits 2.
kit_run_dir() {
  _r=${AGENT_SIGNALS_RUN:-}
  if [ -z "$_r" ] && [ -r .agent-signals-run ]; then
    _r=$(head -n 1 .agent-signals-run)
  fi
  if [ -z "$_r" ] && [ -r "$KIT_ROOT/.agent-signals-run" ]; then
    _r=$(head -n 1 "$KIT_ROOT/.agent-signals-run")
  fi
  [ -n "$_r" ] || kit_die "$KIT_USAGE" "no run: do 'kit start' first"
  [ -d "$_r" ] || kit_die "$KIT_USAGE" "the run folder does not exist: $_r"
  echo "$_r"
}

# kit_pid_start PID: the start time of the process, as ps prints it, with
# the spaces squeezed. Empty when the process does not run.
kit_pid_start() {
  ps -o lstart= -p "$1" 2>/dev/null | tr -s ' ' | sed 's/^ //; s/ $//'
}

# kit_add_pid RUN PID LABEL: record a pid that the kit started, as the file
# RUN/pids/PID with one line "LABEL<tab>START". The kit stops only the pids
# in RUN/pids/, never a process found by its name.
kit_add_pid() {
  mkdir -p "$1/pids"
  printf '%s\t%s\n' "$3" "$(kit_pid_start "$2")" >"$1/pids/$2"
}

# kit_pid_runs PID: true when the process runs.
kit_pid_runs() {
  kill -0 "$1" 2>/dev/null
}

# kit_pid_ours RUN PID: true when the process runs and has the start time
# of RUN/pids/PID. A pid that the system gave again to a new process is not
# ours, so the kit does not stop it.
kit_pid_ours() {
  [ -r "$1/pids/$2" ] || return 1
  kit_pid_runs "$2" || return 1
  _want=$(awk -F '	' 'NR == 1 { print $2 }' "$1/pids/$2")
  [ -n "$_want" ] || return 1
  [ "$_want" = "$(kit_pid_start "$2")" ]
}
