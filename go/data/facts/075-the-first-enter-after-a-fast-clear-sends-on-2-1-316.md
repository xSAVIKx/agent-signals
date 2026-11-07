# 075. The first Enter after a fast clear sends on 2.1.316 and 2.1.318

## Measured

2026-11-04 and 2026-11-05 (UTC), Claude Code 2.1.318 (from npm, in a
scratch folder) and 2.1.316 (the system install). As a control, Claude
Code 2.1.309 (from npm, in a scratch folder, with `DISABLE_AUTOUPDATER=1`),
the version of fact 009. All with `--model haiku` and
`--permission-mode default`, on Linux (Debian 13, x64), in a private tmux
server with a throwaway `HOME`. The scenario
`scenarios/claude/early-keys.sh clear` ran once for each row of the
table below. The load average was 87 to 410 on 12 CPUs, and two runs
were often at the same time. Measured on: real machine.

The CHANGELOG of 2.1.316 says: "Fixed prompts containing invisible
characters needing a second Enter to send". This fact measures that
change with the keys of fact 009.

## What was measured

Each trial started a new process. It waited until the box drew, then
waited 0 to 15 s (each value in turn). Then it sent `C-u`, the text
`Reply with the word ok.` 20 ms later, and Enter 0.3 s later. A
`UserPromptSubmit` hook wrote one line and blocked the prompt, so no
prompt reached the model. A trial counts as "sent" when the hook fired
within 20 s. When the first Enter did not send, the scenario read the
box and sent a second Enter.

"Status line" takes the box as drawn when the screen first shows
`? for shortcuts`. "Box line" takes the first frame with a line that
starts with `❯`, which can be earlier. The time from the box to the
`C-u` was 16 ms to 15.1 s in each run.

| Version | Box from | Trials | First Enter sent | Box held the text, second Enter sent | Box showed no text |
|---|---|---|---|---|---|
| 2.1.318 | status line | 48 | 48 | 0 | 0 |
| 2.1.316 | status line | 48 | 48 | 0 | 0 |
| 2.1.318 | box line | 9 | 8 | 0 | 1 |
| 2.1.309 | status line | 37 | 35 | 0 | 2 |
| 2.1.309 | box line | 15 | 12 | 1 | 2 |

1. No screen read showed the text "invisible character", on any
   version.
2. On 2.1.309, one trial (box line, 2 s) kept the text in the box after
   the first Enter. The second Enter sent it. This is the failure of fact
   009, with no notice on the screen.
3. In 5 trials, the box showed only its hint after the first Enter, and
   the hook did not fire: 4 on 2.1.309 and 1 on 2.1.318 (box line, 11 s).
   In 2 of the 2.1.309 trials, the second Enter sent the message, so the
   box held the text but did not show it. In the other 3 trials, the
   second Enter sent nothing, so the text was lost.
4. Trials with no box in 60 s are not in the table: 4 on 2.1.309 (status
   line), 1 on 2.1.309 (box line), and 3 on 2.1.318 (box line). The
   box-line run of 2.1.318 was stopped during its trial 13, because of
   the load. Its 13th trial is not in the table.
5. A pilot on 2.1.318 (three trials, with a 3 s limit for the hook) is
   not in the table. In one of its trials, at 1.1 s after the box, the
   box showed only its hint, and two Enters sent nothing.

## Mechanism

On 2.1.316 and 2.1.318, no box kept the text after the first Enter, in
105 trials. The first Enter sent the message in 104 of them. In the
other trial, the text did not reach the box. This agrees with the
CHANGELOG of 2.1.316.

The control is weak. With the same keys, 2.1.309 needed a second Enter
in 1 of 52 trials. Fact 009 measured 28 of 125 on 2.1.309, at a load of
15 to 47. So this method makes the failure seldom, and 105 trials with
no failure do not prove that the failure is gone. A tool that keeps the
clear gap of fact 009 loses only time. A tool must also not trust a sent
key: read the box, and see the text in it before the Enter.

## Incident

None.

## Screens

None. The screens of the runs show host paths, so they stay in `out/`.

## Not measured

- The keys of fact 009 at the load of fact 009 (15 to 47). This machine
  had a load of 87 to 410.
- Why 2.1.309 showed the failure less often here than in fact 009.
- Text that holds an invisible character on purpose, and slash
  commands. The CHANGELOG says that commands still wait for review.
- A later message of the same process, other models, macOS and
  Windows.
