# Progress of task A7: two CI flakes

## Done

- Flake 1 (test-trace-ebpf, "one process left, python3"): cause proved
  and fixed.
  - The uutils `date` 0.10.0 of Ubuntu 26.04 prints a wrong `%3N` when
    the nanoseconds are below 100000000. It removes the leading zero
    first: `date +"%s %3N %N"` printed `1795029775 493 004932429`. In a
    container of `ubuntu:26.04`, 206 of 2000 samples were wrong.
  - `kit_ms` used `date +%s%3N`. So the hang-up time in hangup.tsv was
    up to 0.99 s late. The stop of the pids comes 0.5 s after the
    hang-up. When the error was more than about 0.5 s, the exit of the
    left python3 came before the recorded hang-up time, and the build
    removed it from `processes_left`.
  - Evidence: Probes run 43715447426, job 132815865133 (ubuntu-26.04-arm).
    The hang-up line is `1794747447994` (12:57:27.994 UTC). The runner
    printed `pass: ebpf: exit 0` at 12:57:28.379, 0.385 s later. The
    stop after the hang-up takes at least 0.5 s, so the recorded time
    was late. The true time was 12:57:27.099 (nanoseconds 099...).
  - The case failed 11 times in Probes runs from 2026-11-14 to
    2026-11-15. Each failure was on ubuntu-26.04-arm (9) or ubuntu-26.04
    (2). No failure was on 22.04 or 24.04, which have GNU date.
  - Fix: `kit_ms` reads `date +%s.%N` and cuts the 9 digits to 3. It
    uses python3 when the output is not that form. The same fix is in
    `test-trace-cast.sh` (t0) and `scenarios/claude/early-keys.sh`.
  - Test: `test-trace-states.sh` has 4 new kit_ms cases with a fake
    `date`. In the `ubuntu:26.04` container, 2000 samples of the new
    `kit_ms` were all between two reads of `date +%s%N`.

- Commit f5a1ffd holds the fix. The branch is pushed.
- Local runs (p1-slot, fake tracer, CPU-saturated host):
  - Run A of test-trace-states, test-trace-cast and test-trace-ebpf:
    the kit_ms cases and "one process left, python3" passed. One case
    failed: "keep raw: exit 0" (kit trace exit 1). The output of that
    trace was not kept.
  - Runs B and C of test-trace-ebpf only: run C passed all. In run B,
    the first "kit trace" exited 1, so "ebpf: exit 0" and "one process
    left, python3" failed. The stderr of that trace was not kept.
  - These "kit trace exit 1" failures are a different failure mode from
    the CI flake. In each CI failure, "ebpf: exit 0" passed. I did not
    find their cause. The host was CPU-saturated at that time.

## Next

- CI on a PR shows if the case stays green on ubuntu-26.04 and
  ubuntu-26.04-arm.

## Blocked

- Flake 2 (Windows "end gap" on windows-11-arm): no data.
  - The only failure of the case is Probes run 43737152591, attempt 1,
    job 132882165810 (2026-11-15, commit 0f0ceea). That commit is before
    9e6dd47, which added the print of the step log. So the log has no
    step data.
  - In that job, the end gap step took about 4 s (17:14:07 to
    17:14:11). The other steps took about 20 s. The step exited 1, but
    its output had no `fail clock-gap` line. The step file had no
    `watch: clock gap` line. So the step stopped early, before the end
    of the watch. The log does not show the reason.
  - After 9e6dd47, the case did not fail: 40 windows-11-arm jobs of
    Probes from 2026-11-15T18:00Z to 2026-11-18 ran. 2 failed, both on
    other cases (jobs 132907990788 and 134594928325).
  - Open question: why did the step stop after about 4 s? Wait for a
    failure with the print of 9e6dd47, then read the `  | ` lines.
