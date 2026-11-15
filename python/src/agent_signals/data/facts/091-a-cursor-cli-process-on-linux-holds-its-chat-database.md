# 091. A Cursor CLI process on Linux holds its chat database open

## Measured

2026-11-07 and 2026-11-08 (UTC), Cursor CLI 2026.11.05-86047df, on Linux
(Ubuntu 24.04.5, x64), with the real home and login of the operator, in
tmux and in a pseudo-terminal. The kit steps `permission`, `new-chat`,
`resume` and `interrupt` of kit 0.16.0 and 0.18.1 ran each session. The
guided watch listed the files that the session processes held open before
and after the step (section 2 of each step file). It reads
`/proc/<pid>/fd`. It read no chat text. The probe of the same runs also
listed one older Cursor CLI process (2026.10.22-27dcf5f) that the
operator had open in a terminal. Measured on: real machine.

This answers request 8 of aw in `docs/roadmap.md` for Linux.

## What was measured

1. A Cursor CLI session has two processes: the parent
   `~/.local/bin/cursor-agent --use-system-ca .../index.js` and its child
   `.../versions/<version>/node .../index.js <arg>` (fact 081).
2. After the first prompt, the parent process held
   `~/.cursor/chats/<hex>/<uuid>/store.db`, `store.db-shm` and
   `store.db-wal` open. Example, from `32-permission-cursor-agent@tmux.txt`
   of the run of 2026-11-08:

   ```
   > cursor-agent 2080846 ~/.cursor/chats/<hex>/<uuid>/store.db
   > cursor-agent 2080846 ~/.cursor/chats/<hex>/<uuid>/store.db-shm
   > cursor-agent 2080846 ~/.cursor/chats/<hex>/<uuid>/store.db-wal
   ```

   The child process held none of these files.
3. Before the first prompt, the session held no chat database.
4. A session that started again with `--continue` (the `resume` step) held
   one chat database.
5. The older process also held `~/.cursor/ai-tracking/ai-code-tracking.db`
   open. In the steps, that file changed during the session.

## Mechanism

The parent process holds the chat database, as on macOS (fact 021). So a
reader on Linux can bind a terminal session to its chat: find the
`cursor-agent` process on the tty, then read the `store.db` path of that
process in `/proc/<pid>/fd`. The child process gives no chat path.

## Incident

None.

## Screens

None.

## Not measured

- The rule of the `<hex>` folder name: the kit scrubs the name, so no
  hash rule can come from these runs (request 7 of aw).
- Windows: the kit needs Sysinternals `handle.exe` for open files, and
  the laptop had none.
- The sockets of the child process: the kit lists only paths.
- How the probe of 2026-11-08 and 2026-11-13 found a child `node ...
  index.js` process whose parent was the user `systemd`, with no parent
  `cursor-agent`. The data does not show how its parent ended.
