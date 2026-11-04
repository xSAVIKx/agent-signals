#!/bin/sh
# kit check: check the current run folder. It exits 0 only when:
#   1. each step line of manifest.tsv has its file (a "skip" or "fail" line
#      can have no file, "-");
#   2. each file has the SHA-256 of its step line or of an edit line;
#   3. the run folder holds no other file (00-doctor.txt, manifest.tsv,
#      manifest.json and summary.txt are known files);
#   4. no file holds the home folder, the account name, the host name, or
#      the value of an environment variable *_API_KEY or *_TOKEN. The check
#      reads these values now and never writes them. It searches each line
#      and also the text with no line breaks, because a screen wraps long
#      lines. The account name and the host name match as whole words, as
#      in tools/scrub.sh;
#   5. each part of a probe file passes tools/check-probe-output.sh;
#   6. no pid of pids/ runs;
#   7. the run folder belongs to the user and has mode 0700.
# Then it writes manifest.json, summary.txt and the archive
# agent-signals-run-<os>-<time>.tar.gz next to the run folder, and prints
# "run: <path>", "archive: <path>" and "check: pass". The archive holds the
# files of 3 only, not pids/ or sessions/, which can hold the environment
# of a session. Each failure prints "check: <reason>", and the exit code is
# 1.
set -u
. "$(dirname "$0")/lib.sh"

[ "$#" -eq 0 ] || kit_die "$KIT_USAGE" "usage: kit check"
run=$(kit_run_dir) || exit "$KIT_USAGE"
m=$run/manifest.tsv
[ -f "$m" ] || kit_die "$KIT_USAGE" "the run folder has no manifest.tsv"
bad=0
say() {
  echo "check: $*"
  bad=1
}
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

# 1 and 2. The step files and their SHA-256.
awk -F '\t' '$1 == "step" { print $2 "\t" $3 "\t" $4 "\t" $7 "\t" $8 }' "$m" >"$tmp/steps"
while IFS='	' read -r name backend result file sha; do
  if [ "$file" = - ]; then
    case $result in skip | fail) ;; *) say "$name@$backend: the result is $result, but the step has no file" ;; esac
    continue
  fi
  if [ ! -f "$run/$file" ]; then
    say "$file: the file of $name@$backend does not exist"
    continue
  fi
  now=$(kit_sha256 "$run/$file")
  [ "$now" = "$sha" ] && continue
  awk -F '\t' -v f="$file" -v s="$now" '$1 == "edit" && $2 == f && $4 == s { ok = 1 } END { exit ok ? 0 : 1 }' "$m" ||
    say "$file: the file changed after the step, and no 'kit edit' line has its SHA-256"
done <"$tmp/steps"

