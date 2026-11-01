# 073. agy in the Debian VM of the Android Terminal app

## Measured

2026-11-01, Antigravity CLI (agy) 1.4.12 (one process), in the Debian
13 (trixie) VM of the Android Terminal app, on aarch64. The VM kernel was
`6.12.93-android16-6-g3a7d1771d492-ab16496487-4k`. Claude Code 2.1.316 was
installed, but no Claude process ran. The probe kit (`probes/run.sh`) ran
one time in full and two times as the guided step `permission` for agy.
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
6. In both guided steps, agy started during the step, after the kit.
   The kit counted one agy process before the step, but that process was
   the kit itself: the one-line start ran it as
   `sh -s -- --guided permission agy`, and the agent name matched. The
   kit fix skips the processes that start the kit.
7. A new agy process opened `crashes/crash_<pid>_<uuid>.log` with size 0,
   the new `log/` file and a new presence lock, and held them open. No
   agy crash was seen.
8. In the second step, the start of agy and the first prompt also changed
   `history.jsonl` (one new line), `conversation_summaries.db`,
   `jetbox_summaries_proto.pb`, `annotations/<uuid>.pbtxt`,
   `cache/onboarding.json`, `cache/last_conversations.json`,
   `updater/update_status.json` and `last_check.timestamp`.
9. In each step, the operator asked agy for a file write. In the 30 s
   after that, each new transcript got two records: `USER_INPUT` and
   `PLANNER_RESPONSE`. No record type showed a wait for a permission
   dialog. The changed files also held `conversations/<uuid>.db`, and
   four transcript files in `brain/<uuid>/.system_generated/logs/`:
   `transcript.jsonl`, `transcript_full.jsonl`, and one chunk file of
   each in `chunks/`.

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

- Whether the permission dialog showed in the guided steps. The files do
  not say. So item 9 does not prove that agy writes no record for a
  dialog wait.
- The `status` value in `conversation_summaries.db` during the dialog
  (fact 045). The kit saw only that the file changed.
- A guided step with agy started before the kit.
- Whether `cli.log` is a link to the newest file in `log/` or a copy.
- The `flock` lock on the presence file in this VM (fact 044).
- A Claude Code process in this VM.
