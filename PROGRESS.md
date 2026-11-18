# Progress: kit fault tests (plan 2026-11-14, item 2)

## Done

- `tools/agent-kit-tests/test-steps-env.sh`: paths with spaces, a small
  terminal, a missing tool, and a run folder from an older kit.
- Fix: `kit step` scrubs the work folder root also when
  `AGENT_SIGNALS_WORK` puts it out of the run folder.
- Fix: the kit unsets `COLUMNS`. A small terminal cut the `ps` lines, and
  the guided watch found no agent.
- Fix: the step prints the last line of the watch log when the watch
  stops before it starts.
- Fix: `kit step` refuses a run folder from another kit version (exit 2).
- Fix: `kit step` writes 64 KB in the run folder first. On a full disk it
  stops with exit 1 and the reason "the disk can be full". Before the
  fix, it printed "echo: I/O error" and a fail with no reason.
- `tools/agent-kit-tests/test-steps-disk.sh`: the full disk case. CI runs
  it on `ubuntu-24.04` on a tmpfs of 4 MB that `sudo mount` makes. The
  case passed (8 of 8) in a Debian 13 container with a tmpfs of 4 MB. It
  did not run on a GitHub runner yet.

## Next

- Run the full kit suite once.

## Blocked

- Nothing.
