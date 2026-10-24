# 019. The Codex rollout file cannot show an approval wait

## Measured

2026-10-24, Codex CLI 0.163.0, a TUI that ran with `--no-daemon` in a
private tmux server.

## What was measured

Codex writes one rollout file for each session:
`~/.codex/sessions/YYYY/MM/DD/rollout-<time>-<session id>.jsonl`. The first
line is a `session_meta` record. It gives the session ID, the folder (`cwd`),
the originator (`codex-tui` for the TUI, `codex_exec` for a print run) and the
CLI version.

A command that needs an approval gave this order of records:

1. A `custom_tool_call` record for the command. Its `status` is already
   `completed`. Codex writes it before the approval dialog opens.
2. No record while the approval dialog waits.
3. After the approval: `function_call`, `function_call_output`, and at the
   end of the turn `task_complete`.

Thus a tool call with no output and no `task_complete` can mean an approval
wait or a command that still runs. The rollout file cannot tell the two
apart. The screen can: the approval dialog draws "Would you like to run the
following command?" in place of the input box (fact 20).

The rollout file of a TUI session can appear minutes after the session
starts. In one sample, the time in the file name was 5 minutes before the
first record and before the birth time of the file. Thus a reader can find no
rollout file for a session that runs, and the time in the file name is not
the time of the first write.

## Mechanism

Codex records the model output when it arrives. The approval is a state of
the TUI, and the file has no record for it.

## Incident

None recorded.

## Screens

`codex/approval`, `codex/approval-full`.

## Not measured

Which event makes Codex write the rollout file. The order of the records for a file-change approval. Other Codex versions.
A session that runs through the shared app-server daemon, without
`--no-daemon`. The records after a denied approval in the TUI.

## Source

Measured by the ai-world project during its M0 work (the order of the
records) and on 2026-10-24 (the late file). The Codex measurement report of
the tg-bridge project did not examine the order of the records. The text
holds no host details and no session details.
