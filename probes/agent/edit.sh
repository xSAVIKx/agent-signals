#!/bin/sh
# kit edit FILE REASON [COUNT]: record a change by hand in a file of the
# run, after the agent replaced a name that the scrub missed. It adds the
# line
#   edit<tab>FILE<tab>REASON[ COUNT]<tab>SHA256
# to manifest.tsv, with the SHA-256 of the file now. REASON is one of
# project, person, company, host, path or other: the kind of name that the
# agent replaced. COUNT is the number of changes. The reason holds no free
# text, so the manifest cannot get a name. "kit check" then accepts the
# new content of the file.
set -u
. "$(dirname "$0")/lib.sh"

usage="usage: kit edit FILE project|person|company|host|path|other [COUNT]"
[ "$#" -ge 2 ] && [ "$#" -le 3 ] || kit_die "$KIT_USAGE" "$usage"
run=$(kit_run_dir) || exit "$KIT_USAGE"
why=$(kit_run_problem "$run")
[ -z "$why" ] || kit_die "$KIT_USAGE" "the run folder cannot take an edit: $why"
file=$(basename "$1")
case $2 in
  project | person | company | host | path | other) reason=$2 ;;
  *) kit_die "$KIT_USAGE" "$usage" ;;
esac
if [ "$#" -eq 3 ]; then
  case $3 in '' | *[!0-9]*) kit_die "$KIT_USAGE" "$usage" ;; esac
  reason="$reason $3"
fi
[ -f "$run/$file" ] || kit_die "$KIT_USAGE" "the run has no file $file"
awk -F '\t' -v f="$file" '$1 == "step" && $7 == f { found = 1 } END { exit found ? 0 : 1 }' "$run/manifest.tsv" ||
  kit_die "$KIT_USAGE" "$file is not a step file of the manifest"
sha=$(kit_sha256 "$run/$file")
printf 'edit\t%s\t%s\t%s\n' "$file" "$reason" "$sha" >>"$run/manifest.tsv"
kit_json "$run"
echo "edit: $file $reason"
