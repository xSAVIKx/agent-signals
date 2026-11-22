# shellcheck shell=sh
# A full disk in the run folder (Linux only). KIT_TEST_FULL_DISK names an
# empty small file system (for example a tmpfs of 4 MB) that this account
# can write to. The CI job mounts it with sudo. With no KIT_TEST_FULL_DISK,
# the test skips, because a mount needs root.
#
# The test fills the file system, runs a session step with the stub agent
# as a fake claude, and checks the exit code, the reason and that no
# process stays. Then it frees the space and checks that the next step is
# ok.
. "$ROOT/tools/agent-kit-tests/lib.sh"
. "$ROOT/tools/agent-kit-tests/core-lib.sh"
. "$ROOT/tools/agent-kit-tests/steps-lib.sh"

FD=${KIT_TEST_FULL_DISK:-}
if [ -z "$FD" ]; then
  echo "skip: full disk: KIT_TEST_FULL_DISK is not set"
  done_tests
fi
[ -d "$FD" ] && [ -w "$FD" ] || { fail "full disk: the folder" "cannot write in $FD"; done_tests; }
via=
for v in tmux pty; do
  if have "$v"; then via=$v; break; fi
done
if [ -z "$via" ]; then
  echo "skip: full disk: no tmux and no pty backend"
  done_tests
fi
step=permission-claude@$via

# The run folder is out of $T, so the test deletes it, also on a failure,
# and checks for processes that name it.
FO=$FD/kit-test-$$
# shellcheck disable=SC2154
trap '_rc=$?; rm -rf "${FO:?}"; (exit "$_rc"); _cleanup' EXIT
mkdir -m 0700 "$FO" "$FO/out"
D=$FO/out

kitx start --out "$D" >"$T/log" 2>&1
expect_code "full disk: kit start exits 0" 0 $?
run=$(run_of "$D")
case $run in "$FO"/*) pass "full disk: the run folder is on the full file system" ;; *) fail "full disk: the run folder is on the full file system" "$run" ;; esac

# Fill the file system. dd stops with "No space left on device".
dd if=/dev/zero of="$FO/fill" bs=65536 >/dev/null 2>&1
if dd if=/dev/zero of="$FO/fill2" bs=1024 count=1 >/dev/null 2>&1; then
  fail "full disk: the file system is full" "a write works"
fi
rm -f "$FO/fill2"

WATCH=4 kitx step "$step" >"$T/step" 2>&1
rc=$?
expect_code "full disk: the step exits 1" 1 "$rc"
expect_line "full disk: the step names the full disk" "^kit: cannot write 64 KB in the run folder .*: the disk can be full\\. Free space, then run $step again$" "$T/step"
grep -q "the disk can be full" "$T/step" || show "$T/step"
if [ -e "$run/.step.lock" ] || [ -L "$run/.step.lock" ]; then fail "full disk: the lock is gone" "it stays"; else pass "full disk: the lock is gone"; fi

left=$(ps -A -o pid= -o args= | FO_DIR="$FO/" awk -v me="$$" 'index($0, ENVIRON["FO_DIR"]) && $1 != me { print $1 }')
if [ -z "$left" ]; then pass "full disk: no process stays"; else fail "full disk: no process stays" "$left"; fi

# Free the space. The next step must run.
rm -f "$FO/fill"
WATCH=4 kitx step "$step" >"$T/step" 2>&1
expect_code "full disk: the next step exits 0" 0 $?
expect_line "full disk: the next step is ok" "^step: $step ok$" "$T/step"
grep -q "^step: $step ok$" "$T/step" || show "$T/step"
done_tests
