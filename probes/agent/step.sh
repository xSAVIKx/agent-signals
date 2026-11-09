#!/bin/sh
# kit step NAME@BACKEND [ARGS]: run one step of probes/agent/steps.tsv in
# the current run. With one backend in the list, "kit step NAME" is
# enough.
#
# It runs probes/agent/steps/<kind>.sh with no stdin and these variables:
#   KIT_RUN KIT_ROOT KIT_DIR KIT_STEP KIT_KIND KIT_AGENT KIT_BACKEND
#   KIT_PROMPT KIT_ARGS KIT_WAIT_REGEX KIT_ANSWER KIT_PRE KIT_IDLE_REGEX
#   KIT_BUSY_REGEX KIT_DIALOG_REGEX KIT_WINDOWS
#   KIT_HOME (real, throwaway or fixture) and KIT_OUT (the raw output file).
# ARGS go to the script. The script writes its output to KIT_OUT, and can
# write one line of reason to KIT_OUT.reason. The reason keeps only the
# characters a-z, 0-9, "." and "-"; each other character becomes "-". Its exit code: 0 ok, 1 fail,
# 3 skip (a needed tool is missing), 4 the operator must act.
#
# KIT_OUT is in RUN/.raw/. Then "kit step" scrubs KIT_OUT with
# tools/scrub.sh into RUN/.raw/, moves the result to NN-NAME@BACKEND.txt in
# the run folder, deletes KIT_OUT, and adds the line
#   step<tab>NAME<tab>BACKEND<tab>RESULT<tab>START<tab>END<tab>FILE<tab>SHA256<tab>REASON
# to manifest.tsv ("-" for no file or no reason), writes manifest.json and
# summary.txt, and prints
#   step: NAME@BACKEND ok|skip|fail|operator [REASON]
# A step that needs a login skips with the reason "no-login" in a run
# with a throwaway home, and exits 0. In an unattended run (kit start
# --unattended), a step that needs the operator or the screen, or that has
# the backend "operator", skips with the reason "unattended". "operator" adds no line, so that the
# next call (for example with --ready) gets the same number. When the
# scrub fails, the step is "fail scrub" and has no file. When the
# manifest has the meta line "awake" with caffeinate (kit start on macOS,
# unattended), "caffeinate -i -w PID" runs while the script runs.
# Exit codes: the code of the script (0, 1, 3 or 4), 2 for bad use.
set -u
. "$(dirname "$0")/lib.sh"

[ "$#" -ge 1 ] || kit_die "$KIT_USAGE" "usage: kit step NAME@BACKEND [ARGS]"
arg=$1
shift
run=$(kit_run_dir) || exit "$KIT_USAGE"
why=$(kit_run_problem "$run")
[ -z "$why" ] || kit_die "$KIT_USAGE" "the run folder cannot take a step: $why"
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
case $backend in '' | *[!a-z]*) kit_die "$KIT_USAGE" "bad backend: $backend" ;; esac
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

why=$(kit_login_skip "$home" "$needs" "$(kit_step_field "$name" agent)")
[ -n "$why" ] || why=$(kit_unattended_skip "$(kit_manifest_value "$run" unattended)" "$needs" "$backend")
if [ -n "$why" ]; then
  now=$(kit_now)
  record skip "$now" "$now" - - "$why"
  echo "step: $name@$backend skip $why"
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
# The meta line "awake" of kit start names caffeinate (macOS, unattended):
# it keeps the machine awake while this process runs. The step stops it by
# its pid; -w also ends it when this process ends.
awake=
case $(kit_manifest_value "$run" awake) in
  caffeinate*)
    if command -v caffeinate >/dev/null 2>&1; then
      caffeinate -i -w "$$" </dev/null >/dev/null 2>&1 &
      awake=$!
    fi
    ;;
esac
trap '[ -z "$awake" ] || kill "$awake" 2>/dev/null' EXIT
KIT_RUN=$run KIT_ROOT=$KIT_ROOT KIT_DIR=$KIT_DIR KIT_STEP=$name KIT_KIND=$kind KIT_BACKEND=$backend \
  KIT_AGENT=$(kit_step_field "$name" agent) \
  KIT_PROMPT=$(kit_step_field "$name" prompt) \
  KIT_ARGS=$(kit_step_field "$name" args) \
  KIT_WAIT_REGEX=$(kit_step_field "$name" wait_regex) \
  KIT_ANSWER=$(kit_step_field "$name" answer) \
  KIT_PRE=$(kit_step_field "$name" pre) \
  KIT_IDLE_REGEX=$(kit_step_field "$name" idle_regex) \
  KIT_BUSY_REGEX=$(kit_step_field "$name" busy_regex) \
  KIT_DIALOG_REGEX=$(kit_step_field "$name" dialog_regex) \
  KIT_WINDOWS=$(kit_step_field "$name" windows) \
  KIT_HOME=$home KIT_OUT=$out \
  sh "$script" "$@" </dev/null
code=$?
if [ -n "$awake" ]; then
  kill "$awake" 2>/dev/null
  wait "$awake" 2>/dev/null
  awake=
fi
end=$(kit_now)
reason=
[ -f "$out.reason" ] && reason=$(head -n 1 "$out.reason" | sed 's/[^a-z0-9.-]/-/g' | cut -c1-80)
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
  # The run folder and the kit folder can hold spaces and names.
  if SCRUB_EXTRA="$run
$KIT_ROOT" sh "$KIT_ROOT/tools/scrub.sh" "$out" >"$work/$nn.txt" 2>"$work/$nn.scrub"; then
    sed 's/^/kit: /' "$work/$nn.scrub" >&2
    mv "$work/$nn.txt" "$run/$file"
    sha=$(kit_sha256 "$run/$file")
  else
    rm -f "$work/$nn.txt"
    file=-
    result=fail reason=scrub code=1
  fi
else
  file=-
fi
rm -f "$out" "$out.reason" "$work/$nn.scrub"
rmdir "$work" 2>/dev/null
[ "$result" = ok ] && [ "$file" = - ] && result=fail reason=no-output code=1
record "$result" "$start" "$end" "$file" "$sha" "${reason:--}"
echo "step: $name@$backend $result${reason:+ $reason}"
exit "$code"
