# 074. An early digit goes to the box or to the dialog, on 2.1.316 and 2.1.318

## Measured

2026-11-04, Claude Code 2.1.316 (the system install) and 2.1.318 (from
npm, in a scratch folder), with `--model haiku` and
`--permission-mode default`, on Linux (Debian 13, x64), in a private tmux
server with a throwaway `HOME`. The scenario
`scenarios/claude/early-keys.sh digit` ran three times on each version,
at the same time for both versions. The load average was 87 to 160 on 12
CPUs. Measured on: real machine.

The CHANGELOG of 2.1.318 says: "Fixed permission prompts being answered
by keys typed just after sending a message, or before a slow prompt
appeared". This fact measures that change.

## What was measured

Each trial typed `Run the command mkdir dN with your Bash tool. Do not do
anything else.`, checked that the box showed the text, sent Enter, and
then sent `1`. The command opens the four-option Bash dialog of fact 033,
where "1." is "Yes". A trial counts as "answered" when the folder `dN`
was made with no other key. When the dialog stayed, the scenario sent
Esc and read the input box.

1. The `1` followed the Enter after a fixed wait (run 1, three trials for
   each wait). "0 ms" is one `send-keys` command with both keys. "next" is
   two `send-keys` commands with no wait. The measured gap is in brackets.

   | Wait | 2.1.316: answered / dialogs | 2.1.318: answered / dialogs |
   |---|---|---|
   | 0 ms | 0 / 2 | 0 / 2 |
   | next (3 to 26 ms) | 0 / 2 | 0 / 2 |
   | 50 ms (70 to 87 ms) | 0 / 2 | 0 / 2 |
   | 200 ms (212 to 320 ms) | 0 / 2 | 0 / 1 |
   | 500 ms (513 to 541 ms) | 0 / 1 | 0 / 2 |

   In each of these 18 dialogs, the dialog stayed. After Esc, the input
   box held `1`. In these 18 trials, the `PreToolUse` hook fired 1.2 to
   5.0 s after the `UserPromptSubmit` hook, and each `1` went at most
   541 ms after the Enter. So each `1` arrived while the model worked,
   before the tool call. In the other 12
   trials, the model did not call the tool: it saw the earlier denials in
   the same conversation and stopped. In those trials, the box also held
   `1` at the end of the turn.
2. The `1` went at the moment the hook of the tool call wrote its line
   (runs 2 and 3, with `/clear` before each trial):

   | Send point | 2.1.316: answered / trials | 2.1.318: answered / trials |
   |---|---|---|
   | `PreToolUse` hook (1.7 to 5.0 s after Enter) | 7 / 7 | 7 / 7 |
   | `PermissionRequest` hook (2.9 to 5.6 s after Enter) | 4 / 4 | 4 / 4 |

   The command ran in each trial, and the box held no `1` after the turn.
   In 5 of the 7 `PreToolUse` trials on each version, a screen read just
   before the key showed no dialog.
3. Pilot runs, not in the tables. On 2.1.316, one `Enter 1` in one
   `send-keys` command did not send the message: the box held the text,
   and `1` on a second line. In runs 1 to 3 the same keys sent the
   message. In a second pilot on 2.1.316, a `1` at 579 ms after the
   Enter answered the dialog once. The `PreToolUse` hook fired about 3 s
   after the `UserPromptSubmit` hook. That pilot did not start each trial
   from an idle box: one of its five messages did not reach the model.
   The keys that the box held before that trial are not known. On
   2.1.318, in one pilot run, the typed text did not reach the
   box in 4 of 5 trials, and no `UserPromptSubmit` hook fired. Runs 1 to
   3 checked the box before the Enter, and found no lost text.

## Mechanism

A digit that arrives while the model works goes to the input box, on
both versions. It does not answer the dialog that opens later. It stays
in the box, and it goes out as text with the next message, unless a tool
clears it. A digit that arrives near the start of the tool call answers
the dialog, on both versions, also when the screen did not yet show the
dialog. This measurement found no change between 2.1.316 and 2.1.318.

The rule of fact 004 stays: read the state again just before a digit.
Send the digit only when the screen shows the dialog. After a digit that
went to a busy box, clear the box.

## Incident

None.

## Screens

None. The screens of the runs show host paths, so they stay in `out/`.

## Not measured

- The order of the key and the first draw of the dialog. The screen read
  after the key cannot tell "not drawn yet" from "drawn and answered".
- Which change 2.1.318 made. The cases above gave the same result on
  both versions. A dialog that takes longer to appear (a slow hook or a
  slow permission check) was not tried.
- Keys other than `1`, other dialogs, other models, an idle machine,
  macOS and Windows.
