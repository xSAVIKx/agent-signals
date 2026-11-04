#!/bin/sh
# kit step NAME@BACKEND [ARGS]: run one step of probes/agent/steps.tsv in
# the current run. With one backend in the list, "kit step NAME" is
# enough.
#
# It runs probes/agent/steps/<kind>.sh with no stdin and these variables:
#   KIT_RUN KIT_ROOT KIT_DIR KIT_STEP KIT_KIND KIT_AGENT KIT_BACKEND
#   KIT_PROMPT KIT_WAIT_REGEX KIT_ANSWER KIT_PRE KIT_IDLE_REGEX KIT_WINDOWS
#   KIT_HOME (real or throwaway) and KIT_OUT (the raw output file).
# ARGS go to the script. The script writes its output to KIT_OUT, and can
# write one line of reason to KIT_OUT.reason. Its exit code: 0 ok, 1 fail,
# 3 skip (a needed tool is missing), 4 the operator must act.
#
# KIT_OUT is in RUN/.raw/. Then "kit step" scrubs KIT_OUT with tools/scrub.sh into
# NN-NAME@BACKEND.txt in the run folder, deletes KIT_OUT, adds the line
#   step<tab>NAME<tab>BACKEND<tab>RESULT<tab>START<tab>END<tab>FILE<tab>SHA256<tab>REASON
# to manifest.tsv ("-" for no file or no reason), writes manifest.json and
# summary.txt, and prints
#   step: NAME@BACKEND ok|skip|fail|operator [REASON]
# A step that needs a login skips with the reason "no-login" in a run
# with a throwaway home, and exits 0. "operator" adds no line, so that the
# next call (for example with --ready) gets the same number.
# Exit codes: the code of the script (0, 1, 3 or 4), 2 for bad use.
set -u
. "$(dirname "$0")/lib.sh"

[ "$#" -ge 1 ] || kit_die "$KIT_USAGE" "usage: kit step NAME@BACKEND [ARGS]"
arg=$1
shift
run=$(kit_run_dir) || exit "$KIT_USAGE"
name=${arg%%@*}
case $name in '' | *[!a-z0-9-]*) kit_die "$KIT_USAGE" "bad step name: $name" ;; esac
kind=$(kit_step_field "$name" kind) || kit_die "$KIT_USAGE" "unknown step: $name. Run 'kit plan'"
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
kit_has_word "$blist" "$backend" || kit_die "$KIT_USAGE" "the step $name has no backend $backend. Use one of: $blist"
kit_has_word "$(kit_step_field "$name" os)" "$(kit_os)" || kit_die "$KIT_USAGE" "the step $name is not for $(kit_os)"
script=$KIT_DIR/steps/$kind.sh
[ -f "$script" ] || kit_die "$KIT_USAGE" "this kit has no script for the step $name (steps/$kind.sh)"
home=$(kit_manifest_value "$run" home)
needs=$(kit_step_field "$name" needs)

# record RESULT START END FILE SHA REASON: add a step line, and write the
# JSON manifest and the summary again.
record() {
  printf 'step\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$backend" "$1" "$2" "$3" "$4" "$5" "$6" >>"$run/manifest.tsv"
  kit_json "$run"
  kit_summary "$run"
}

if [ "$needs" = login ] && [ "$home" = throwaway ]; then
  now=$(kit_now)
  record skip "$now" "$now" - - no-login
  echo "step: $name@$backend skip no-login"
  exit 0
fi

# The number is one more than the highest number of a file in the manifest
# (00-doctor.txt is 00).
n=$(awk -F '\t' '$1 == "step" && $7 ~ /^[0-9][0-9]*-/ { k = substr($7, 1, index($7, "-") - 1) + 0; if (k > n) n = k } END { print n + 1 }' "$run/manifest.tsv")
nn=$(printf '%02d' "$n")
file=$nn-$name@$backend.txt
work=$run/.raw
mkdir -p "$work"
out=$work/$nn.raw
rm -f "$out" "$out.reason"
start=$(kit_now)
KIT_RUN=$run KIT_ROOT=$KIT_ROOT KIT_DIR=$KIT_DIR KIT_STEP=$name KIT_KIND=$kind KIT_BACKEND=$backend \
  KIT_AGENT=$(kit_step_field "$name" agent) \
  KIT_PROMPT=$(kit_step_field "$name" prompt) \
  KIT_WAIT_REGEX=$(kit_step_field "$name" wait_regex) \
  KIT_ANSWER=$(kit_step_field "$name" answer) \
  KIT_PRE=$(kit_step_field "$name" pre) \
  KIT_IDLE_REGEX=$(kit_step_field "$name" idle_regex) \
  KIT_WINDOWS=$(kit_step_field "$name" windows) \
  KIT_HOME=$home KIT_OUT=$out \
  sh "$script" "$@" </dev/null
code=$?
end=$(kit_now)
reason=
[ -f "$out.reason" ] && reason=$(head -n 1 "$out.reason" | tr '\t' ' ')
case $code in
  0) result=ok ;;
  3) result=skip ;;
  4) result=operator ;;
  1) result=fail ;;
  *) result=fail reason=${reason:-exit-$code} code=1 ;;
esac

if [ "$result" = operator ]; then
  rm -f "$out" "$out.reason"
  rmdir "$work" 2>/dev/null
  echo "step: $name@$backend operator${reason:+ $reason}"
  exit "$code"
fi
sha=-
if [ -f "$out" ]; then
  sh "$KIT_ROOT/tools/scrub.sh" "$out" >"$run/$file" 2>"$work/$nn.scrub"
  sed 's/^/kit: /' "$work/$nn.scrub" >&2
  sha=$(kit_sha256 "$run/$file")
else
  file=-
fi
rm -f "$out" "$out.reason" "$work/$nn.scrub"
rmdir "$work" 2>/dev/null
[ "$result" = ok ] && [ "$file" = - ] && result=fail reason=no-output code=1
record "$result" "$start" "$end" "$file" "$sha" "${reason:--}"
echo "step: $name@$backend $result${reason:+ $reason}"
exit "$code"
