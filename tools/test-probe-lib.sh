#!/bin/sh
# Checks that the helpers of probes/lib.sh do not change the variables of a
# probe. A POSIX shell has no local variables, so a helper that sets "a"
# changes the "a" of the probe that calls it.
# Run: sh tools/test-probe-lib.sh
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=probes/lib.sh
. "$here/probes/lib.sh"

names="a c d f g h l n p q s t v x list"
for _name in $names; do eval "$_name=keep-$_name"; done

header test 1 sh >/dev/null
resolve /bin/sh >/dev/null
ps_line $$ >/dev/null
chain $$ >/dev/null
children $$ >/dev/null
cwd $$ >/dev/null
open_files $$ . >/dev/null
layout "$here/probes" 1 >/dev/null
mtime "$here/probes/lib.sh" >/dev/null
newest "$here"/probes/*.sh >/dev/null
terminal_env $$ >/dev/null
data="$here/tools/testdata/probe-lib"
toml_tables "$data/config.toml" >/dev/null
json_keys "$data/settings.json" >/dev/null

fail=0
_now=
for _name in $names; do
  eval "_now=\$$_name"
  if [ "$_now" != "keep-$_name" ]; then
    echo "fail: a helper changed \$$_name to: $_now"
    fail=1
  fi
done
[ "$fail" = 0 ] && echo "pass: the helpers keep the variables of the probe"

# The helpers must not print the names in a config file. Compare their
# output with the expected files.
check_output() {
  # $1: the name of the check; $2: the expected file; $3: the output.
  if printf '%s\n' "$3" | diff -u "$2" -; then
    echo "pass: $1"
  else
    echo "fail: $1"
    fail=1
  fi
}
check_output "toml_tables hides paths and names" "$data/toml-tables.txt" "$(toml_tables "$data/config.toml")"
if command -v python3 >/dev/null 2>&1; then
  check_output "json_keys hides names" "$data/json-keys.txt" "$(json_keys "$data/settings.json")"
fi
exit "$fail"
