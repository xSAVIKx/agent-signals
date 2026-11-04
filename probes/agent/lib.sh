# shellcheck shell=sh
# Shared functions of the agent kit. Source it from a command file:
#   . "$(dirname "$0")/lib.sh"
# A command file adds its own helpers to its own file. Add a helper here
# only when two or more commands use it.

# KIT_DIR: the folder probes/agent. KIT_ROOT: the folder that holds probes/.
KIT_DIR=$(cd "$(dirname "$0")" && pwd)
KIT_ROOT=$(cd "$KIT_DIR/../.." && pwd)

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

# kit_version: the version of the kit, from the release manifest, or
# "dev" in a clone with no manifest.
kit_version() {
  _v=
  if [ -r "$KIT_ROOT/.release-please-manifest.json" ]; then
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

# kit_run_dir: print the path of the current run folder. It reads
# AGENT_SIGNALS_RUN, else the file .agent-signals-run in the current
# folder. With no run, it exits 2.
kit_run_dir() {
  _r=${AGENT_SIGNALS_RUN:-}
  if [ -z "$_r" ] && [ -r .agent-signals-run ]; then
    _r=$(head -n 1 .agent-signals-run)
  fi
  [ -n "$_r" ] || kit_die "$KIT_USAGE" "no run: do 'kit start' first"
  [ -d "$_r" ] || kit_die "$KIT_USAGE" "the run folder does not exist: $_r"
  echo "$_r"
}

# kit_add_pid RUN PID LABEL: record a pid that the kit started. The kit
# stops only the pids in RUN/pids/, never a process found by its name.
kit_add_pid() {
  mkdir -p "$1/pids"
  echo "$3" >"$1/pids/$2"
}

# kit_pid_runs PID: true when the process runs.
kit_pid_runs() {
  kill -0 "$1" 2>/dev/null
}
