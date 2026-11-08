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
    if ($c["needs"] !~ /^(none|operator|login|fixture|screen)$/) print $1 ": needs " $c["needs"]
    if ($c["cost"] !~ /^(none|turns:[0-9]+)$/) print $1 ": cost " $c["cost"]
    if (!words($c["backends"], "^(none|tmux|pty|conpty|psmux|operator)$")) print $1 ": backends " $c["backends"]
    if (!words($c["os"], "^(linux|macos|windows)$")) print $1 ": os " $c["os"]
    if ($c["agent"] !~ /^(-|claude|codex|agy|cursor-agent)$/) print $1 ": agent " $c["agent"]
    want = $c["kind"] ($c["agent"] == "-" ? "" : "-" $c["agent"])
    # A permission step for one mode: write-AGENT-MODE or
    # write-outside-AGENT-MODE.
    mode = $c["kind"] == "permission" && $1 ~ ("^write-(outside-)?" $c["agent"] "-[a-z-]+$")
    if ($1 != want && !mode) print $1 ": the name is not " want
  }
  END { if (n != 18) print "the header has " n " columns, want 18" }' "$steps" >"$T/shape"
if [ -s "$T/shape" ]; then fail "each line of steps.tsv has a known shape" "$(head -n 3 "$T/shape" | tr '\n' ';')"; else pass "each line of steps.tsv has a known shape"; fi

for k in probe terminals first-run permission new-chat resume interrupt real-session; do
  for a in claude codex agy cursor-agent; do
    case $k in probe | terminals) n=$k ;; *) n=$k-$a ;; esac
    grep -q "^$n	" "$steps" || echo "$n" >>"$T/missing"
  done
done
if [ -f "$T/missing" ]; then fail "steps.tsv has each step kind for each agent" "$(sort -u "$T/missing" | tr '\n' ' ')"; else pass "steps.tsv has each step kind for each agent"; fi

# field NAME COLUMN: a value of steps.tsv.
field() {
  awk -F '\t' -v n="$1" -v c="$2" '/^#/ { next } !h { for (i = 1; i <= NF; i++) col[$i] = i; h = 1; next } $1 == n { print $col[c] }' "$steps"
}

