# shellcheck shell=sh
# The step list (probes/agent/steps.tsv) and "kit plan".
. "$ROOT/tools/agent-kit-tests/lib.sh"
. "$ROOT/tools/agent-kit-tests/core-lib.sh"

steps=$ROOT/probes/agent/steps.tsv

# The shape of each line, and the known values of the columns.
awk -F '\t' '
  /^#/ || NF == 0 { next }
  !h { n = NF; for (i = 1; i <= NF; i++) c[$i] = i; h = 1; next }
  function words(v, re,    a, k, i) {
    k = split(v, a, ",")
    for (i = 1; i <= k; i++) if (a[i] !~ re) return 0
    return 1
  }
  {
    if (NF != n) { print $1 ": " NF " fields, want " n; next }
    for (i = 1; i <= NF; i++) if ($i == "") print $1 ": field " i " is empty"
    if (seen[$1]++) print $1 ": two lines"
    if ($c["kind"] !~ /^(probe|terminals|first-run|permission|new-chat|resume|interrupt|real-session)$/) print $1 ": kind " $c["kind"]
    if ($c["needs"] !~ /^(none|operator|login|screen)$/) print $1 ": needs " $c["needs"]
    if ($c["cost"] !~ /^(none|turns:[0-9]+)$/) print $1 ": cost " $c["cost"]
    if (!words($c["backends"], "^(none|tmux|pty|conpty|psmux|operator)$")) print $1 ": backends " $c["backends"]
    if (!words($c["os"], "^(linux|macos|windows)$")) print $1 ": os " $c["os"]
    if ($c["agent"] !~ /^(-|claude|codex|agy|cursor)$/) print $1 ": agent " $c["agent"]
    want = $c["kind"] ($c["agent"] == "-" ? "" : "-" $c["agent"])
    if ($1 != want) print $1 ": the name is not " want
  }
  END { if (n != 15) print "the header has " n " columns, want 15" }' "$steps" >"$T/shape"
if [ -s "$T/shape" ]; then fail "each line of steps.tsv has a known shape" "$(head -n 3 "$T/shape" | tr '\n' ';')"; else pass "each line of steps.tsv has a known shape"; fi

for k in probe terminals first-run permission new-chat resume interrupt real-session; do
  for a in claude codex agy cursor; do
    case $k in probe | terminals) n=$k ;; *) n=$k-$a ;; esac
    grep -q "^$n	" "$steps" || echo "$n" >>"$T/missing"
  done
done
if [ -f "$T/missing" ]; then fail "steps.tsv has each step kind for each agent" "$(sort -u "$T/missing" | tr '\n' ' ')"; else pass "steps.tsv has each step kind for each agent"; fi

# field NAME COLUMN: a value of steps.tsv.
field() {
  awk -F '\t' -v n="$1" -v c="$2" '/^#/ { next } !h { for (i = 1; i <= NF; i++) col[$i] = i; h = 1; next } $1 == n { print $col[c] }' "$steps"
}

