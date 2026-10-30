# 024. The Claude hooks around a permission dialog

## Measured

2026-10-30, Claude Code 2.1.314 with `--permission-mode default`, on Linux
(Debian 13, x64), in a private tmux server with a throwaway `HOME`. The
scenario `scenarios/claude/permission-dialog.sh` recorded every hook
payload. The prompt asked for a new file in an empty folder.
Measured on: real machine.

## What was measured

1. A new install starts in auto mode. In auto mode the file write ran with
   no dialog. With `--permission-mode default` it opened the dialog
   "Do you want to create note.txt?" with three options: "1. Yes",
   "2. Yes, and switch to accept edits ...", "3. No".
2. The hooks fired in this order:

   | Step | Hooks |
   |---|---|
   | The dialog opens | `PreToolUse`, `PermissionRequest`, `Notification` |
   | Esc on the dialog | none |
   | "1. Yes" on the dialog | `PostToolUse`, `Stop` |

3. The `PermissionRequest` payload has `tool_name`, `tool_input`,
   `permission_suggestions`, `permission_mode`, `session_id`,
   `transcript_path`, `cwd`, `prompt_id` and `effort`. The suggestion was
   `{"type": "setMode", "mode": "acceptEdits", "destination": "session"}`.
   That is option 2. The payload does not hold the question text or the
   option labels.
4. The `Notification` payload has `notification_type: permission_prompt`
   and `message: Claude needs your permission`.
5. After Esc, no `Stop` hook fired. The next hook was the
   `UserPromptSubmit` of the next prompt.
6. `/clear` fired `SessionEnd` with `reason: clear`, and then
   `SessionStart` with `source: clear` and a new `session_id`.

## Mechanism

A reader learns that a dialog is open from `PermissionRequest` or from the
`Notification` of type `permission_prompt`. It can build the buttons from
`tool_name`, `tool_input` and `permission_suggestions`, but the labels and
the number of options come only from the screen.

A reader that waits for `Stop` after a denial waits for ever. The pid file
(fact 023) changes to `idle` after a denial.

## Incident

A tg-bridge parse of the dialog options failed when an option wrapped to
a second line. This fact shows which part of the dialog the hooks give.

## Screens

None.

## Not measured

- A denial with "3. No" instead of Esc.
- A Bash command dialog, and dialogs with more than three options.
- Whether a `PermissionRequest` hook can answer the dialog by its output.
- macOS and Windows.
