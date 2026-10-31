# 032. The Claude question hooks carry the question and the options

## Measured

2026-10-30, Claude Code 2.1.314 with `--model haiku` and
`--permission-mode default` (the question) or `--permission-mode plan`
(the plan), on Linux (Debian 13, x64), in a private tmux server with a
throwaway `HOME`. The scenarios `scenarios/claude/dialog-states.sh` (three
runs) and `scenarios/claude/plan-and-resume.sh` (one run) recorded every
hook payload. The scenarios print only the keys and the shape of
`tool_input`.
Measured on: real machine.

## What was measured

1. The prompt "Ask me with your question tool whether I prefer red or
   blue, then reply with my answer." opened this dialog:

   ```
    ☐ Color
   Do you prefer red or blue?
   ❯ 1. Red
        You prefer red.
     2. Blue
        You prefer blue.
     3. Type something.
   ────────────────────────────
     4. Chat about this
   Enter to select · ↑/↓ to navigate · Esc to cancel
   ```

2. The hooks for the question fired in this order: `PreToolUse`,
   `PermissionRequest`, `Notification` (`notification_type:
   permission_prompt`), and after "1." `PostToolUse`, then `Stop`.
3. `PreToolUse` and `PermissionRequest` have `tool_name: AskUserQuestion`
   and a `tool_input` of this shape:

   ```
   {"questions": [{"question": str, "header": str,
                   "options": [{"label": str, "description": str}, ...],
                   "multiSelect": bool}]}
   ```

   In each run there was one question with two options. `question` was
   the dialog line "Do you prefer red or blue?", `header` was "Color",
   and the labels were "Red" and "Blue", each with its description line.
   `PermissionRequest` has no `permission_suggestions` for this tool.
4. The rows "3. Type something." and "4. Chat about this" are not in
   `tool_input`. Claude Code adds them. Two options in `tool_input` gave
   four numbered rows on the screen.
5. The `PostToolUse` `tool_input` and `tool_response` have the same
   `questions`, and also `answers` and `annotations`. `answers` maps the
   question text to the label of the answer.
6. A single question with a digit answer opened no review screen. The
   digit "1" closed the dialog at once (fact 004).
7. The plan approval. In plan mode the agent wrote the plan file with the
   `Write` tool, and then called `ExitPlanMode`. The hooks were
   `PreToolUse`, `PermissionRequest` and `Notification`
   (`permission_prompt`). The `tool_input` keys were `plan` (the plan
   text) and `planFilePath` (`~/.claude/plans/<name>.md`).
   `PermissionRequest` had no `permission_suggestions`. The dialog was:

   ```
    Claude has written up a plan and is ready to execute. Would you like to proceed?
    ❯ 1. Yes, and use auto mode
      2. Yes, manually approve edits
      3. Tell Claude what to change
         shift+tab to approve with this feedback
   ```

   After "1.", `PostToolUse` had an empty `tool_input` and a
   `tool_response` with `plan`, `isAgent` and `filePath`. The
   `permission_mode` of the next hooks was `auto`.

## Mechanism

A reader can build a structured record of a question from `PreToolUse` or
`PermissionRequest` with no screen parse: the question, the header, the
labels, the descriptions, and `multiSelect`. It must add the two rows that
Claude Code draws: a free-text row and "Chat about this". In the measured
dialog, the digit of option N of `tool_input` was N.

For a plan approval the hooks give the plan text, not the option labels.
The labels come only from the screen.

## Incident

None. tg-bridge asked for a structured record of a dialog with its
options.

## Screens

None.

## Not measured

- A question with `multiSelect: true`, and a wizard of more than one
  question in 2.1.314.
- An answer with "Type something." or "Chat about this", and Esc on the
  question.
- Answers "2." and "3." on the plan approval.
- Other models, macOS and Windows.