# 3. The files of the run folder. The archive gets only these.
: >"$tmp/files"
for f in "$run"/* "$run"/.[!.]*; do
  [ -f "$f" ] || continue
  b=$(basename "$f")
  case $b in
    manifest.json | summary.txt) continue ;;
    manifest.tsv | 00-doctor.txt) ;;
    *)
      awk -F '\t' -v f="$b" '$1 == "step" && $7 == f { ok = 1 } END { exit ok ? 0 : 1 }' "$m" ||
        say "$b: the file is not in the manifest"
      ;;
  esac
  echo "$b" >>"$tmp/files"
done

# 4. The raw values of this machine.
q() { printf '%s' "$1" | sed 's/[][\.*^$+?(){}|#]/\\&/g'; }
user=$(id -un 2>/dev/null)
host=$(hostname 2>/dev/null || uname -n)
short=${host%%.*}
: >"$tmp/pats"
if [ -n "${HOME:-}" ] && [ "$HOME" != / ]; then
  printf 'the home folder\t%s\n' "$(q "$HOME")([/\\\\\"' :]|\$)" >>"$tmp/pats"
fi
if [ -n "$user" ] && [ "$user" != dev ]; then
  printf 'the account name\t%s\n' "(^|[^A-Za-z0-9_.-])$(q "$user")([^A-Za-z0-9_-]|\$)" >>"$tmp/pats"
fi
for h in "$host" "$short"; do
  [ -n "$h" ] && [ "$h" != host ] &&
    printf 'the host name\t%s\n' "(^|[^A-Za-z0-9_-])$(q "$h")([^A-Za-z0-9_-]|\$)" >>"$tmp/pats"
done
env | awk -F '=' '$1 ~ /^[A-Za-z0-9_]+_(API_KEY|TOKEN)$/ { print $1 }' | sort -u >"$tmp/vars"
while read -r b; do
  tr -d '\n' <"$run/$b" >"$tmp/joined"
  while IFS='	' read -r what re; do
    if grep -Eq -- "$re" "$run/$b" || grep -Eq -- "$re" "$tmp/joined"; then
      say "$b: the file holds $what"
    fi
  done <"$tmp/pats"
  while read -r v; do
    val=$(printenv "$v")
    [ "${#val}" -ge 8 ] || continue
    if grep -Fq -- "$val" "$run/$b" || grep -Fq -- "$val" "$tmp/joined"; then
      say "$b: the file holds the value of $v"
    fi
  done <"$tmp/vars"
done <"$tmp/files"

# 5. The probe files. A probe file holds the output of each probe after a
# line "################ <probe>" (probes/run.sh). Each part must pass
# tools/check-probe-output.sh.
cpo=$KIT_ROOT/tools/check-probe-output.sh
awk -F '\t' '$1 == "step" && $7 != "-" { print $2 "\t" $7 }' "$m" | while IFS='	' read -r name file; do
  case $(kit_step_field "$name" kind) in probe | terminals) ;; *) continue ;; esac
  [ -f "$run/$file" ] || continue
  if [ ! -f "$cpo" ]; then
    echo "note: this kit has no tools/check-probe-output.sh, so $file is not checked"
    continue
  fi
  rm -rf "$tmp/parts"
  mkdir "$tmp/parts"
  awk -v d="$tmp/parts" '
    /^################ / { o = ""; if (NF == 2 && $2 ~ /^[a-z]+$/) { o = d "/" $2; print $2 >(d "/list") } next }
    o != "" { print >o }' "$run/$file"
  if [ ! -s "$tmp/parts/list" ]; then
    echo "check: $file: no probe output"
    echo x >"$tmp/bad5"
    continue
  fi
  while read -r p; do
    if [ "$p" = terminals ]; then s=probes/terminals/macos.sh; else s=probes/$p/unix.sh; fi
    if [ ! -f "$KIT_ROOT/$s" ]; then
      echo "check: $file: no probe $s"
      echo x >"$tmp/bad5"
    elif ! (cd "$KIT_ROOT" && sh tools/check-probe-output.sh "$s" "$tmp/parts/$p") >"$tmp/cpo" 2>&1; then
      sed "s#^check: #check: $file: #" "$tmp/cpo" | grep '^check: ' | grep -v ' pass$'
      echo x >"$tmp/bad5"
    fi
  done <"$tmp/parts/list"
done
[ -f "$tmp/bad5" ] && bad=1

# 6. The processes that the run started.
for f in "$run"/pids/*; do
  [ -f "$f" ] || continue
  p=$(basename "$f")
  label=$(head -n 1 "$f" | cut -f 1)
  if type kit_pid_ours >/dev/null 2>&1; then
    kit_pid_ours "$run" "$p" && say "the process $p ($label) of the run still runs. Run 'kit session stop --all'"
  else
    kit_pid_runs "$p" && say "the process $p ($label) of the run still runs. Run 'kit session stop --all'"
  fi
done

# 7. The run folder itself, again before the archive.
# shellcheck disable=SC2012,SC2046
set -- $(ls -ldn "$run" | awk '{print $1, $3}')
[ "${2:-}" = "$(id -u)" ] || say "the run folder does not belong to you"
case ${1:-} in drwx------*) ;; *) say "the run folder has the mode ${1:-unknown}, not drwx------" ;; esac

[ "$bad" -eq 0 ] || exit "$KIT_FAIL"

kit_json "$run"
kit_summary "$run"
printf '%s\n' manifest.json summary.txt >>"$tmp/files"
base=$(basename "$run")
parent=$(dirname "$run")
archive=$run.tar.gz
umask 077
set --
for b in $(sort "$tmp/files"); do set -- "$@" "$base/$b"; done
rm -f "$archive"
if ! (cd "$parent" && tar -cf - "$@" | gzip -c >"$archive"); then
  rm -f "$archive"
  kit_die "$KIT_FAIL" "cannot write the archive $archive"
fi
echo "run: $run"
echo "archive: $archive"
echo "check: pass"
