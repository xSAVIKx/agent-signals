#!/bin/sh
# Test tools/release-corpus.sh. The test builds the archives of HEAD in a
# temporary folder and checks the file list of each archive, SHA256SUMS,
# and that two builds give the same bytes. It deletes the folder when it
# ends, also when it fails.
# Run: sh tools/test-release-corpus.sh
set -eu
dir=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$dir/.." && pwd)
script=$dir/release-corpus.sh
tmp=$(mktemp -d)
trap 'rm -rf "${tmp:?}"' EXIT
fail=0
ver=0.0.0-test
name=agent-signals-corpus-$ver

ok() { echo "pass: $1"; }
bad() { echo "fail: $1"; fail=1; }

# names OUT ARCHIVE: write the sorted file names of ARCHIVE (tar.gz or zip)
# to OUT, without the folder entries.
names() {
  case $2 in
    *.tar.gz) tar -tzf "$2" ;;
    *.zip) python3 -I -c 'import sys, zipfile; print("\n".join(zipfile.ZipFile(sys.argv[1]).namelist()))' "$2" ;;
  esac | grep -v '/$' | LC_ALL=C sort >"$1"
}

# The expected file names: the tracked files of HEAD and the extra files.
(cd "$root" && git ls-tree -r --name-only HEAD corpus schema facts LICENSE) |
  sed "s|^|$name/|" >"$tmp/tracked"
{ cat "$tmp/tracked"; echo "$name/README.md"; } | LC_ALL=C sort >"$tmp/want-plain"
{ cat "$tmp/tracked"; printf '%s\n' "$name/README.md" "$name/corpus.json" "$name/facts.json"; } |
  LC_ALL=C sort >"$tmp/want-index"

# 1. No index folder: two archives and SHA256SUMS.
sh "$script" "$ver" "$tmp/plain" >/dev/null
(cd "$tmp/plain" && ls) | LC_ALL=C sort >"$tmp/ls"
printf '%s\n' SHA256SUMS "$name.tar.gz" "$name.zip" | LC_ALL=C sort >"$tmp/ls-want"
if cmp -s "$tmp/ls" "$tmp/ls-want"; then ok "the output folder holds two archives and SHA256SUMS"; else bad "output folder: $(tr '\n' ' ' <"$tmp/ls")"; fi
if (cd "$tmp/plain" && sha256sum -c --quiet SHA256SUMS); then ok "SHA256SUMS matches the archives"; else bad "SHA256SUMS does not match"; fi
if [ "$(wc -l <"$tmp/plain/SHA256SUMS")" -eq 2 ]; then ok "SHA256SUMS has two lines"; else bad "SHA256SUMS line count"; fi
for ext in tar.gz zip; do
  names "$tmp/got" "$tmp/plain/$name.$ext"
  if cmp -s "$tmp/got" "$tmp/want-plain"; then ok "$ext holds corpus, schema, facts, LICENSE and README.md"; else
    bad "$ext file list"; diff "$tmp/want-plain" "$tmp/got" | head -10 | sed 's/^/  /'; fi
done
if tar -xzOf "$tmp/plain/$name.tar.gz" "$name/README.md" | grep -q "^# agent-signals corpus $ver\$"; then
  ok "README.md names the version"; else bad "README.md has no version line"; fi
if tar -xzOf "$tmp/plain/$name.tar.gz" "$name/LICENSE" | cmp -s - "$root/LICENSE"; then
  ok "LICENSE has the bytes of the file"; else bad "LICENSE differs"; fi
if tar -tzvf "$tmp/plain/$name.tar.gz" | awk '$2 != "root/root" { exit 1 }'; then
  ok "each tar entry has the owner root/root"; else bad "a tar entry has an other owner"; fi

# 2. An index folder, and a kit file that is already in the output folder.
mkdir "$tmp/idx" "$tmp/full"
echo '{"screens":[]}' >"$tmp/idx/corpus.json"
echo '{"facts":[]}' >"$tmp/idx/facts.json"
echo kit >"$tmp/full/agent-signals-kit.tar.gz"
TZ=UTC0 sh "$script" "$ver" "$tmp/full" "$tmp/idx" >/dev/null
for ext in tar.gz zip; do
  names "$tmp/got" "$tmp/full/$name.$ext"
  if cmp -s "$tmp/got" "$tmp/want-index"; then ok "$ext also holds corpus.json and facts.json"; else
    bad "$ext file list with the indexes"; diff "$tmp/want-index" "$tmp/got" | head -10 | sed 's/^/  /'; fi
done
if tar -xzOf "$tmp/full/$name.tar.gz" "$name/corpus.json" | cmp -s - "$tmp/idx/corpus.json"; then
  ok "corpus.json has the bytes of the index file"; else bad "corpus.json differs"; fi
sed 's/^[0-9a-f]*  //' "$tmp/full/SHA256SUMS" >"$tmp/sums-names"
printf '%s\n' agent-signals-kit.tar.gz "$name.tar.gz" "$name.zip" | LC_ALL=C sort >"$tmp/sums-want"
if cmp -s "$tmp/sums-names" "$tmp/sums-want"; then ok "SHA256SUMS also lists the kit file"; else bad "SHA256SUMS names: $(tr '\n' ' ' <"$tmp/sums-names")"; fi
if (cd "$tmp/full" && sha256sum -c --quiet SHA256SUMS); then ok "SHA256SUMS matches all files"; else bad "SHA256SUMS does not match all files"; fi

# 3. A second build in another time zone gives the same bytes.
TZ=EST5 sh "$script" "$ver" "$tmp/again" "$tmp/idx" >/dev/null
for ext in tar.gz zip; do
  if cmp -s "$tmp/full/$name.$ext" "$tmp/again/$name.$ext"; then ok "two builds of $ext in two time zones give the same bytes"; else bad "two builds of $ext differ"; fi
done

# 4. Bad input.
if sh "$script" "x.y" "$tmp/bad" >/dev/null 2>&1; then bad "a bad version is accepted"; else ok "a bad version is refused"; fi
rm "$tmp/idx/facts.json"
if sh "$script" "$ver" "$tmp/bad" "$tmp/idx" >/dev/null 2>&1; then bad "an index folder with no facts.json is accepted"; else ok "an index folder with no facts.json is refused"; fi

exit "$fail"
