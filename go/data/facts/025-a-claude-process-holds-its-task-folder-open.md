# 025. A Claude process holds its task folder open

## Measured

2026-10-30, Claude Code 2.1.310 and 2.1.314, on Linux (Debian 13, x64).
Two live interactive sessions in tmux. `readlink` read each entry of
`/proc/<pid>/fd`.
Measured on: real machine.

## What was measured

1. A Claude process holds no transcript file open.
2. It holds one folder open:
   `/tmp/claude-<uid>/<project key>/<session id>/tasks`. The session ID in
   that path is the `sessionId` of `~/.claude/sessions/<pid>.json`
   (fact 023).
3. Its other descriptors are its tty (8 descriptors), sockets, and
   `anon_inode` entries (`eventpoll`, `eventfd`, `pidfd`).

## Mechanism

A reader that can read the open files of a process, but not the home
folder of its user, can still get the session ID from the task folder.

## Incident

None.

## Screens

None.

## Not measured

- Whether the folder changes after `/clear`.
- Sessions with no background task. Both sessions had run tasks.
- The path on macOS and Windows, where the temporary folder is different.
