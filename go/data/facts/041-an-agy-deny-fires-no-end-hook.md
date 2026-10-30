# 041. An agy deny on the file dialog fires no end hook

## Measured

2026-10-30, Antigravity CLI (agy) 1.4.7, on Linux (Debian 13, x64), in a
private tmux server with a throwaway `HOME` and a copied login. The
scenario `scenarios/agy/deny-and-tools.sh` ran two times. It set a hook
for each of the six events in `~/.gemini/config/hooks.json`, and recorded
at each step the screen, the hook payloads, and the type, the keys and the
enum values of each transcript record. It read no conversation text.
Measured on: real machine.

## What was measured

1. The prompt asked for a file write. The file dialog "Allow creation of
   this file?" opened. The scenario sent the digit `2` ("No, deny
   creation"). The file was not written.
2. The hooks of that turn, in both runs:

   | Step | Hooks |
   |---|---|
   | The prompt | `SessionStart` (first prompt only), then `PreInvocation` |
   | Before the dialog draws | `PreToolUse` (fact 42) |
   | `2` on the dialog | none |
   | The next prompt | `PreInvocation` |

   `PostToolUse`, `PostInvocation` and `Stop` did not fire for the denied
   turn. No `Stop` payload with `terminationReason` `USER_CANCELED` or
   any other value came.
3. The screen after the deny shows `⎿  User declined the tool call` and
   `⎿  Interrupted · What should Antigravity CLI do instead?`, then a framed,
   empty box and `? for shortcuts`. The next prompt ran. After that prompt,
   the history keeps only the "User declined the tool call" line.
4. The deny added one record to `transcript.jsonl`, of type `GENERIC`, in
   both runs. The second run also recorded the keys: that record has
   `status` `ERROR` and an `error` key. A tool call that ran added a
   `GENERIC` record with `status` `DONE` and no `error` key.
5. Esc on the same dialog (turn 4 of each run) gave the same hooks as in
   item 2, and added no transcript record. The screen shows
   `⎿  Interrupted · What should Antigravity CLI do instead?`.
6. The tool-call record (`PLANNER_RESPONSE` with a `tool_calls` key) is in
   the transcript before the dialog draws. It is the last record while the
   dialog waits, and after an Esc.
7. Each transcript record has the keys `content` (not in a tool-call
   record), `created_at`, `source`, `status`, `step_index` and `type`.

## Mechanism

agy ends a denied turn and an Esc turn without its normal end path, so it
calls neither `PostInvocation` nor `Stop`. A reader that waits for `Stop`
after a deny waits for ever, as after an Esc (fact 28). The summaries
database shows the end of these turns (fact 45). The screen shows it too.

A reader of the transcript can tell a deny from an Esc: a deny adds a
`GENERIC` record with `status` `ERROR`, and an Esc adds no record.

## Incident

None recorded.

## Screens

`agy/file-permission-v1-4-7`, `agy/after-deny-v1-4-7`,
`agy/after-escape-v1-4-7`.

## Not measured

- The text of the `error` value. The scenario reads no content.
- A deny of a command dialog ("Run this command?").
- "No" with a text from the operator (`tab Amend`).
- macOS and Windows. Other agy versions.
