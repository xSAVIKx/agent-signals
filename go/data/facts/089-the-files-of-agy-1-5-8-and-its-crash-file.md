# 089. The files of agy 1.5.8, and the crash file of each live process

## Measured

2026-11-14 (UTC), Antigravity CLI (agy) 1.5.8, on Linux (Debian 13, x64),
in a private tmux server with a throwaway `HOME` and a copied login. The
scenario `scenarios/agy/continue.sh` started agy four times in the same
`HOME` and work folder: `agy` with no prompt, `agy --continue` with no
conversation, `agy --continue`, and `agy --conversation <id>`. Each start
after the first had one short turn, and each start ended with `/exit`.
After each step, the scenario listed the names, sizes and times of the
files below `~/.gemini`, the open files, the kernel locks, the hooks, the
transcript record types, and the columns of `conversation_summaries.db`.
It read no conversation text. Measured on: real machine.

The scenario is the same as for fact 043 (agy 1.4.7). Two session-archive
projects, agentsview and ai-session-search, say in their code that the
agy file layout changes between versions. This run checks the layout of
the current version.

## What was measured

1. agy keeps each conversation in `conversations/<conversation id>.db`, a
   SQLite file with `-wal` and `-shm` files, as in 1.4.7 (fact 043). The
   folder held no `.pb` conversation file and no `trajectory.json` file.
   The process held a POSIX read lock on the `.db` and the `.db-shm` file.
2. The process held a flock write lock on
   `presence/<conversation id>.lock` while it ran. After `/exit`, the lock
   was free (fact 044). A continued process opened the conversation files
   at the start, before the first prompt (fact 043).
3. Each start made the file `crashes/crash_<pid>_<uuid>.log`, with the pid
   of that agy process and the size 0. The process held it open from the
   start. Each `/exit` deleted it. The four starts made four files, and no
   file stayed.
4. Each turn of a continued conversation wrote one new file
   `brain/<conversation id>/.system_generated/messages/<uuid>.json` (475
   bytes) and made `messages/read.json` larger (45, then 89 bytes). The
   first turn of the new conversation wrote no file in `messages/`. Each
   continued turn also added a `SYSTEM_MESSAGE` record after its
   `USER_INPUT` record in the transcript, as in 1.4.7.
5. The transcript files are the same four files as in 1.4.7 (fact 045):
   `transcript.jsonl`, `transcript_full.jsonl`, and one file in each of
   `chunks/transcript/` and `chunks/transcript_full/`, below
   `brain/<conversation id>/.system_generated/logs/`.
6. Other files and the step that wrote them first:

   | File | Written first |
   |---|---|
   | `implicit/<uuid>.pb` (318 bytes) | the first start |
   | `jetski_state.pbtxt` | the first start |
   | `annotations/<conversation id>.pbtxt` (31 bytes) | the first turn |
   | `cache/last_conversations.json` | the first turn |
   | `jetbox_summaries_proto.pb` | the first turn |
   | `cache/conversation_metadata.json` | the first `--continue` start with a conversation |
   | `log/cli-<yyyyMMdd>_<HHmmss>.log` | each start, one file |

7. `conversation_summaries.db` had nine tables. Fact 045 (1.4.7)
   recorded one table. The tables:
   - `conversation_summaries`, one row for each conversation. Its
     columns include `status`, `not_fully_idle`, `parent_conversation_id`,
     `nesting_depth`, `agent_name` and `group_id`. After the last turn,
     the row had `status` `CASCADE_RUN_STATUS_IDLE` and `not_fully_idle`
     0.
   - `conversation_parents`, with the columns `conversation_id` and
     `parent_id`.
   - `search_schema_version`, with the version 3.
   - `conversations_fts` and its five SQLite FTS tables (`_data`, `_idx`,
     `_content`, `_docsize`, `_config`). The columns of
     `conversations_fts` include `title`, `workspace`, `user_body` and
     `agent_body`. The scenario read only the numbers and the sizes of
     these rows.
8. `SessionStart` fired at the first turn only. Each turn gave
   `PreInvocation`, `PostInvocation` and `Stop`, as in 1.4.7 (fact 043).

## Mechanism

The crash file names the pid of a live agy process, and the process
deletes it at a normal exit. So a reader can find the live agy processes
from a list of `crashes/`, with no `ps` and no `lsof`, and then test each
pid. A file can stay after a crash or a kill: fact 072 and fact 082 saw
files in `crashes/` with no process. The system can also give the pid of
a stale file to another process. So the reader must test that the pid
runs, and that the process is agy: the process holds its crash file open
(item 3), or its command name is agy. The presence lock (fact 044) stays
the test for one conversation.

The files that tell the state are the same as in 1.4.7: the
conversation database, the presence lock and the summaries database. A
reader of 1.4.x works on 1.5.8 for these files.

The column names of `conversations_fts` show a full-text index of the
conversations in the summaries database. A reader that copies
`conversation_summaries.db` to read the `status` (fact 045) can copy
conversation text with it. Such a reader must delete the copy after the
read, and must not send it off the machine.

## Incident

None. This measurement checks the claims of agentsview and
ai-session-search (2026-11-14). Their code says that older agy versions
kept conversations as encrypted `.pb` files. agy 1.4.7 and 1.5.8 keep them
as SQLite files. No version with `.pb` conversations was measured here.

## Screens

None.

## Not measured

- Whether the crash file stays after `kill -9` or a crash of agy 1.5.8.
- The text of the `messages/*.json` files and of the `.pbtxt` and `.pb`
  files.
- Whether `user_body` and `agent_body` hold the text of the turns: the
  scenario read no text.
- macOS and Windows. The file layout of the agy versions between 1.4.12
  and 1.5.8.
- A real home: the run used a throwaway `HOME` with a copied login.
