# 073. agy in the Debian VM of the Android Terminal app

## Measured

2026-11-01, Antigravity CLI (agy) 1.4.12 (one process), in the Debian
13 (trixie) VM of the Android Terminal app, on aarch64. The VM kernel was
`6.12.93-android16-6-g3a7d1771d492-ab16496487-4k`. Claude Code 2.1.316 was
installed, but no Claude process ran. The probe kit (`probes/run.sh`) ran
one time in full and one time as the guided step `permission` for agy.
It listed names, sizes, times and record types. It read no content.
Measured on: real machine (an Android telephone).

## What was measured

1. The parent chain of the agy process was `agy` -> `bash` -> `ttyd` ->
   pid 1. `ttyd` had no tty. The terminal variables held only
   `TERM=xterm-256color`. No variable named the Android Terminal app.
2. The command line of the process was only `agy`. The command
   `~/.local/bin/agy` was the program, not a link.
3. agy kept its state in `~/.gemini/antigravity-cli/`, with the same
   names as on Linux (x64), macOS and Windows (fact 072). The process held
   open `conversations/<uuid>.db`, its `-shm` and `-wal` files, and
   `presence/<uuid>.lock`, as in fact 028.
4. The process started at 08:36:54. `log/` got the file
   `cli-20261101_083657.log`, 3 s later. `log/` held one file for each of
   four starts.
5. `cli.log` in the top folder had the same size (24070 bytes) as the
   newest file in `log/`.
6. During the guided step, the agy process opened
   `crashes/crash_<pid>_<uuid>.log`, the new `log/` file and a new
   presence lock. No agy crash was seen.
7. In the guided step, the operator asked agy for a file write. In the
   30 s after that, each new transcript got two records: `USER_INPUT` and
   `PLANNER_RESPONSE`. No record type showed a wait for a permission
   dialog. The changed files were `conversations/<uuid>.db`, the
   presence lock, and four transcript files in
   `brain/<uuid>/.system_generated/logs/`: `transcript.jsonl`,
   `transcript_full.jsonl`, and one chunk file of each in `chunks/`.

## Mechanism

The Android Terminal app shows the shell of the VM through `ttyd`, a
web terminal. So a reader in the VM finds the terminal from the parent
chain (`ttyd`), not from the environment.

agy on aarch64 Linux keeps the same files as on x64 Linux. A reader of
agy state needs no special case for this VM.

## Incident

None.

## Screens

None.

## Not measured

- Whether the permission dialog showed in the guided step. The file does
  not say. So item 7 does not prove that agy writes no record for a
  dialog wait.
- `conversation_summaries.db` during the guided step. The step did not
  watch it then. The kit watches it now (fact 045).
- Whether `cli.log` is a link to the newest file in `log/` or a copy.
- The `flock` lock on the presence file in this VM (fact 044).
- A Claude Code process in this VM.
