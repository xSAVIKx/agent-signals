#!/bin/sh
# Runs the fixture steps of "kit plan" N times, each time in a new run with
# the fixture home (the fake model, no login, no cost), and counts the
# results of each step. A step that does not give the same result each time
# is flaky.
#
# Run: sh tools/kit-repeat.sh [-n N] [--keep DIR] [REGEX]
#   -n N        the number of runs (default 3).
#   --keep DIR  keep the run folders and their archives in DIR. Without
#               it, the script deletes each run when the counts are made.
#   REGEX       run only the steps NAME@BACKEND that match this extended
#               regular expression.
#
# It prints one line for each step, the line "repeat: N runs, S steps, F
# flaky", then one line for each run:
#   step: NAME@BACKEND runs=N ok=A skip=B fail=C [flaky] [reasons: R1 R2 ...]
#   run: K start=TIME end=TIME steps=S fail=F A step is
# flaky when its results or its reasons are not the same in all runs.
# Exit code: 0 when no step is flaky and no step fails, 1 else, 2 for bad
# use.
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
kit=$root/probes/agent/kit.sh
n=3
keep=
re=.
while [ "$#" -gt 0 ]; do
  case $1 in
    -n)
      [ "$#" -ge 2 ] || { echo "usage: kit-repeat.sh [-n N] [--keep DIR] [REGEX]" >&2; exit 2; }
      n=$2
      shift 2
      ;;
    --keep)
      if [ "$#" -lt 2 ] || [ ! -d "$2" ]; then echo "kit-repeat: --keep needs a folder" >&2; exit 2; fi
      keep=$(cd "$2" && pwd)
      shift 2
      ;;
    -*) echo "usage: kit-repeat.sh [-n N] [--keep DIR] [REGEX]" >&2; exit 2 ;;
    *)
      re=$1
      shift
      ;;
  esac
done
case $n in '' | 0* | *[!0-9]*) echo "kit-repeat: -n takes a number from 1" >&2; exit 2 ;; esac

tmp=$(mktemp -d) || exit 1
run=
stop_all() {
  [ -n "$run" ] && AGENT_SIGNALS_RUN=$run sh "$kit" session stop --all >/dev/null 2>&1
}
trap 'stop_all; rm -rf "$tmp"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

: >"$tmp/results"
k=1
while [ "$k" -le "$n" ]; do
  out=$tmp/out-$k
  mkdir -m 700 "$out"
  t0=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  (cd "$out" && sh "$kit" start --home fixture --unattended --out "$out") >"$tmp/start" 2>&1 || {
    echo "kit-repeat: kit start failed:" >&2
    cat "$tmp/start" >&2
    exit 1
  }
  run=$(head -n 1 "$out/.agent-signals-run")
  (cd "$out" && sh "$kit" plan --home fixture) 2>/dev/null \
    | sed -n 's/^step: \([^ ]*\) needs=login .*/\1/p' | grep -E -- "$re" >"$tmp/steps" || :
  while read -r s; do
    (cd "$out" && sh "$kit" step "$s" </dev/null) >"$tmp/step" 2>&1
    echo "kit-repeat: run $k: $(tail -n 1 "$tmp/step")" >&2
  done <"$tmp/steps"
  stop_all
  awk -F '\t' -v k="$k" '$1 == "step" { print k "\t" $2 "@" $3 "\t" $4 "\t" $9 }' "$run/manifest.tsv" >>"$tmp/results"
  t1=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  awk -F '\t' -v k="$k" -v a="$t0" -v b="$t1" '$1 == k { s++; if ($3 == "fail") f++ }
    END { printf "run: %s start=%s end=%s steps=%d fail=%d\n", k, a, b, s, f }' "$tmp/results" >>"$tmp/runs"
  if [ -n "$keep" ]; then
    (cd "$out" && sh "$kit" check) >/dev/null 2>&1
    mv "$run" "$keep/" && mv "$run.tar.gz" "$keep/" 2>/dev/null
  fi
  rm -rf "$out"
  run=
  k=$((k + 1))
done

# One line for each step. A retried step has more than one line in a run:
# its last line counts.
awk -F '\t' -v n="$n" '
  { last[$2 SUBSEP $1] = $3 "\t" $4; if (!($2 in seen)) { seen[$2] = 1; order[++m] = $2 } }
  END {
    flaky = 0; bad = 0
    for (i = 1; i <= m; i++) {
      s = order[i]; ok = sk = fl = 0; runs = 0; first = ""; same = 1; why = ""
      for (k = 1; k <= n; k++) {
        if (!((s SUBSEP k) in last)) continue
        runs++
        split(last[s SUBSEP k], f, "\t")
        if (f[1] == "ok") ok++; else if (f[1] == "skip") sk++; else fl++
        if (f[2] != "-") why = why " " f[2]
        if (first == "") first = last[s SUBSEP k]; else if (first != last[s SUBSEP k]) same = 0
      }
      if (runs != n) same = 0
      if (!same) flaky++
      if (fl) bad++
      printf "step: %s runs=%d ok=%d skip=%d fail=%d%s%s\n", s, runs, ok, sk, fl, same ? "" : " flaky", why ? " reasons:" why : ""
    }
    printf "repeat: %d runs, %d steps, %d flaky\n", n, m, flaky
    exit (flaky || bad) ? 1 : 0
  }' "$tmp/results"
rc=$?
cat "$tmp/runs"
exit "$rc"
