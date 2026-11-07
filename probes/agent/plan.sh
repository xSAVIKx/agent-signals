#!/bin/sh
# kit plan [--home real|throwaway|fixture]: print the steps that this machine can
# run, in the order of probes/agent/steps.tsv, one line for each step and
# backend:
#   step: <name>@<backend> needs=<needs> cost=<cost> [skip=no-login] measures=<text>
# A step is in the plan when its script probes/agent/steps/<kind>.sh
# exists, its OS is this OS, its agent is on PATH and the tool of its
# backend is installed. A step that needs a login gets "skip=no-login"
# with a throwaway home. With no --home, the plan uses the home mode of
# the current run, else "real".
set -u
. "$(dirname "$0")/lib.sh"

home=
while [ "$#" -gt 0 ]; do
  case $1 in
    --home)
      [ "$#" -ge 2 ] || kit_die "$KIT_USAGE" "--home needs real, throwaway or fixture"
      home=$2
      shift 2
      ;;
    *) kit_die "$KIT_USAGE" "usage: kit plan [--home real|throwaway|fixture]" ;;
  esac
done
if [ -z "$home" ]; then
  run=$(kit_run_dir 2>/dev/null) && home=$(kit_manifest_value "$run" home 2>/dev/null)
  home=${home:-real}
fi
case $home in real | throwaway | fixture) ;; *) kit_die "$KIT_USAGE" "--home needs real, throwaway or fixture" ;; esac

os=$(kit_os)
agents=" $(kit_agents | tr '\n' ' ') "
backends=" $(kit_backends | tr '\n' ' ') "

# The columns by their names, in a fixed order for "read". Each value is
# not empty ("-" at least), so the tabs do not merge.
awk -F '\t' '
  /^#/ || NF == 0 { next }
  !h { for (i = 1; i <= NF; i++) c[$i] = i; h = 1; next }
  { print $c["name"] "\t" $c["kind"] "\t" $c["agent"] "\t" $c["backends"] "\t" $c["os"] "\t" $c["needs"] "\t" $c["cost"] "\t" $c["measures"] }' "$KIT_STEPS" |
  while IFS='	' read -r name kind agent blist oslist needs cost measures; do
    [ -f "$KIT_DIR/steps/$kind.sh" ] || continue
    kit_has_word "$oslist" "$os" || continue
    if [ "$agent" != - ]; then
      case $agents in *" $agent "*) ;; *) continue ;; esac
    fi
    skip=
    why=$(kit_login_skip "$home" "$needs" "$agent")
    [ -z "$why" ] || skip=" skip=$why"
    for b in $(echo "$blist" | tr ',' ' '); do
      case $backends in *" $b "*) ;; *) continue ;; esac
      echo "step: $name@$b needs=$needs cost=$cost$skip measures=$measures"
    done
  done
exit 0
