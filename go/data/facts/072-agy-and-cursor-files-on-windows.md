# 072. The agy and Cursor CLI files on Windows

## Measured

2026-10-31, Antigravity CLI (agy) 1.4.12 (one process) and Cursor CLI
2026.10.22-27dcf5f (no process), on Windows 11 Pro 10.0.26300 (x64). The
probe kit (`probes/run.ps1`) listed the state folders with names, sizes
and times. It read no content.
Measured on: real machine.

## What was measured

1. agy keeps its state in `~\.gemini\antigravity-cli\`, with the same
   names as on Linux and macOS: `conversations\<uuid>.db`,
   `presence\<uuid>.lock`, `brain\<uuid>\`, `log\`,
   `conversation_summaries.db`, `history.jsonl` and `settings.json`.
   No agy folder exists below `%APPDATA%` or `%LOCALAPPDATA%` other than
   the install folder `%LOCALAPPDATA%\agy\bin\`.
2. `presence\` held 10 lock files, while one agy process ran. The lock
   files stay after a process stops. Fact 044 shows that a live process
   holds a flock lock on its file on Linux.
3. `log\` held one file for each start, named
   `cli-<yyyyMMdd>_<HHmmss>.log`. `crashes\` held
   `crash_<pid>_<uuid>.log`, with the pid of the process that ran.
4. The last records of the newest agy transcript had the types
   `PLANNER_RESPONSE` and `GENERIC`.
5. Cursor CLI keeps its state in `~\.cursor\` (`chats\<hex>\<uuid>\`,
   `projects\`, `ai-tracking\`, `cli-config.json`), and its login in
   `%APPDATA%\cursor\auth.json`. The commands are `agent.cmd` and
   `cursor-agent.cmd` in `%LOCALAPPDATA%\cursor-agent\`.
6. On Windows, the name of a Cursor project folder is the project path
   with the drive letter and one dash: `C-Users-<name>-<folder>` or
   `D-<folder>`. Claude Code uses two dashes after the drive letter:
   `D--<folder>`.
7. `~\.cursor\` held four files `statsig-cache.json.<pid>.<uuid>.tmp`,
   left from earlier processes.
8. A closed Cursor chat folder held `meta.json`, `prompt_history.json`
   and `store.db`, with no `-wal` and no `-shm` file. The newest transcript
   ended with a `turn_ended` record.

## Mechanism

A presence lock file of agy does not prove a live process on Windows, as
on Linux. A reader must test the lock or find the process.

A project folder name holds the project path, and on Windows also the
drive letter and the account name. A tool that shows or sends these names
must scrub them. The scrub of this repository missed both Windows forms on
this run; the fix adds them.

## Incident

The kit sent project folder names and the account name in the output of
this run, because the scrub did not know the Windows key forms.

## Screens

None.

## Not measured

- Whether agy holds a lock on its presence file on Windows. The open files
  need Sysinternals `handle.exe`.
- A Cursor CLI process on Windows.
