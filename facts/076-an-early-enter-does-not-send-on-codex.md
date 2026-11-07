# 076. An early Enter does not send on Codex 0.167.0

## Measured

2026-11-07 (UTC), Codex CLI 0.167.0, on Linux (Debian 13, x64), in a private
tmux server with a throwaway `HOME`. The fake model of the kit
(`probes/agent/fake-model.py`) answered on 127.0.0.1, with no login. The
scenario `scenarios/codex/early-prompt.sh` ran two times. Measured on: real
machine.

## What was measured

Each trial started a new process and waited until the screen showed
`Ask Codex to do anything`. Then it waited DELAY seconds, typed
`Create a file now`, waited 0.2 s and sent Enter. A trial counts as "sent"
when the approval dialog showed within 6 s.

| Delay (s) | Run 1: sent of 10 | Run 2: sent of 5 |
|---|---|---|
| 0 | 10 | not run |
| 0.3 | 10 | 0 |
| 0.5 | 0 | 0 |
| 0.8 | 0 | 0 |
| 1 | 0 | 5 |
| 1.5 | 0 | 5 |
| 2 | 10 | 5 |
| 2.5 | not run | 5 |
| 3 | 10 | not run |

In run 2, all 15 trials that did not send kept the text in the box, and the
fake model got no request. Run 1 did not record the state of the box. An
earlier run of the same steps with 6 trials for each delay lost 1 of 6 at
3 s, with no record of the box.

## Mechanism

Not known. The Enter arrives and the text stays in the box, so the Enter does
not submit. The time window was 0.3 to 0.8 s after the idle text in run 2, and
0.5 to 1.5 s in run 1. So the window moves between runs. Within one run and
one delay, all trials gave the same result.

## Screens

No corpus screen pins this fact. The state is the normal box with text.

## Use

A driver cannot trust an Enter sent soon after the idle text. A check that the
text is on the screen does not find this fault, because the text is there.
The idle text shows only when the box is empty. So a screen that shows the
text, with no idle text, no busy line and no dialog, means that the box still
holds the prompt. Send Enter again.

`probes/agent/steps/session-step.sh` waits 2 s, then uses this rule.

## Not measured

- A session with a real login and a real model.
- Other Codex versions, macOS and Windows.
- The cause, and a delay above 3 s.
- Whether a second Enter sends. In one local run of the four Codex steps the
  rule did not fire, because the 2 s wait came first.
