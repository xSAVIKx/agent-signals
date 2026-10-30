# 027. The Codex rollout file shows an aborted turn

## Measured

2026-10-30, Codex CLI 0.164.0, on Linux (Debian 13, x64), with
`--sandbox read-only --ask-for-approval on-request`, in a private tmux
server with a throwaway `HOME`. The scenario `scenarios/codex/approval.sh`
recorded the record types of the rollout file at each step, with and
without `--no-daemon`. It read no content.
Measured on: real machine.

## What was measured

1. A prompt that asked for a new file opened the dialog "Would you like to
   run the following command?" with "1. Yes, proceed (y)",
   "2. Yes, and don't ask again ...", and "3. No, and tell Codex what to do
   differently (esc)".
2. Esc on the dialog added these records, in this order:
   `response_item` `custom_tool_call_output`, `event_msg` `token_count`,
   `response_item` `message`, `event_msg` `turn_aborted`.
   The screen showed "Conversation interrupted".
3. A turn that ended normally had an `event_msg` `task_complete` record.
4. Both modes (daemon and `--no-daemon`) gave the same records.

## Mechanism

A reader of the rollout file sees the end of a turn in both cases:
`task_complete` after a normal end, `turn_aborted` after Esc. This does not
depend on the Stop hook, which tg-bridge measured does not fire after Esc
or a denial.

## Incident

tg-bridge did not learn that a Codex turn ended after Esc on an approval
dialog, because no Stop hook fired.

## Screens

None.

## Not measured

- "3. No" with a typed answer, and Ctrl+C during a turn.
- An Esc during a running command, with no dialog.
- macOS and Windows.
