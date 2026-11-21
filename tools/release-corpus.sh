#!/bin/sh
# Builds the corpus archives of a release and their SHA256SUMS.
#
# Usage: sh tools/release-corpus.sh VERSION OUTDIR [INDEXDIR]
#
# The script writes these files to OUTDIR:
#   agent-signals-corpus-VERSION.tar.gz
#   agent-signals-corpus-VERSION.zip
#   SHA256SUMS
# Each archive holds the folder agent-signals-corpus-VERSION/ with corpus/,
# schema/, facts/, LICENSE and a short README.md. With INDEXDIR, each
# archive also holds INDEXDIR/corpus.json and INDEXDIR/facts.json. The site
# builder makes these two files (tools/cmd/site).
#
# The archives hold the files of HEAD (git archive), so a change that is not
# committed is not in them. git archive sorts the names, sets each mtime to
# the commit time of HEAD, sets the owner to root, and writes gzip with no
# name and no time. The zip format stores local time, so the script sets
# TZ=UTC0. So the same commit and the same index files give the same bytes.
#
# SHA256SUMS lists each file in OUTDIR, also the files that were in OUTDIR
# before the script started. The release workflow puts the kit archives in
# OUTDIR first, so SHA256SUMS covers all the assets of the release.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
[ "$#" -ge 2 ] && [ "$#" -le 3 ] || {
  echo "usage: release-corpus.sh VERSION OUTDIR [INDEXDIR]" >&2
  exit 2
}
ver=$1 out=$2 idx=${3:-}
case $ver in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "release-corpus: VERSION is not X.Y.Z: $ver" >&2; exit 2 ;;
esac
case $ver in
  *[!0-9A-Za-z.+-]*) echo "release-corpus: VERSION has a bad character: $ver" >&2; exit 2 ;;
esac
mkdir -p "$out"
out=$(cd "$out" && pwd)
name=agent-signals-corpus-$ver

set -- "--prefix=$name/" "--add-virtual-file=$name/README.md:# agent-signals corpus $ver

This archive holds the data of the release corpus-v$ver of
https://github.com/xSAVIKx/agent-signals.

| Path | Content |
|---|---|
| \`corpus/\` | One folder for each agent: the screens, a \`.yaml\` file for each screen, and \`coverage.yaml\`. |
| \`schema/\` | The JSON schemas of the files. |
| \`facts/\` | The facts, one Markdown file for each fact. |
| \`corpus.json\` | An index of each agent and each screen, if it is in the archive. |
| \`facts.json\` | An index of each fact, if it is in the archive. |
| \`LICENSE\` | The license. |

To verify the archive, download SHA256SUMS from the same release and run:

    sha256sum -c SHA256SUMS --ignore-missing
    gh attestation verify $name.tar.gz --repo xSAVIKx/agent-signals
"
if [ -n "$idx" ]; then
  for f in corpus.json facts.json; do
    [ -f "$idx/$f" ] || { echo "release-corpus: no $f in $idx" >&2; exit 1; }
  done
  idx=$(cd "$idx" && pwd)
  set -- "$@" "--add-file=$idx/corpus.json" "--add-file=$idx/facts.json"
fi

for fmt in tar.gz zip; do
  (cd "$root" && TZ=UTC0 git -c tar.umask=022 archive --format="$fmt" -o "$out/$name.$fmt" \
    "$@" HEAD corpus schema facts LICENSE)
done

# Write the list to a temporary name, so that it does not list itself.
(
  cd "$out"
  rm -f SHA256SUMS
  find . -maxdepth 1 -type f ! -name SHA256SUMS ! -name .SHA256SUMS.tmp -print |
    sed 's|^\./||' | LC_ALL=C sort |
    while IFS= read -r f; do sha256sum -- "$f"; done >.SHA256SUMS.tmp
  mv .SHA256SUMS.tmp SHA256SUMS
)
echo "release-corpus: wrote $name.tar.gz, $name.zip and SHA256SUMS to $out"
