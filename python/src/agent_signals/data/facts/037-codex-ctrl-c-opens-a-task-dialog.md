# 037. Ctrl+C during a Codex turn opens a task dialog

## Measured

2026-10-30, Codex CLI 0.164.0 (standalone install,
x86_64-unknown-linux-musl), on Linux (Debian 13, x64), in the default
daemon mode, in a private tmux server with a throwaway `HOME` and a
copied login. The scenario `scenarios/codex/interrupt.sh` recorded at
each step the screen, the record types of the rollout file, and whether
the TUI process ran. It read no content.
Measured on: real machine.

The command was `sleep 20`, approved with the digit `1` on the approval
dialog (`--sandbox read-only --ask-for-approval on-request`). On this
machine `bwrap` cannot make a namespace, so a command in the sandbox fails
at once ("bwrap: No permissions to create a new namespace ..."). With
`--ask-for-approval never`, `sleep 20` thus ended in less than 1 s with
status 1. An approved command runs outside the sandbox.

## What was measured

1. Ctrl+C while the command ran did not stop the turn. It opened this
   dialog in place of the input box, with no busy line and no footer
   `? for shortcuts`:

   ```
     Task is still running
     Choose what happens to the current task.


   › 1. Cancel task        Stop the current task and stay in Codex
     2. Run in background  Exit Codex and leave the task running
     3. Exit               Stop the current task and exit Codex

     enter select · esc back
   ```

   The dialog added no record to the rollout file.
2. The answers to the dialog. A digit acted at once, with no Enter.

   | Key | Screen | Records added | TUI |
   |---|---|---|---|
   | `1` (Cancel task) | `• Exited (status 1) sleep 20`, `■ Conversation interrupted - use /feedback if something went wrong`, the empty box | `custom_tool_call_output`, `token_count`, `message`, `turn_aborted` | runs |
   | Esc (back) | the busy line `• Working (7s • esc to interrupt)` is back; the command ends (`• Ran sleep 20`) and the turn ends normally | at the end: `task_complete` | runs |
   | `3` (Exit) | no pane: the TUI exited | `custom_tool_call_output`, `token_count`, `message`, `turn_aborted` | exited |

3. Esc while the command ran (no dialog) gave the same screen and the same
   four records as `1. Cancel task`, then one `event_msg` `item_completed`
   within 6 s. The TUI kept running.
4. In an earlier run of the scenario, Ctrl+C came while the model wrote a
   long answer with no tool. The same dialog opened. The turn went on
   behind the dialog: the rollout file got `task_complete` and the `Stop`
   hook fired, and the dialog stayed open. Then the digit `2` of a typed
   prompt ("sleep 20") answered the dialog with `2. Run in background`,
   and the TUI exited.
5. Two Ctrl+C, 1 s apart, on an idle box exited the TUI in
   `scenarios/codex/deny.sh` and in the second run of
   `scenarios/codex/daemon-life.sh`. In the first run of
   `daemon-life.sh`, the same keys left two of three TUIs running.

## Mechanism

Each interrupt that stops the turn writes `turn_aborted`: Esc during a
command, `1. Cancel task`, `3. Exit`, and the denial of fact 36. A reader
of the rollout file sees the end of the turn in each case.

A reader of the screen must know the dialog of item 1. It hides the busy
line and the idle footer. A tool that types a prompt into it can answer it
by mistake, because a digit acts at once (fact 4), and `2` exits the TUI.

## Incident

The first version of the interrupt scenario typed a prompt with the digit
`2` into this dialog. The TUI exited, and the scenario lost its pane.

## Screens

`codex/task-running-v0-164-0`.

## Not measured

- Why two Ctrl+C on an idle box did not exit two of the TUIs in one run.
- What `2. Run in background` leaves running, and which records follow.
- Ctrl+C during a sandboxed command, on a machine where `bwrap` works.
- `--no-daemon`.
- macOS and Windows.
