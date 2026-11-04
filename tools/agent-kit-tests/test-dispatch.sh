# shellcheck shell=sh
# The dispatcher of the agent kit.
. "$ROOT/tools/agent-kit-tests/lib.sh"

kit >"$T/out" 2>&1
expect_code "no command is bad use" 2 $?
expect_line "the help lists the commands" '^commands:$' "$T/out"

kit no-such >"$T/out" 2>&1
expect_code "an unknown command is bad use" 2 $?

kit '../lib' >"$T/out" 2>&1
expect_code "a path is not a command" 2 $?

kit version >"$T/out" 2>&1
expect_code "version exits 0" 0 $?

(cd "$T" && AGENT_SIGNALS_RUN='' sh -c ". '$ROOT/probes/agent/lib.sh'; kit_run_dir") >"$T/out" 2>&1
expect_code "kit_run_dir with no run is bad use" 2 $?

mkdir "$T/run a"
echo "$T/run a" >"$T/.agent-signals-run"
got=$(cd "$T" && sh -c "KIT_DIR=x; . '$ROOT/probes/agent/lib.sh'; kit_run_dir" 2>/dev/null)
if [ "$got" = "$T/run a" ]; then pass "kit_run_dir reads .agent-signals-run"; else fail "kit_run_dir reads .agent-signals-run" "got '$got'"; fi

done_tests
