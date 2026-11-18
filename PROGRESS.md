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

## Next

- `tools/agent-kit-tests/test-steps-disk.sh`: the full disk case. It runs
  only in CI, on `ubuntu-24.04`, on a tmpfs that `sudo mount` makes.

## Blocked

- Nothing.
