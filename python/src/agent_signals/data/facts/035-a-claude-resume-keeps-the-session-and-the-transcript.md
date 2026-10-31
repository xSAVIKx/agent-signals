# 035. A Claude resume keeps the session ID and the transcript file

## Measured

2026-10-30, Claude Code 2.1.314 with `--model haiku`, on Linux (Debian 13,
x64), in a private tmux server with a throwaway `HOME`. The scenario
`scenarios/claude/plan-and-resume.sh` ran one session, stopped it with
`/exit`, and started `claude --resume <sessionId>` in a new process. It
listed the files below `~/.claude/sessions/` and `~/.claude/projects/` at
each step, and recorded every hook payload. One run.
Measured on: real machine.

## What was measured

1. After `/exit`, `SessionEnd` fired with `reason: prompt_input_exit`.
   The files `<pid>.json` and `<pid>.<64 hex characters>.key` of the
   first process were gone. The transcript file stayed.
2. The new process had a new pid and wrote a new `<pid>.json` and a new
   `.key` file. Its `sessionId` was the same ID as in the first process.
3. `SessionStart` fired with `source: resume` and the same `session_id`.
   Its `transcript_path` was the same file as in the first process.
4. The new process appended to that transcript file. The file grew at
   the resume and again after the next prompt. No other transcript file
   appeared in the project folder.
5. After the first prompt of the resumed session, the hooks were
   `UserPromptSubmit`, `Stop`, and then `SubagentStop` with an empty
   `agent_type`. The scenario did not start a subagent. The cause of this
   `SubagentStop` is not known.
6. The resumed screen drew the old conversation, and the name of the
   session (`create-note-txt`) in the frame of the input box.

## Mechanism

A session ID names one transcript file for the whole life of the
session, also across processes. A reader that maps a pid to a session
(fact 023) must read the pid file again for each new process. The
session ID can stay the same while the pid changes.

## Incident

None.

## Screens

None.

## Not measured

- `/resume` inside a running process, and `--continue`.
- A resume while the first process still runs.
- A resume after a crash, with a pid file that stayed.
- Whether a resumed process uses the task folder of the resumed ID
  (fact 034). No Bash call ran after the resume.
- macOS and Windows.
