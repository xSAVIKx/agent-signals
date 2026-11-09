# shellcheck shell=sh
# The awake rule of an unattended run (kit_awake in probes/agent/lib.sh).
# On macOS, "kit start --unattended" writes the meta line "awake", and
# "kit step" then runs "caffeinate -i -w PID" while the step runs. Linux
# gets no line and no caffeinate. A stub caffeinate on PATH logs its pid
# and its arguments, and waits for the -w pid.
. "$ROOT/tools/agent-kit-tests/lib.sh"
. "$ROOT/tools/agent-kit-tests/core-lib.sh"

H=$T/home
mkdir -p "$H" "$T/cb" "$T/empty"
cat >"$T/cb/caffeinate" <<EOF
#!/bin/sh
echo "\$\$ \$*" >>"$T/caff.log"
w=
while [ "\$#" -gt 0 ]; do
  [ "\$1" = -w ] && [ "\$#" -ge 2 ] && w=\$2
  shift
done
[ -n "\$w" ] || exit 2
while kill -0 "\$w" 2>/dev/null; do sleep 0.2; done
EOF
chmod +x "$T/cb/caffeinate"
P=$T/cb:$PATH

# kit_awake gives a line for macOS only, and only in an unattended run.
awake() { (. "$ROOT/probes/agent/lib.sh" && PATH=$1 && kit_awake "$2" "$3"); }
v=$(awake "$T/cb" macos yes)
case $v in caffeinate*) pass "kit_awake names caffeinate on macOS" ;; *) fail "kit_awake names caffeinate on macOS" "$v" ;; esac
v=$(awake "$T/empty" macos yes)
case $v in none:*) pass "kit_awake says when caffeinate is missing" ;; *) fail "kit_awake says when caffeinate is missing" "$v" ;; esac
v=$(awake "$T/cb" linux yes)
if [ -z "$v" ]; then pass "kit_awake gives no line on Linux"; else fail "kit_awake gives no line on Linux" "$v"; fi
v=$(awake "$T/cb" macos no)
if [ -z "$v" ]; then pass "kit_awake gives no line with a person"; else fail "kit_awake gives no line with a person" "$v"; fi

# A fake step. It waits for the stub caffeinate (CAFF_WAIT tenths of a
# second at most), and writes whether it runs.
kit_copy "$T/k"
cat >"$T/k/probes/agent/steps/permission.sh" <<EOF
#!/bin/sh
n=0
while [ ! -s "$T/caff.log" ] && [ "\$n" -lt "\$CAFF_WAIT" ]; do sleep 0.1; n=\$((n + 1)); done
p=\$(head -n 1 "$T/caff.log" 2>/dev/null | cut -d' ' -f1)
if [ -n "\$p" ] && kill -0 "\$p" 2>/dev/null; then r=yes; else r=no; fi
echo "caffeinate runs: \$r" >"\$KIT_OUT"
EOF

# step DIR WAIT: run permission-claude@pty in the run of DIR.
step() {
  (cd "$1" && HOME=$H && PATH=$P && CAFF_WAIT=$2 && export HOME PATH CAFF_WAIT && kitc "$T/k" step permission-claude@pty) >"$T/out" 2>&1
}

# test_unattended_run: the stub is on PATH on each system.
mkdir -m 0700 "$T/u"
(cd "$T/u" && HOME=$H && PATH=$P && export HOME PATH && kitc "$T/k" start --unattended --out "$T/u") >/dev/null 2>&1
expect_code "kit start --unattended exits 0" 0 $?
run=$(run_of "$T/u")
if [ "$(uname -s)" = Darwin ]; then
  expect_line "macOS: the manifest says caffeinate" '^meta	awake	caffeinate ' "$run/manifest.tsv"
  step "$T/u" 30
  expect_code "macOS: the step exits 0" 0 $?
  expect_line "macOS: caffeinate runs in the step" '^caffeinate runs: yes$' "$run/01-permission-claude@pty.txt"
else
  expect_no_line "not macOS: the manifest has no awake line" '^meta	awake	' "$run/manifest.tsv"
  step "$T/u" 10
  expect_code "not macOS: the step exits 0" 0 $?
  expect_line "not macOS: no caffeinate in the step" '^caffeinate runs: no$' "$run/01-permission-claude@pty.txt"
  if [ -f "$T/caff.log" ]; then
    fail "not macOS: the kit does not start caffeinate" "$(cat "$T/caff.log")"
  else
    pass "not macOS: the kit does not start caffeinate"
  fi
fi

# test_awake_line: a manifest with the line that kit start writes on macOS,
# on each system. The step starts caffeinate with -i -w and its own pid,
# and stops it by its pid at the end.
rm -f "$T/caff.log"
mkdir -m 0700 "$T/a"
(cd "$T/a" && HOME=$H && export HOME && kitc "$T/k" start --unattended --out "$T/a") >/dev/null 2>&1
run=$(run_of "$T/a")
grep -q '^meta	awake	' "$run/manifest.tsv" ||
  printf 'meta\tawake\tcaffeinate -i -w <pid of kit step>, in each step\n' >>"$run/manifest.tsv"
step "$T/a" 30
expect_code "awake line: the step exits 0" 0 $?
expect_line "awake line: caffeinate runs in the step" '^caffeinate runs: yes$' "$run/01-permission-claude@pty.txt"
n=0
[ -f "$T/caff.log" ] && n=$(wc -l <"$T/caff.log" | tr -d ' ')
if [ "$n" -eq 1 ]; then pass "awake line: one caffeinate for the step"; else fail "awake line: one caffeinate for the step" "$n lines"; fi
expect_line "awake line: caffeinate gets -i -w PID" '^[0-9]+ -i -w [0-9]+$' "$T/caff.log"
p=$(cut -d' ' -f1 "$T/caff.log" | head -n 1)
if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then
  fail "awake line: caffeinate ends with the step" "pid $p runs"
else
  pass "awake line: caffeinate ends with the step"
fi

done_tests
