# 067. The Codex app-server daemon runs with no TUI and updates on its own

## Measured

2026-10-31, Codex CLI 0.164.0 (standalone install), on macOS 26.6.2
(arm64). The probe kit (`probes/run.sh`, probe `codex/unix.sh`) read
`ps`, `lsof` and the names in `~/.codex/`. It read no content.

The same day, the kit ran on Ubuntu 24.04.5 (x64), with the same Codex
CLI version. It also ran on Windows 11 Pro 10.0.26300 (x64), with Codex CLI
0.164.0 installed in `~\AppData\Local\Programs\OpenAI\Codex\bin\`.
Measured on: real machine.

## What was measured

1. No Codex TUI ran. Two daemon processes ran:
   - `~/.codex/packages/app-server-daemon/releases/0.166.0-aarch64-apple-darwin/bin/codex`,
     with parent process 1 and no tty. It started about 23 h before the
     probe.
   - A child of that process, the same program, with
     `--listen unix:// --analytics-default-enabled --managed-daemon`.
2. On Ubuntu, the same two processes ran from
   `releases/0.166.0-x86_64-unknown-linux-musl/`. The parent of the daemon
   was the `systemd` user manager, not process 1. The daemon started 7 days
   before the probe, and its child 2 days before the probe.
   `app-server-daemon/releases/` also held 0.165.0. No TUI ran.
3. On Windows, three processes ran with no TUI:
   `codex.exe app-server --listen unix:// --analytics-default-enabled --managed-daemon`,
   its child `codex-code-mode-host.exe`, and `codex.exe app-server daemon <arg>`.
   Their path was
   `\\?\~\.codex\packages\app-server-daemon\releases\0.166.0-x86_64-pc-windows-msvc\bin\`.
   The daemon listens on `unix://` on Windows too:
   `~\.codex\app-server-control\app-server-control.sock`.
   `~\.codex\app-server-daemon\` held `daemon.pid`, `daemon-updater.pid`,
   their `.lock` files and `.stderr.log` files.
   `~\.codex\packages\app-server-daemon\` held `auto-update-version`
   and `selection-history`.
4. The daemon was version 0.166.0 on all three machines. The command `codex` gave
   `codex-cli 0.164.0`. `~/.codex/packages/` held
   `app-server-daemon/releases/0.164.0-…`, `app-server-daemon/releases/0.166.0-…`
   and `standalone/releases/0.164.0-…`.
5. The daemon held no rollout file and no thread lock open.
6. `~/.codex/` held these names that fact 026 does not list:
   `app-server-control/`, `app-server-daemon/`, `goals_1.sqlite`,
   `memories_1.sqlite`, `queue_1.sqlite`, `thread_history_1.sqlite`,
   `tui-thread-reference-capabilities/` and `.sqlite-maintenance.lock`.
   Ubuntu had the same names.
7. The last records of the newest rollout file had the types
   `event_msg` (`thread_settings_applied`, `task_started`,
   `item_completed`, `token_count`, `task_complete`), `turn_context`,
   `response_item` (`message`) and `token_usage_record`.

## Mechanism

The daemon of fact 026 does not stop when the last TUI stops. It updates
from its own release folder, so its version can be newer than the
version of the `codex` command.

A reader that finds a daemon must not count it as a session. A reader
that reports the Codex version must say whose version it is: the
command, or the daemon that holds the rollout files.

## Incident

None.

## Screens

None.

## Not measured

- When the daemon stops, and what updated it to 0.166.0.
- Whether a TUI of 0.164.0 uses the daemon of 0.166.0.
- The tables of the new SQLite files.
