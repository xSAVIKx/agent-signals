#!/bin/sh
# check-traces.sh RUN [--passed FILE]: check each trace of a kit run.
#
# A trace RUN/traces/NN-NAME@BACKEND/trace.json passes when:
#   1. it is JSON,
#   2. meta.checks holds "ebpf",
#   3. summary.programs has one item or more, and
#   4. the corpus validator (tools/cmd/validate) finds no problem in it.
#
# For the validator, the script makes a temp root with a copy of each file
# of schema/, the empty folders corpus/ and facts/ (the validator stops
# with exit 2 without them), and each trace as
# traces/AGENT/VERSION/NN-STEP/trace.json. AGENT and VERSION come from
# meta.agent and meta.agent_version, and NN-STEP is the name of the trace
# folder. Each character of a part outside [A-Za-z0-9._@-] becomes "-".
# Then it runs "cd tools && go run ./cmd/validate ROOT" one time for all
# traces, and deletes the temp root at the end.
#
# The output: one line "check: NN-NAME@BACKEND ok" or
# "check: NN-NAME@BACKEND fail REASON" for each trace. The problems of the
# validator for a trace follow its fail line with the prefix "check:   ".
# REASON is one of bad-json, no-ebpf, no-programs, invalid and
# validator-error.
#
# With --passed FILE, the script writes the name NN-NAME@BACKEND of each
# trace that passed to FILE, one on each line, also when another trace
# failed and the script exits 1. FILE is empty only when no trace passed.
#
# Exit codes: 0 when each trace passed, 1 when a trace failed or when
# RUN/traces has no trace, 2 for bad use.
set -u

usage() {
  echo "usage: sh tools/check-traces.sh RUN [--passed FILE]" >&2
  exit 2
}

run=
passed=
while [ $# -gt 0 ]; do
  case $1 in
    --passed)
      [ $# -ge 2 ] && [ -n "$2" ] || usage
      passed=$2
      shift 2
      ;;
    -*) usage ;;
    *)
      [ -z "$run" ] || usage
      run=$1
      shift
      ;;
  esac
done
[ -n "$run" ] || usage
[ -d "$run" ] || {
  echo "check: no folder $run" >&2
  exit 2
}

root=$(cd "$(dirname "$0")/.." && pwd) || exit 2
if [ -n "$passed" ]; then
  : >"$passed" || exit 2
fi

tmp=$(mktemp -d) || exit 1
[ -n "$tmp" ] && [ -d "$tmp" ] || exit 1
cleanup() { rm -rf -- "$tmp"; }
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

# part TEXT: TEXT with each character outside [A-Za-z0-9._@-] changed to
# "-". An empty part, "." and ".." become "-", so that each part is one
# folder.
part() {
  _p=$(printf '%s' "$1" | tr -c 'A-Za-z0-9._@-' '-')
  case $_p in "" | . | ..) _p=- ;; esac
  printf '%s\n' "$_p"
}

vroot=$tmp/root
mkdir -p "$vroot/schema" "$vroot/corpus" "$vroot/facts" "$vroot/traces" || exit 1
for f in "$root"/schema/*; do
  [ -f "$f" ] && { cp "$f" "$vroot/schema/" || exit 1; }
done

# list.tsv: NAME<tab>REL<tab>REASON for each trace. REL is the path of the
# copy below the temp root, or "-" for a trace that is not JSON. REASON is
# empty until a check fails.
: >"$tmp/list.tsv"
count=0
for j in "$run"/traces/*/trace.json; do
  [ -f "$j" ] || continue
  count=$((count + 1))
  d=${j%/trace.json}
  name=${d##*/}
  # The facts of the trace: AGENT, VERSION, then ok or the reason.
  if ! python3 -I -c '
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        d = json.load(f)
    meta = d["meta"]
    agent = str(meta.get("agent") or "")
    version = str(meta.get("agent_version") or "")
except Exception:
    print("\n\nbad-json")
    sys.exit(0)
reason = "ok"
progs = (d.get("summary") or {}).get("programs")
if "ebpf" not in (meta.get("checks") or []):
    reason = "no-ebpf"
elif not isinstance(progs, list) or not progs:
    reason = "no-programs"
print(agent.replace("\n", " "))
print(version.replace("\n", " "))
print(reason)' "$j" >"$tmp/facts"; then
    printf '%s\t-\t%s\n' "$name" bad-json >>"$tmp/list.tsv"
    continue
  fi
  agent=$(sed -n 1p "$tmp/facts")
  version=$(sed -n 2p "$tmp/facts")
  reason=$(sed -n 3p "$tmp/facts")
  [ "$reason" = ok ] && reason=
  if [ "$reason" = bad-json ]; then
    printf '%s\t-\t%s\n' "$name" bad-json >>"$tmp/list.tsv"
    continue
  fi
  rel=traces/$(part "$agent")/$(part "$version")/$(part "$name")
  mkdir -p "$vroot/$rel" && cp "$j" "$vroot/$rel/trace.json" || exit 1
  printf '%s\t%s\t%s\n' "$name" "$rel/trace.json" "$reason" >>"$tmp/list.tsv"
done

if [ "$count" = 0 ]; then
  echo "check: no trace in $run/traces"
  exit 1
fi

# The validator, one time for all traces. Exit 0: no problem. Exit 1: a
# problem line "PATH: MESSAGE" on stdout for each problem. Another exit: it
# could not check. "go run" also exits 1 when the build fails, with no
# problem line.
(cd "$root/tools" && go run ./cmd/validate "$vroot") >"$tmp/validate.log" 2>"$tmp/validate.err"
vrc=$?
# A problem line that names no trace (for example "traces: ...") makes
# each trace fail, because the script cannot tell which trace it is. So
# does an exit 1 with no problem line.
other=0
if [ "$vrc" = 1 ]; then
  other=$(awk -F '\t' 'NR == FNR { if ($2 != "-") p[$2 ": "] = 1; next }
    /^validate: / { next }
    { all++; f = 0; for (k in p) if (index($0, k) == 1) f = 1; if (!f) n++ }
    END { print (all == 0) ? 1 : n + 0 }' "$tmp/list.tsv" "$tmp/validate.log")
fi

fail=0
while IFS="$(printf '\t')" read -r name rel reason; do
  probs=
  if [ -z "$reason" ]; then
    if [ "$vrc" != 0 ] && [ "$vrc" != 1 ]; then
      reason=validator-error
    elif [ "$vrc" = 1 ]; then
      probs=$(awk -v k="$rel: " 'index($0, k) == 1' "$tmp/validate.log")
      if [ -n "$probs" ]; then
        reason=invalid
      elif [ "$other" != 0 ]; then
        reason=validator-error
      fi
    fi
  fi
  if [ -z "$reason" ]; then
    echo "check: $name ok"
    [ -z "$passed" ] || printf '%s\n' "$name" >>"$passed"
  else
    fail=1
    echo "check: $name fail $reason"
    [ -z "$probs" ] || printf '%s\n' "$probs" | sed 's/^/check:   /'
  fi
done <"$tmp/list.tsv"

if [ "$vrc" != 0 ] && [ "$vrc" != 1 ] || [ "$other" != 0 ]; then
  echo "check: the validator (exit $vrc):"
  { grep -v '^traces/[^:]*/trace.json: ' "$tmp/validate.log"; cat "$tmp/validate.err"; } |
    head -n 20 | sed 's/^/check:   /'
fi
exit "$fail"
