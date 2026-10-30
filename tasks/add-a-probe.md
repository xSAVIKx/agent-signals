# Task: add a probe for a new agent or a new OS

## Goal

A read-only script that prints the processes, terminals, open files and
session folders of one agent on Linux and macOS (`unix.sh`) or Windows
(`windows.ps1`).

## Inputs

- The agent command and its state folders. Find the folders with
  `ls -a ~` before and after a first start of the agent in a throwaway
  `HOME`.

## Steps

1. Copy the probe of a similar agent, for example `probes/agy/unix.sh`.
2. Change the header line, the process pattern, and the state folders.
3. Keep the rules of `probes/README.md`: read only, no conversation text,
   numbered sections, `not found` for an empty section, exit 0.
4. Use only the helpers of `probes/lib.sh` or `probes/lib.ps1` to read
   processes and files. A helper hides values that can be private.
5. Run the probe on a machine with no session of the agent. Each section
   must print `not found` or data.
6. Run `sh tools/check-probe-output.sh <probe> <output>`.
7. Add the agent to `pattern_of`, `state_dirs` and `agents` in
   `probes/run.sh` (and the map in `probes/run.ps1`).
8. Add a row to the table in `probes/README.md`.
9. Commit with `feat: add the <agent> probe for <os>`. Open a pull request.
   The probes workflow runs it on all runner types.

## Done when

The probes workflow passes on Linux, macOS and Windows.
