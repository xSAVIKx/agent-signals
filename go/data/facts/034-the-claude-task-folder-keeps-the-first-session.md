# 034. The Claude task folder keeps the first session ID of the process

## Measured

2026-10-30, Claude Code 2.1.314 with `--model haiku`, on Linux (Debian 13,
x64), in a private tmux server with a throwaway `HOME`. The scenario
`scenarios/claude/dialog-states.sh` (three runs) listed the open files of
the process at each step from `/proc/<pid>/fd`, and listed the folders
and files below `/tmp/claude-<uid>/<project key>/`.
Measured on: real machine.

## What was measured

1. After the start, and after a question from the agent, the process held
   no folder below `/tmp/claude-<uid>/` open. Only
   `/tmp/claude-<uid>/<project key>/<session id>/scratchpad` existed.
2. The first Bash tool call made
   `/tmp/claude-<uid>/<project key>/<session id>/tasks`, and the process
   then held it open. In run 2 and run 3 that call was a foreground `ls`,
   not a background task. So a Bash call opens the folder, not only a
   background task.
3. A background task wrote its output to `tasks/<task id>.output`. The
   task ID is the `backgroundTaskId` of the hooks (fact 031).
4. After `/clear`, the pid file and the hooks named the new session ID
   (fact 023, fact 024). The process still held the `tasks` folder of the
   first session ID open. The new session got only a `scratchpad` folder.
5. A background task that started after `/clear` wrote its output to the
   `tasks` folder of the first session ID, not to a folder of the new
   session ID.
6. The folders stay after the process ends. The scenario cleanup deletes
   them.

## Mechanism

The process makes its task folder one time, with the session ID that it
has at that time. `/clear` does not move the folder.

A reader that takes the session ID from the open task folder (fact 025)
gets the first session ID of the process. After `/clear`, that ID is
wrong. It is correct only when the process has had one session. The pid
file (fact 023) gives the current session ID.

## Incident

None.

## Screens

None.

## Not measured

- A session with no Bash call at all after a long time.
- Whether `--resume` in a new process makes a new task folder, or uses
  the folder of the resumed ID.
- `/resume` inside a running process.
- macOS and Windows, where the temporary folder is different.
