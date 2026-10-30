# 036. A Codex denial ends the turn

## Measured

2026-10-30, Codex CLI 0.164.0 (standalone install,
x86_64-unknown-linux-musl), on Linux (Debian 13, x64), in the default
daemon mode with `--sandbox read-only --ask-for-approval on-request`, in a
private tmux server with a throwaway `HOME` and a copied login. The
scenario `scenarios/codex/deny.sh` recorded at each step the screen and
the record types of the rollout file (`type` and `payload.type`, as
`record_types` in `scenarios/lib.sh` gives them). It read no content.
One run with all steps, and one earlier run with the denial only.
Measured on: real machine.

## What was measured

1. A prompt that asked for a file write in the read-only folder opened the
   approval dialog "Would you like to run the following command?" with
   `1. Yes, proceed (y)`, `2. Yes, and don't ask again for commands that
   start with ... (p)` and `3. No, and tell Codex what to do differently
   (esc)`. The `custom_tool_call` record of the command was in the file
   before the dialog opened.
2. The digit `3` acted at once, with no Enter. Codex did not ask for a
   text. 3 s later the screen showed the empty box and the footer
   `? for shortcuts`, with these lines above them:

   ```
   ✗ You canceled the request to run printf 'hello' > note3.txt

   • Exited (status 1) printf 'hello' > note3.txt
     └ (no output)

   ■ Conversation interrupted - use /feedback if something went wrong
   ```

3. The digit `3` added these records, in this order:
   `response_item` `custom_tool_call_output`, `event_msg` `token_count`,
   `response_item` `message`, `event_msg` `turn_aborted`. No record came
   in the next 5 s. The turn ended. It did not go on.
4. Esc on the same dialog gave the same four records and the same lines on
   the screen. Thus a reader cannot tell "3. No" from Esc in the rollout
   file or on the screen.
5. The text that the user typed after the denial started a new turn:
   `event_msg` `thread_settings_applied`, `event_msg` `task_started`,
   `turn_context`, and at its end `event_msg` `task_complete`.
6. The digit `1` (`Yes, proceed`) also acted at once. It gave
   `event_msg` `item_completed`, `response_item` `custom_tool_call_output`,
   `event_msg` `token_count`, `event_msg` `item_completed`,
   `response_item` `message`, `token_usage_record`, `event_msg`
   `token_count` and `event_msg` `task_complete`. The file was written.
7. In the first run, the denial came first. On the next write prompt the
   model refused with no dialog ("I can't create the file because this
   session's workspace is read-only."). The scenario thus asks for the
   denial last.

## Mechanism

"3. No, and tell Codex what to do differently" is the Esc action of the
dialog: its label ends with `(esc)`. Both cancel the command and abort the
turn. The "tell Codex" part is the next prompt of the user, which starts a
new turn.

## Incident

None recorded.

## Screens

`codex/approval-v0-164-0`, `codex/after-deny-v0-164-0`.

## Not measured

- The digit `3` followed by Enter, and the key `n`.
- `2. Yes, and don't ask again`.
- The file-change approval dialog.
- `--no-daemon`. Fact 27 found the same records in both modes for Esc.
- macOS and Windows.
