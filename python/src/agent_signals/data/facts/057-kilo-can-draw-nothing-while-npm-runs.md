# 057. Kilo Code CLI can draw nothing for 30 s while a child npm runs

## Measured

2026-10-30, Kilo Code CLI 7.8.18 (npm `@kilocode/cli`), the scenario
`scenarios/first-run.sh kilo kilo` in the scenarios workflow (run
41142220844), with a throwaway `HOME`, no login and no key. The scenario
records the screen, the processes and the files below `HOME` at each step.
The step `02-after-20s` came about 30 s after the start on macos-26-intel,
and about 20 s after the start on the other labels. The data comes from the
scrubbed summary in the job logs and from the scrubbed artifact.

Measured on: CI runner macos-26-intel (x64). For comparison: CI runner
ubuntu-24.04 (x64), ubuntu-22.04-arm (arm64), macos-15, macos-26 (arm64)
and macos-15-intel (x64). The screens of ubuntu-22.04, ubuntu-26.04,
ubuntu-24.04-arm and ubuntu-26.04-arm were also compared.

## What was measured

1. On macos-26-intel, the pane was empty at the step `02-after-20s`: 40
   empty lines. On the other nine labels, Kilo Code CLI showed its input box
   at that step.
2. At that step on macos-26-intel, the TUI process `.kilo` had a child
   process `npm list` with no tty (`??`). On the five other labels whose
   processes were read, no `npm list` process was there at that step.
3. On each of the six labels whose files were read, Kilo Code CLI made
   `.npm/_logs/<time>-debug-0.log` and `.npm/_update-notifier-last-checked`
   below `HOME`. The time in the name of the npm log came after the line
   "version:" of the scenario log:

   | Label | Delay of the npm log |
   |---|---|
   | ubuntu-24.04 | 3 s |
   | ubuntu-22.04-arm | 4 s |
   | macos-26 | 5 s |
   | macos-15 | 7 s |
   | macos-15-intel | 8 s |
   | macos-26-intel | 19 s |

4. On macos-26-intel, the TUI already held `.local/share/kilo/kilo.db` (with
   `-wal` and `-shm`) and two logs in `.local/share/kilo/log/` open, as on
   the other labels.

## Mechanism

Kilo Code CLI starts npm on each first start. On the slowest runner, the npm
child still ran when the other labels had drawn the box, and the pane stayed
empty. This suggests that the TUI waits for npm before it draws. The source
of Kilo Code CLI was not read, and one run does not prove the cause.

A tool must not read an empty pane of a new agent process as a dead or idle
agent. The state is `NO_BOX`: the agent has not drawn its box yet.

## Incident

None.

## Screens

- `kilo/idle-v7-8-18` (ubuntu-24.04, the input box)
- `kilo/blank-v7-8-18` (macos-26-intel, the empty pane)

## Not measured

- Whether the empty pane comes again on macos-26-intel in another run. Fact
  46 gives the input box for all labels in two earlier runs.
- How long the pane stays empty, and the first screen after npm ends.
- What `npm list` reads, and whether opencode does the same.
- Windows.
