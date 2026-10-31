# 045. The agy summaries database shows a running turn

## Measured

2026-10-30, Antigravity CLI (agy) 1.4.7, on Linux (Debian 13, x64), in a
private tmux server with a throwaway `HOME` and a copied login. The
scenario `scenarios/agy/deny-and-tools.sh` ran two times, with four turns
in each run. A poller listed every 0.5 s the size and the modification
time of each file below `~/.gemini/antigravity-cli/`. In the second run,
each time `conversation_summaries.db` changed, the poller copied it (with
its `-wal` and `-shm` files) and read `status`, `not_fully_idle` and
`step_count` from the copy. It read no conversation text.
Measured on: real machine.

## What was measured

1. `~/.gemini/antigravity-cli/conversation_summaries.db` is a SQLite file
   with one table, `conversation_summaries`, and one row for each
   conversation. Its columns include `conversation_id`, `status`,
   `not_fully_idle`, `step_count`, `killed`, `last_modified_time` and
   `last_user_input_time`.
2. The `status` of the row in the second run:

   | Time (s) | Event | `status`, `not_fully_idle` |
   |---|---|---|
   | 0.3 | turn 1 sent | |
   | 2.2 | | `CASCADE_RUN_STATUS_RUNNING`, 1 |
   | 5.8 | the file dialog opens | |
   | 8.2 | the dialog waits | `CASCADE_RUN_STATUS_RUNNING`, 1 |
   | about 10.0 | `2` (deny) sent | |
   | 10.8 | | `CASCADE_RUN_STATUS_IDLE`, 0 |
   | 28.3 | `Stop` of turn 2 | |
   | 28.8 | | `CASCADE_RUN_STATUS_IDLE`, 0 |
   | 64.7 | `Stop` of turn 3 | |
   | 65.0 | | `CASCADE_RUN_STATUS_IDLE`, 0 |
   | about 81.0 | Esc on the dialog of turn 4 | |
   | 83.1 | | `CASCADE_RUN_STATUS_IDLE`, 0 |

   Each turn changed the status to `CASCADE_RUN_STATUS_RUNNING` within
   2.2 s of the prompt. The status stayed `RUNNING` while a dialog waited.
   It changed to `CASCADE_RUN_STATUS_IDLE` within 0.5 s of `Stop`, within
   0.8 s of a deny, and within 2.1 s of an Esc. No hook fires for the deny
   and the Esc (fact 41).
3. `~/.gemini/antigravity-cli/jetbox_summaries_proto.pb` changed at the same
   times as `conversation_summaries.db-wal`.
4. The conversation files changed only at the steps of a turn:
   `conversations/<conversation id>.db-wal` and the four transcript files
   below `brain/<conversation id>/.system_generated/logs/`
   (`transcript.jsonl`, `transcript_full.jsonl`, and one file in each of
   `chunks/transcript/` and `chunks/transcript_full/`). In turn 3 of the
   second run, no conversation file changed for 21.6 s while the turn ran.
   A size or a modification time of these files does not show that a turn
   runs.
5. `history.jsonl` changed at each prompt that was sent. `cli.log` and the
   file in `log/` changed during the turns and also at other times.

## Mechanism

agy keeps the run state of each conversation in the summaries database,
apart from the transcript. A reader with no hooks can read the `status` of
the row with its `conversation_id`. `RUNNING` means busy or a dialog. The
screen tells these two apart (fact 18). `IDLE` also shows the end of a deny
and of an Esc, where no hook fires.

A reader must not hold a lock on the live database. The scenario read a
copy. A read-only connection to the live file was not tested.

## Incident

None recorded.

## Screens

`agy/busy-v1-4-7`.

## Not measured

- Other values of `status`, for example for an error or a crash.
  `killed` was 0 in each read.
- The content of `jetbox_summaries_proto.pb`.
- The status in the first run (the poller did not read it then).
- The delay with a poll faster than 0.5 s.
- A read-only connection to the live database.
- macOS and Windows. Other agy versions.
