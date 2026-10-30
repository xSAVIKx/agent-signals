# Task: add an agent

## Goal

The agent has a row in `docs/roadmap.md`, a probe for each OS, and a
first-run scenario.

## Steps

1. Add a row to `docs/roadmap.md`: the command, the install method, the
   login method for CI, and the state folders. Write `not checked` for each
   value that you did not see yourself.
2. Install the agent in a throwaway `HOME` on a machine where you may
   install software. Start it once, with no login. Record the files that
   it makes.
3. Add the probes. Follow `tasks/add-a-probe.md`.
4. Add `corpus/<agent>/` only when you have a measured screen. Follow
   `docs/format.md`.
5. Add a scenario in `scenarios/<agent>/` when a signal needs an action.
   Follow `scenarios/README.md`. A scenario that needs a model turn says
   so in its header, with its cost.
6. Update the matrix in `docs/roadmap.md`.
7. Commit each part as its own pull request.

## Done when

The roadmap row has no `not checked` value for the command and the state
folders, and the probes workflow passes.
