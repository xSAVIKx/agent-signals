#!/bin/sh
# kit start [--home real|throwaway] [--out DIR]: make a new run folder
# DIR/agent-signals-run-<os>-<time>/ with mode 0700, write its path to
# DIR/.agent-signals-run and KIT_ROOT/.agent-signals-run, and print
# "run: <path>" as the last line. With no --out, DIR is the current
# folder. When the current folder cannot hold a run (for example, it is
# in a git work tree), DIR is the folder that holds the kit folder. When
# that folder also cannot hold it, the command refuses. The later commands
# find the run from AGENT_SIGNALS_RUN or the file .agent-signals-run.
#
# It refuses (exit 2) a DIR that does not belong to the user, that other
# accounts can write to, or that is in ~/.claude, ~/.codex, ~/.gemini,
# ~/.cursor or a git work tree.
#
# The run folder holds manifest.tsv. Its first lines are the facts of the
# run, one "KEY<tab>VALUE" line each: kit, os, os_version, cpu, home,
# orchestrator, start. "kit step" adds the step lines, and "kit edit" the
# edit lines. The manifest never holds the host name, the account name or
# the home folder.
set -u
. "$(dirname "$0")/lib.sh"

home=real
out=
while [ "$#" -gt 0 ]; do
  case $1 in
    --home | --out)
      [ "$#" -ge 2 ] || kit_die "$KIT_USAGE" "$1 needs a value"
      [ "$1" = --home ] && home=$2 || out=$2
      shift 2
      ;;
    *) kit_die "$KIT_USAGE" "usage: kit start [--home real|throwaway] [--out DIR]" ;;
  esac
done
case $home in real | throwaway) ;; *) kit_die "$KIT_USAGE" "--home needs real or throwaway" ;; esac
if [ -n "$out" ]; then
  why=$(kit_dir_problem "$out")
  [ -z "$why" ] || kit_die "$KIT_USAGE" "cannot use the folder $out: $why"
else
  # No --out: the current folder, else the folder that holds the kit.
  why=$(kit_dir_problem .)
  out=.
  if [ -n "$why" ]; then
    why2=$(kit_dir_problem "$KIT_ROOT/..")
    [ -z "$why2" ] || kit_die "$KIT_USAGE" "cannot use the current folder ($why) or the folder of the kit ($why2). Give a folder with --out DIR"
    out=$KIT_ROOT/..
  fi
fi

dir=$(cd "$out" && pwd -P)
os=$(kit_os)
run=$dir/agent-signals-run-$os-$(date -u +%Y%m%dT%H%M%SZ)
umask 077
mkdir "$run" 2>/dev/null || kit_die "$KIT_FAIL" "cannot make the run folder $run"
chmod 700 "$run"
{
  printf 'kit\t%s\n' "$(kit_version)"
  printf 'os\t%s\n' "$os"
  printf 'os_version\t%s\n' "$(kit_os_version | tr '\t' ' ')"
  printf 'cpu\t%s\n' "$(kit_cpu)"
  printf 'home\t%s\n' "$home"
  printf 'orchestrator\t%s\n' "$(kit_orchestrator)"
  printf 'start\t%s\n' "$(kit_now)"
} >"$run/manifest.tsv"
kit_json "$run"
kit_summary "$run"
echo "$run" >"$dir/.agent-signals-run"
# Also in the folder of the kit, so that a command in another folder finds
# the run.
[ "$dir" = "$(cd "$KIT_ROOT" && pwd -P)" ] || echo "$run" >"$KIT_ROOT/.agent-signals-run" 2>/dev/null || true
echo "run: $run"
