# Task: write a fact from probe or scenario output

## Goal

One file in `facts/` that states one measured finding, how it was
measured, and what was not measured.

## Inputs

- Probe output (from the kit) or scenario output (from `out/`).
- The agent version and the OS of the run.

## Steps

1. Find the next free number: the highest `facts/NNN-*.md` plus one.
2. Make `facts/NNN-<short-slug>.md` with these headings, as in
   `facts/README.md`: `Measured`, `What was measured`, `Mechanism`,
   `Incident`, `Screens`, `Not measured`.
3. Under `Measured`, give the date, the agent version, the OS and CPU
   type, how it was measured (the probe or the scenario), and one line
   `Measured on: real machine`, `Measured on: CI runner <image>`, or
   `Measured on: emulation <image>`.
4. Under `What was measured`, write only what the output shows. Use
   `/work/example` for each path and `dev` for each account name. Do not
   copy conversation text.
5. Under `Not measured`, list what a reader could expect but the run did
   not show: other OSes, other versions, other keys.
6. Add the fact number to the `Facts` column of the probe or scenario in
   its README.
7. Run `sh tools/sync-go-data.sh`, then the checks in `AGENTS.md`.
8. Commit with `feat: add fact NNN ...`. Open a pull request.

## Done when

CI passes, and each sentence of the fact comes from the output.
