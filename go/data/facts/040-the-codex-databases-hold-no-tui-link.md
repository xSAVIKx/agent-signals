# 040. The Codex databases hold no link from a TUI to its thread

## Measured

2026-10-30, Codex CLI 0.164.0 (standalone install,
x86_64-unknown-linux-musl), on Linux (Debian 13, x64), in the default
daemon mode, in a private tmux server with a throwaway `HOME` and a
copied login. The scenario `scenarios/codex/daemon-life.sh` read the
table layout of each `~/.codex/*.sqlite` file while two TUIs ran, with
`sqlite3 -readonly` and only `.tables` and `.schema`. It read no row. It
also read `/proc/<pid>/fd` of each process. Two runs gave the same
layout. The file list of `scenarios/codex/deny.sh` gave the names and
sizes below `~/.codex`.
Measured on: real machine.

## What was measured

1. `~/.codex` holds six SQLite files, each in WAL mode (with `-wal` and
   `-shm` files): `state_5.sqlite`, `logs_2.sqlite`,
   `thread_history_1.sqlite`, `goals_1.sqlite`, `memories_1.sqlite` and
   `queue_1.sqlite`.
2. The tables of `state_5.sqlite`: `threads`, `thread_attachments`,
   `thread_dynamic_tools`, `thread_read_receipts`, `thread_sections`,
   `thread_spawn_edges`, `projects`, `project_roots`,
   `project_idempotency_keys`, `backfill_state`,
   `rollout_migration_state`, `rollout_migration_skipped_rollouts`,
   `external_agent_config_imports`, `guardian_review_feedback`,
   `remote_control_enrollments` and `_sqlx_migrations`.
3. No column of `state_5.sqlite` holds a pid, a tty, a pane or a client of
   the daemon. `threads` has `id`, `rollout_path`, `cwd`, `source`,
   `originator`, `cli_version`, `created_at` and `updated_at`, and more.
   `thread_read_receipts` has `thread_id`, `first_unread_turn`,
   `revision` and `last_published_turn`: one row for each thread, not for
   each client. `remote_control_enrollments` has `app_server_client_name`,
   for remote control.
4. `logs_2.sqlite` has one table `logs` with the columns `thread_id` and
   `process_uuid`, and an index on `process_uuid` for rows with no thread.
   This is the only layout that joins a process to a thread. The
   `process_uuid` is not a pid, and no table maps it to a pid.
5. The other tables: `thread_history_1.sqlite` has `thread_items`,
   `thread_turns`, `thread_realtime_items` and
   `thread_history_projection_state`. `goals_1.sqlite` has `thread_goals`
   and `thread_goal_continuation_deferrals`. `queue_1.sqlite` has
   `queued_items` and `queued_thread_revisions`. `memories_1.sqlite` has
   `jobs`, `stage1_outputs` and `consolidation_progress`.
6. Each daemon-mode TUI holds `state_5`, `logs_2`, `goals_1`, `memories_1`
   and `queue_1` open, but not `thread_history_1`. The daemon and the
   `--no-daemon` TUI hold all six. Thus the open databases of a TUI do not
   name its thread.
7. Codex makes an empty file (0 bytes)
   `~/.codex/tui-thread-reference-capabilities/<session id>` when a
   session starts, before the first prompt. Two daemon-mode TUIs and one
   `--no-daemon` TUI left two such files; a third daemon-mode TUI added
   one more. No process held one open, while a TUI ran or after.

## Mechanism

The daemon keeps the threads. The tables describe threads, not the
clients that show them. A reader that must link a daemon-mode TUI to its
thread finds no pid in these layouts.

## Incident

None recorded. aw asked for an exact link from a Codex TUI to its thread
in daemon mode (fact 26).

## Screens

None.

## Not measured

- The rows. A row of `logs` could hold a `process_uuid` of a TUI, and the
  text of a log line could name a pid. Neither was read.
- The content of the files below `tui-thread-reference-capabilities/`
  other than their size, and which process makes them.
- The app-server protocol on the daemon socket, which could list clients.
- `codex agents`, which browses the sessions of the daemon.
- macOS and Windows.
