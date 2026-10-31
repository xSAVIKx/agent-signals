# 066. The Claude pid files outside tmux: stale files, the version of the process, and no tmux key

## Measured

2026-10-31, Claude Code 2.1.316 installed, seven interactive processes of
2.1.287, 2.1.288, 2.1.295, 2.1.311, 2.1.312 and 2.1.314, on macOS 26.6.2
(arm64). All processes ran in the terminal of a JetBrains IDE (PyCharm),
not in tmux. The probe kit (`probes/run.sh`, probe `claude/unix.sh`)
read `ps`, `lsof`, and the keys of each `~/.claude/sessions/<pid>.json`.
It read no values other than `status`, `kind` and `version`.

The same day, the kit ran on Ubuntu 24.04.5 (x64), with Claude Code
2.1.314 installed. One interactive process of 2.1.292 ran in GNOME
Terminal, not in tmux. One other `claude` process ran.
Measured on: real machine.

## What was measured

1. Each of the seven processes had a `<pid>.json` and a
   `<pid>.<hex>.key` file. `status` was `idle` and `kind` was
   `interactive` in all seven.
2. `version` in the pid file is the version of the running process, not
   the installed version. The installed command gave 2.1.316. The pid
   files gave six older versions. The oldest process started 29 days
   before the probe.
3. The folder `~/.claude/sessions/` held pid files for nine pids. Two of
   them (`.json` and `.key`) had no process with that pid. Their `status`
   was `idle`. Claude does not delete the pid file of a process that
   stopped, at least not in every case.
4. No pid file had the key `tmux`, on macOS and on Ubuntu. Fact 023 saw
   the key, empty or with a pane, in tmux on Linux. Outside tmux, these
   versions do not write it.
5. The pid files had keys that fact 023 does not list: `pidDomain`,
   `peerProtocol`, `peerFeatures`, `nameSince` and `nameSource` in all
   seven, `bridgeSessionId` in three, and `asksForConvertedSkills` in one
   (2.1.314).
6. The processes held no file below `~/.claude/` and no file below
   `/tmp/claude-<uid>/` open (`lsof -Fn`). The folder `/tmp/claude-501/`
   existed with 11 entries. On Ubuntu, the process held
   `/tmp/claude-1000/<project key>/<uuid>/tasks` open, as in fact 025.
7. Five processes ran as `pycharm` > `/bin/zsh` > `claude`. Two ran as
   `pycharm` > `~/.local/bin/claude`, with no shell between them.
8. The last records of the newest transcript had the types `assistant`,
   `user`, `attachment`, `system`, `last-prompt`, `ai-title`, `mode`,
   `permission-mode`, `atis-latch`, `pr-link` and `bridge-session`.
9. On Ubuntu, a second process ran as `~/.local/bin/claude --chrome-native-host`.
   Its parent was `chrome`, it had no tty, its working folder was
   `~/.claude/chrome`, and it had no pid file. It is the native messaging
   host of the Claude browser extension, not a session.
10. On macOS, during a 30 s guided step, a new pid file appeared, with `status`
   `idle`, 6 s after the start of the step. The step did not start that
   process.

## Mechanism

A pid file proves a session only when its process lives. A reader must
check that the pid runs and that its start time is `procStart` of the
file, because the system can give the pid of a stopped process to a new
process.

A reader must not take the pane of a session from the `tmux` key outside
tmux. When the key is absent, the process is not in tmux, or its version
does not write the key.

On macOS, the task folder of fact 025 does not link a process to its
session. The pid file does (fact 023).

A process match on `claude` also finds the browser host. A reader must
skip a process with `--chrome-native-host`, or a process with no tty and
no pid file.

## Incident

None.

## Screens

None.

## Not measured

- Why the two stale pid files stayed: a crash, a kill, or a stop that
  skips the clean-up.
- The values of the new keys.
- Whether a process on macOS holds its task folder open while a turn
  runs. All seven processes were idle.
- Which program started the two processes that have no shell.
