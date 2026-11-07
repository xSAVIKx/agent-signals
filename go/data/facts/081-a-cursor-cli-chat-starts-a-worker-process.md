# 081. A Cursor CLI chat starts a worker process with a socket

## Measured

2026-11-07 (UTC), Cursor CLI 2026.11.05-86047df, on macOS 26.6.2 (arm64),
with a real login. The guided step `permission` of the probe kit watched
for 30 s. The step text asks the operator to request a file write in one
session and to leave the permission dialog open. The kit does not record
what the operator did. The kit recorded the process
list before and after, the open files, the changed files and the record
types of new transcript lines. It read no text. One run.
Measured on: real machine.

## What was measured

1. A new session started during the step. It started two processes on the same tty:
   `~/.local/bin/agent --use-system-ca .../index.js` and, one second
   later, its child `.../versions/<version>/node .../index.js <arg>`.
2. Both processes held `~/.cursor/projects/<project key>/worker.sock`
   open. The parent also held `store.db`, `store.db-shm`, `store.db-wal`
   and `ai-code-tracking.db` open, as in fact 021.
3. In the project folder, the step changed `worker.log`, `repo.json` and
   `mcp-auth.json`, and wrote a new transcript. In the chat folder, it
   changed `meta.json`, `prompt_history.json` and the `store.db` files.
4. The new transcript got seven records in two turns: `user` `text`,
   `assistant` `text` and `tool_use`, `assistant` `text`, then the same
   for the second turn, and one `turn_ended` record. The transcript ended
   with `turn_ended`, so no turn waited when the step ended.
5. The 19 older Cursor processes (2026.10.01 to 2026.11.05) did not
   change in the process list during the step.

## Mechanism

A reader that finds Cursor processes by name finds two processes for one
session. The child is a `node` process with the parent of the session as
its parent. A reader must bind the session to the parent, which holds
`store.db` (fact 021), and skip the child.

This run does not show whether the transcript marks a permission wait.

## Incident

None.

## Screens

None.

## Not measured

- What the worker process does, and what it sends over `worker.sock`.
- Whether the older Cursor versions also start the worker. Their processes
  held no `worker.sock` open in the probe before the step, and fact 021
  does not list it.
- Whether a dialog was on the screen during the step, and whether Cursor
  ran the command with no dialog. The kit does not read the screen of a
  terminal on macOS.
- Linux and Windows.