# The regexes agree with the state of each corpus screen (the "state:" of
# its .yaml). A screen is idle when a line matches idle_regex and no line
# matches busy_regex or dialog_regex. An IDLE screen is idle (not a
# "typed" or "paste" screen: the step waits for idle before it types). A
# BUSY, PERMISSION, DIALOG_OVER_BOX or TRUST screen is not idle. A BUSY
# screen matches busy_regex and not dialog_regex. A dialog screen matches
# dialog_regex and not busy_regex. The file write regex of the permission
# step matches each write dialog and no other state.
# has RE FILE: a line of FILE matches RE.
has() { grep -Eq -- "$1" "$2"; }
for a in claude codex agy; do
  idle=$(field "permission-$a" idle_regex)
  busy=$(field "permission-$a" busy_regex)
  dialog=$(field "permission-$a" dialog_regex)
  write=$(field "permission-$a" wait_regex)
  [ "$(field "interrupt-$a" wait_regex)" = "$busy" ] || fail "the interrupt step of $a waits for busy_regex" "another regex"
  n=0
  : >"$T/bad"
  for y in "$ROOT"/corpus/$a/screens/*.yaml; do
    s=${y%.yaml}.screen
    [ -f "$s" ] || continue
    st=$(sed -n 's/^  state: *//p' "$y" | head -n 1)
    b=$(basename "$s" .screen)
    n=$((n + 1))
    i=no
    has "$idle" "$s" && ! has "$busy" "$s" && ! has "$dialog" "$s" && i=yes
    case $st in
      IDLE)
        case $b in typed* | paste*) ;; *) [ "$i" = yes ] || echo "$b ($st) is not idle" >>"$T/bad" ;; esac
        ! has "$write" "$s" || echo "$b ($st) matches the write regex" >>"$T/bad"
        ;;
      BUSY)
        [ "$i" = no ] || echo "$b ($st) is idle" >>"$T/bad"
        has "$busy" "$s" || echo "$b ($st) does not match busy_regex" >>"$T/bad"
        ! has "$dialog" "$s" || echo "$b ($st) matches dialog_regex" >>"$T/bad"
        ! has "$write" "$s" || echo "$b ($st) matches the write regex" >>"$T/bad"
        ;;
      PERMISSION | DIALOG_OVER_BOX | TRUST)
        [ "$i" = no ] || echo "$b ($st) is idle" >>"$T/bad"
        has "$dialog" "$s" || echo "$b ($st) does not match dialog_regex" >>"$T/bad"
        ! has "$busy" "$s" || echo "$b ($st) matches busy_regex" >>"$T/bad"
        ;;
    esac
    case $b in
      *permission* | approval*) has "$write" "$s" || echo "$b does not match the write regex" >>"$T/bad" ;;
    esac
  done
  if [ -s "$T/bad" ]; then
    fail "the regexes of $a agree with its $n corpus screens" "$(tr '\n' ';' <"$T/bad")"
  else
    pass "the regexes of $a agree with its $n corpus screens"
  fi
  # The other idle regexes of the permission rows of $a (the rows of one
  # mode) follow the same idle rule.
  awk -F '\t' -v a="$a" -v r="$idle" '/^#/ { next } !h { for (i = 1; i <= NF; i++) col[$i] = i; h = 1; next }
    $col["kind"] == "permission" && $col["agent"] == a && $col["idle_regex"] != r && !seen[$col["idle_regex"]]++ { print $col["idle_regex"] }' "$steps" >"$T/idles"
  : >"$T/bad"
  while IFS= read -r idle2; do
    for y in "$ROOT"/corpus/$a/screens/*.yaml; do
      s=${y%.yaml}.screen
      [ -f "$s" ] || continue
      b=$(basename "$s" .screen)
      i=no
      has "$idle2" "$s" && ! has "$busy" "$s" && ! has "$dialog" "$s" && i=yes
      case $(sed -n 's/^  state: *//p' "$y" | head -n 1) in
        IDLE) case $b in typed* | paste*) ;; *) [ "$i" = yes ] || echo "$idle2: $b is not idle" >>"$T/bad" ;; esac ;;
        BUSY | PERMISSION | DIALOG_OVER_BOX | TRUST) [ "$i" = no ] || echo "$idle2: $b is idle" >>"$T/bad" ;;
      esac
    done
  done <"$T/idles"
  if [ -s "$T/bad" ]; then
    fail "the mode rows of $a agree with its corpus screens" "$(tr '\n' ';' <"$T/bad")"
  else
    pass "the mode rows of $a agree with its corpus screens"
  fi
  # Each pre pair matches a screen of the agent, and no IDLE, BUSY or
  # PERMISSION screen.
  field "permission-$a" pre | awk '{ n = split($0, p, ";;"); for (i = 1; i <= n; i++) { sub(/=>.*/, "", p[i]); print p[i] } }' >"$T/pre"
  : >"$T/bad"
  while IFS= read -r re; do
    hit=no
    for y in "$ROOT"/corpus/$a/screens/*.yaml; do
      s=${y%.yaml}.screen
      [ -f "$s" ] && has "$re" "$s" || continue
      hit=yes
      case $(sed -n 's/^  state: *//p' "$y" | head -n 1) in
        IDLE | BUSY | PERMISSION) echo "$re matches $(basename "$s")" >>"$T/bad" ;;
      esac
    done
    [ "$hit" = yes ] || echo "$re matches no screen" >>"$T/bad"
  done <"$T/pre"
  if [ -s "$T/bad" ]; then
    fail "the pre answers of $a match only the screens before idle" "$(tr '\n' ';' <"$T/bad")"
  else
    pass "the pre answers of $a match only the screens before idle"
  fi
done

# A kit copy with fake step scripts for the kinds that later tasks add, a
# PATH with a fake claude, a fake agy and a fake tmux, and no other agent.
kit_copy "$T/k"
# The copy has no script for these kinds, so that the plan leaves them out.
for k in new-chat resume interrupt real-session; do rm -f "$T/k/probes/agent/steps/$k.sh"; done
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
grep -v ' needs=fixture ' "$T/plan" >"$T/plan-login"
expect_no_line "a real home gives no skip to a step with no fixture need" 'skip=' "$T/plan-login"

(cd "$T" && PATH=$P AGENT_SIGNALS_RUN='' kitc "$T/k" plan --home throwaway) >"$T/plan2" 2>&1
expect_code "kit plan --home throwaway exits 0" 0 $?
if grep 'needs=login' "$T/plan2" | grep -vq ' skip=no-login '; then
  fail "each login step skips in a throwaway home" "a line has no skip=no-login"
else
  pass "each login step skips in a throwaway home"
fi
expect_line "a login step is still in the plan" '^step: permission-claude@tmux needs=login cost=turns:1 skip=no-login measures=' "$T/plan2"
expect_line "a step with no login does not skip" '^step: probe@none needs=none cost=none measures=' "$T/plan2"
expect_line "a fixture step skips in a throwaway home" '^step: write-outside-claude-auto-deny@tmux needs=fixture cost=turns:1 skip=needs-fixture ' "$T/plan2"
expect_line "a fixture step skips in a real home" '^step: write-outside-claude-auto-deny@tmux needs=fixture cost=turns:1 skip=needs-fixture ' "$T/plan"
(cd "$T" && PATH=$P AGENT_SIGNALS_RUN='' kitc "$T/k" plan --home fixture) >"$T/plan3" 2>&1
expect_line "a fixture step runs in the fixture" '^step: write-outside-claude-auto-deny@tmux needs=fixture cost=none measures=' "$T/plan3"
expect_line "a mode step is in the plan" '^step: write-claude-accept-edits@tmux needs=login cost=none measures=' "$T/plan3"

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
