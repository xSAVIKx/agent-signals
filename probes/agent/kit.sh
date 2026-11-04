#!/bin/sh
# The agent kit: the commands that an agent runs to do the probe kit and
# to drive test sessions of other agents. Read
# docs/design/2026-11-01-agent-run-kit.md.
#
#   sh probes/agent/kit.sh <command> [arguments]
#
# Each command is the file probes/agent/<command>.sh. Exit codes of each
# command: 0 ok, 1 fail, 2 bad use, 3 a needed tool is missing, 4 the
# operator must act. All state is in files in the run folder, so each
# command can run in a new shell.
set -u
here=$(cd "$(dirname "$0")" && pwd)
# The command files and the step scripts in steps/ source lib.sh. They find
# the kit folders from these variables, not from their own path.
KIT_DIR=$here
KIT_ROOT=$(cd "$here/../.." && pwd)
export KIT_DIR KIT_ROOT
. "$here/lib.sh"

# Under Git Bash, MSYS or Cygwin on Windows, the Windows kit is the right
# kit: hand over to it.
case $(uname -s) in
  MINGW*|MSYS*|CYGWIN*)
    if [ -z "${AGENT_SIGNALS_NO_HANDOVER:-}" ]; then
      for ps in pwsh powershell; do
        if command -v "$ps" >/dev/null 2>&1; then
          exec "$ps" -NoProfile -ExecutionPolicy Bypass -File "$here/kit.ps1" "$@"
        fi
      done
      kit_die 3 "this is Windows, and no PowerShell is on PATH"
    fi
    ;;
esac

cmd=${1:-}
case $cmd in
  ''|-h|--help|help)
    echo "usage: kit <command> [arguments]"
    echo "commands:"
    for f in "$here"/*.sh; do
      n=$(basename "$f" .sh)
      case $n in kit|lib) continue ;; esac
      echo "  $n"
    done
    [ -n "$cmd" ] && exit 0
    exit 2
    ;;
  version)
    kit_version
    exit 0
    ;;
esac
case $cmd in
  *[!a-z-]*) kit_die 2 "unknown command: $cmd" ;;
esac
[ -f "$here/$cmd.sh" ] || kit_die 2 "unknown command: $cmd"
shift
exec sh "$here/$cmd.sh" "$@"