# The regexes match the screens of the corpus: the dialog regex each
# permission screen and no idle screen, the idle regex each idle screen,
# the busy regex each busy screen.
for a in claude codex agy; do
  re=$(field "permission-$a" wait_regex)
  idle=$(field "permission-$a" idle_regex)
  busy=$(field "interrupt-$a" wait_regex)
  n=0
  for s in "$ROOT"/corpus/$a/screens/*permission*.screen "$ROOT"/corpus/$a/screens/approval*.screen; do
    [ -f "$s" ] || continue
    n=$((n + 1))
    grep -Eq -- "$re" "$s" || fail "the dialog regex of $a matches $(basename "$s")" "no match"
  done
  [ "$n" -gt 0 ] && pass "the dialog regex of $a matches its $n dialog screens"
  for s in "$ROOT"/corpus/$a/screens/idle*.screen; do
    [ -f "$s" ] || continue
    if grep -Eq -- "$re" "$s"; then fail "the dialog regex of $a does not match $(basename "$s")" "a match"; fi
    grep -Eq -- "$idle" "$s" || fail "the idle regex of $a matches $(basename "$s")" "no match"
  done
  pass "the idle screens of $a match the idle regex, not the dialog regex"
  for s in "$ROOT"/corpus/$a/screens/busy*.screen; do
    [ -f "$s" ] || continue
    grep -Eq -- "$busy" "$s" || fail "the busy regex of $a matches $(basename "$s")" "no match"
  done
  pass "the busy screens of $a match the busy regex"
done

# A kit copy with fake step scripts for the kinds that later tasks add, a
# PATH with a fake claude, a fake agy and a fake tmux, and no other agent.
kit_copy "$T/k"
fake_step "$T/k" permission
fake_step "$T/k" first-run
mkdir "$T/bin"
cp "$FAKE/bin/claude" "$FAKE/bin/agy" "$FAKE/tools/tmux" "$T/bin/"
P=$T/bin:$SYS_PATH
os=$(uname -s)

(cd "$T" && PATH=$P AGENT_SIGNALS_RUN='' kitc "$T/k" plan --home real) >"$T/plan" 2>&1
expect_code "kit plan exits 0" 0 $?
expect_line "the plan has the probe" '^step: probe@none needs=none cost=none measures=' "$T/plan"
expect_line "the plan has permission-claude on tmux" '^step: permission-claude@tmux needs=login cost=turns:1 measures=' "$T/plan"
expect_line "the plan has permission-agy" '^step: permission-agy@' "$T/plan"
expect_line "the plan has first-run-claude on tmux" '^step: first-run-claude@tmux ' "$T/plan"
if PATH=$SYS_PATH command -v codex >/dev/null 2>&1; then
  pass "the plan has no codex line (skipped: codex is in $SYS_PATH)"
else
  expect_no_line "the plan has no codex line" '-codex@' "$T/plan"
fi
expect_no_line "the plan has no step with no script" '^step: (new-chat|resume|interrupt|real-session)-' "$T/plan"
expect_no_line "the plan has no Windows backend" '@(conpty|psmux) ' "$T/plan"
if [ "$os" = Darwin ]; then
  : # terminals.sh exists and macOS is in its list.
  expect_line "the plan has the terminal probe on macOS" '^step: terminals@none needs=screen ' "$T/plan"
else
  expect_no_line "the plan has no terminal probe on Linux" '^step: terminals@' "$T/plan"
fi
expect_no_line "a real home gives no skip" 'skip=' "$T/plan"

(cd "$T" && PATH=$P AGENT_SIGNALS_RUN='' kitc "$T/k" plan --home throwaway) >"$T/plan2" 2>&1
expect_code "kit plan --home throwaway exits 0" 0 $?
if grep 'needs=login' "$T/plan2" | grep -vq ' skip=no-login '; then
  fail "each login step skips in a throwaway home" "a line has no skip=no-login"
else
  pass "each login step skips in a throwaway home"
fi
expect_line "a login step is still in the plan" '^step: permission-claude@tmux needs=login cost=turns:1 skip=no-login measures=' "$T/plan2"
expect_line "a step with no login does not skip" '^step: probe@none needs=none cost=none measures=' "$T/plan2"

(cd "$T" && PATH=$P kitc "$T/k" plan --home other) >"$T/out" 2>&1
expect_code "a bad home mode is bad use" 2 $?

# With no tmux, the tmux lines go.
rm "$T/bin/tmux"
(cd "$T" && PATH=$P AGENT_SIGNALS_RUN='' kitc "$T/k" plan) >"$T/plan3" 2>&1
if PATH=$SYS_PATH command -v tmux >/dev/null 2>&1; then
  pass "with no tmux, no tmux step (skipped: tmux is in $SYS_PATH)"
else
  expect_no_line "with no tmux, no tmux step" '@tmux ' "$T/plan3"
fi

done_tests
