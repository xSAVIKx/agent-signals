# shellcheck shell=sh
# The states of a step on one clock (kit_trace_state in probes/agent/lib.sh).
# With KIT_TRACE set, a session step writes states.tsv, and "kit session
# start" writes sessions.tsv. With KIT_TRACE empty, nothing is written.
. "$ROOT/tools/agent-kit-tests/lib.sh"
. "$ROOT/tools/agent-kit-tests/core-lib.sh"
. "$ROOT/tools/agent-kit-tests/steps-lib.sh"

kitx start --out "$D" >"$T/log" 2>&1
expect_code "kit start exits 0" 0 $?

# in_order FILE STATE...: true when the states are in FILE in this order.
# Other states can be between them.
in_order() {
  _f=$1
  shift
  awk -F '\t' -v want="$*" '
    BEGIN { n = split(want, w, " "); i = 1 }
    i <= n && $2 == w[i] { i++ }
    END { exit (i > n) ? 0 : 1 }' "$_f"
}

via=
for v in tmux pty; do
  have "$v" && { via=$v; break; }
done
if [ -z "$via" ]; then
  echo "skip: no backend tool is installed"
  done_tests
fi

raw=$T/raw
mkdir -m 0700 "$raw"
# kit trace writes t0 first: the terminal recorder reads it.
echo 1700000000000 >"$raw/t0"
stub_set STUB_TRUST=yes
# A subshell: in a POSIX-mode sh (macOS), a variable before a function call stays set.
(KIT_TRACE=$raw; export KIT_TRACE; kitx step "permission-claude@$via") >"$T/step" 2>&1
expect_code "permission: the step exits 0" 0 $?
st=$raw/states.tsv
if [ -s "$st" ]; then pass "permission: states.tsv exists"; else fail "permission: states.tsv exists" "no file"; fi
if in_order "$st" start idle prompt dialog answer stop; then
  pass "permission: the states are in order"
else
  fail "permission: the states are in order" "$(tr '\t' ' ' <"$st" | tr '\n' ',')"
fi
bad=$(grep -Evc '^[0-9]{13}	(start|idle|prompt|busy|dialog|answer|idle-after|stop)$' "$st")
if [ "$bad" = 0 ]; then pass "permission: each line is a 13-digit time and a state"; else fail "permission: each line is a 13-digit time and a state" "$bad bad lines"; fi
if cut -f1 "$st" | awk 'NR > 1 && $1 < p { bad = 1 } { p = $1 } END { exit bad ? 1 : 0 }'; then
  pass "permission: the times do not go down"
else
  fail "permission: the times do not go down" "$(cut -f1 "$st" | tr '\n' ' ')"
fi
ss=$raw/sessions.tsv
n=$(wc -l <"$ss" 2>/dev/null | tr -d ' ')
if [ "$n" = 1 ]; then pass "sessions.tsv has one line"; else fail "sessions.tsv has one line" "lines: $n"; fi
expect_line "sessions.tsv: NAME, HOME, WORK, AGENT_PID and SOCKDIR" "^permission-claude-$via	[^	]+	[^	]+	[0-9]+	/tmp/as\\.[A-Za-z0-9]+$" "$ss"

# The kinds that use the busy state.
rm -f "$st"
stub_set
(KIT_TRACE=$raw; export KIT_TRACE; kitx step "interrupt-claude@$via") >"$T/step" 2>&1
expect_code "interrupt: the step exits 0" 0 $?
if in_order "$st" prompt busy answer; then
  pass "interrupt: prompt, busy, answer"
else
  fail "interrupt: prompt, busy, answer" "$(tr '\t' ' ' <"$st" | tr '\n' ',')"
fi

# No KIT_TRACE: no states.tsv anywhere.
stub_set STUB_TRUST=yes
rm -f "$st" "$ss"
kitx step "permission-claude@$via" >"$T/step" 2>&1
expect_code "no trace: the step exits 0" 0 $?
found=$(find "$T" -name states.tsv -o -name sessions.tsv 2>/dev/null)
if [ -z "$found" ]; then pass "no trace: no states.tsv is made"; else fail "no trace: no states.tsv is made" "$found"; fi

done_tests
