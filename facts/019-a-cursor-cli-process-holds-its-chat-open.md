# 019. A Cursor CLI process holds its chat database open

## Measured

2026-10-30, Cursor CLI 2026.10.22-27dcf5f (nine processes) and
2026.10.01-e373342 (one process), on macOS 26.6 (arm64). The probe
`probes/cursor/macos.sh` read the open files with `lsof` and the folder
names with `ls`. It read no conversation text.

## What was measured

1. Each interactive Cursor CLI process keeps one chat database open:

   ```
   ~/.cursor/chats/<32 hex characters>/<chat id>/store.db
   ```

   The `store.db-shm` and `store.db-wal` files of the same chat are open
   too. Each of the ten interactive processes held exactly one chat.
2. The chat ID is the same as the ID of the transcript of that chat:

   ```
   ~/.cursor/projects/<project key>/agent-transcripts/<chat id>/<chat id>.jsonl
   ```

   One chat was checked by its ID in both paths.
3. Four processes in the same folder used the same `<32 hex characters>`
   folder. Processes in other folders used other ones. Thus the hex folder
   depends on the working folder. The hash function is not measured.
4. A file `meta.json` lies beside `store.db`. Its top-level fields are
   `createdAtMs`, `cwd`, `hasConversation`, `schemaVersion`, `title` and
   `updatedAtMs`.
5. A process also keeps `~/.cursor/ai-tracking/ai-code-tracking.db` open.
   One process kept a file `~/.cursor/projects/<project key>/terminals/<number>.txt`
   open.
6. `sqlite3 -readonly` could not open the newest `store.db` while its
   process ran: "unable to open database file".
7. The last records of a transcript can be `assistant` records with
   `tool_use` content, `assistant` records with `text`, and `user` records
   with `text`. A transcript of this version can also hold a record
   `{"type": "turn_ended", "status": "success"}` (seen in the shape report of
   a diagnostic tool, one record).

## Mechanism

A reader can bind a process to its transcript with no terminal screen and
no folder rule: it reads the open files of the process, takes the chat ID
from the `store.db` path, and opens the transcript with the same ID. This
works when several sessions run in the same folder. `meta.json` gives the
folder and the title of the chat.

## Incident

None. Before this fact, a reader bound a Cursor CLI transcript only through
the folder of a tmux pane. On a Mac with no tmux it showed no Cursor session.

## Screens

None.

## Not measured

- Whether the process opens a new `store.db` after `/new-chat` or `--resume`,
  and whether it closes the old one.
- The hash function of the hex folder.
- Linux and Windows.
- The editor's agent workers (fact 20) held no `store.db` open when the
  probe ran.
- Whether the transcript shows a wait on a permission dialog.
