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

# A step script in steps/ sources lib.sh and gets the folders of kit.sh.
mkdir -p "$T/kit/probes/agent/steps"
cp "$ROOT/probes/agent/kit.sh" "$ROOT/probes/agent/lib.sh" "$T/kit/probes/agent/"
cat >"$T/kit/probes/agent/where.sh" <<'X'
sh "$KIT_DIR/steps/s.sh"
X
cat >"$T/kit/probes/agent/steps/s.sh" <<'X'
. "$KIT_DIR/lib.sh"
echo "root=$KIT_ROOT"
X
got=$(sh "$T/kit/probes/agent/kit.sh" where)
if [ "$got" = "root=$T/kit" ]; then pass "a step script gets KIT_ROOT"; else fail "a step script gets KIT_ROOT" "got '$got'"; fi

echo 1.2.3 >"$T/kit/VERSION"
got=$(sh "$T/kit/probes/agent/kit.sh" version)
if [ "$got" = 1.2.3 ]; then pass "version reads VERSION"; else fail "version reads VERSION" "got '$got'"; fi

# The pointer in KIT_ROOT works from another folder.
mkdir "$T/run b" "$T/elsewhere"
echo "$T/run b" >"$T/kit/.agent-signals-run"
got=$(cd "$T/elsewhere" && AGENT_SIGNALS_RUN='' KIT_DIR="$T/kit/probes/agent" sh -c ". '$T/kit/probes/agent/lib.sh'; kit_run_dir")
if [ "$got" = "$T/run b" ]; then pass "kit_run_dir reads the pointer in KIT_ROOT"; else fail "kit_run_dir reads the pointer in KIT_ROOT" "got '$got'"; fi

# A pid is ours only with its start time.
sleep 30 &
p=$!
bg_pid "$p"
lib=". '$ROOT/probes/agent/lib.sh'"
sh -c "$lib; kit_add_pid '$T/run b' $p sleeper"
if sh -c "$lib; kit_pid_ours '$T/run b' $p"; then pass "a recorded pid is ours"; else fail "a recorded pid is ours" "not ours"; fi
printf 'sleeper\tMon Jan  1 00:00:00 2001\n' >"$T/run b/pids/$p"
if sh -c "$lib; kit_pid_ours '$T/run b' $p"; then fail "a reused pid is not ours" "ours"; else pass "a reused pid is not ours"; fi
echo sleeper >"$T/run b/pids/$p"
if sh -c "$lib; kit_pid_ours '$T/run b' $p"; then fail "a pid with no start time is not ours" "ours"; else pass "a pid with no start time is not ours"; fi

done_tests
