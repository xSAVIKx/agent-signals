# How a tool detects an agent session

The rules that a tool uses to find an agent process, to link it to its
session, and to read its state. Each rule names its source:

- "fact NNN": measured in this repository.
- "aw": reported by the aw tool (v0.40.0, 2026-10-31) for Claude Code
  2.1.309 to 2.1.314, codex-cli 0.163.0 and 0.164.0, agy 1.4.5 and 1.4.7,
  cursor-agent 2026.10.22-27dcf5f and psmux 3.4.0. This repository did not
  measure a rule that has only this source.

## What each OS gives

| OS | Process data | Open files | Source |
|---|---|---|---|
| Linux | `/proc`: name, arguments, tty, folder, environment of own processes | `/proc/<pid>/fd`, `/proc/locks` | fact 025, aw |
| macOS | `ps`, `sysctl`: name, arguments, tty; `ps eww` for the environment of own processes | `lsof -n -P -Fn` | facts 021, 069, aw |
| Windows | CIM `Win32_Process`: name, path, command line, parent. A Toolhelp scan gives the name and the path only | Sysinternals `handle.exe` only | facts 051 to 055, 070, aw |

On macOS, the process name of a native Claude Code install can be its
version, for example `2.1.309` (aw).

## Claude Code

| Step | Rule | Source |
|---|---|---|
| Find | The process name or the program name is `claude` (`claude.exe` on Windows), or the program is `.../claude/versions/<version>`, or the first argument of a node process ends in `claude`. | aw |
| Skip | `claude --chrome-native-host`: no tty, no pid file. | fact 066 |
| Skip | A psmux pane shell whose command line holds a `claude` function. Match the program, not the command line. | fact 070 |
| Link | `~/.claude/sessions/<pid>.json` names the pid. Check that the pid lives and that `procStart` matches, because stale files stay. | facts 023, 066 |
| Link | A `.key` file with no `.json` file: the trust question waits, or the process has just started. | fact 023 |
| Link | On Linux, the open task folder `/tmp/claude-<uid>/<key>/<session id>/tasks`. Not on macOS. | facts 025, 066 |
| Link | Two pid files with one session ID (a resume): the live file with the matching start wins, then the later start, then the later status time. | aw |
| State | `status`: `idle`, `busy`, `waiting` (a dialog), `shell`. `waitingFor` names the kind of wait. | facts 023, 031 |
| State | A dialog on the screen wins over the pid file. | aw |
| Pane | `tmux` in the pid file, only when the process runs in tmux. | facts 023, 066 |

## Codex CLI

| Step | Rule | Source |
|---|---|---|
| Find | The program name is `codex` or `codex-*`. Skip `codex-code-mode-host`. | fact 065, aw |
| Skip | The app-server daemon: `app-server` with `--managed-daemon`, or `app-server daemon`. On Windows, a scan with no arguments can skip it by its path: `~\.codex\packages\app-server-daemon\releases\`. | facts 026, 067 |
| Skip | A direct child of a Codex process is a helper. A first argument that is a subcommand (`exec`, `login`, `app-server`) is not a TUI. | aw |
| Link | A TUI with `--no-daemon` holds its rollout file open. In the default mode the daemon holds it. | facts 026, 039 |
| Link | Folder rules: one Codex process in the folder, one rollout with the same `cwd` in `session_meta`, started after the process. Day folders in local time and in UTC. | aw |
| Home | `CODEX_HOME`, else `~/.codex`, on all three systems. | fact 062 |
| State | The last turn record of the rollout file: `task_complete` = idle, `turn_aborted` = idle, `*_call` = busy. The tool call is written before the approval, so the file never shows a permission wait. | facts 027, 036, aw |
| State | On the screen: "esc to interrupt" = busy; `? for shortcuts` = idle. While Codex 0.164.0 streams an answer, the screen can look idle; an open turn in the rollout file then means busy. | fact 020, aw |

## agy

| Step | Rule | Source |
|---|---|---|
| Find | The program name is `agy`, also while the file is renamed to `agy.exe.<hex>.old`. Skip `-p` and `--print`. | fact 071, aw |
| Link | The open files below `~/.gemini/antigravity-cli/`: one ID in `presence/<id>.lock` and `conversations/<id>.db`. | facts 028, 068 |
| Link | On Linux, the holder of the flock lock of `presence/<id>.lock` in `/proc/locks`. A lock file alone proves nothing: the files stay after a process stops. | facts 044, 072 |
| Link | `cache/last_conversations.json` maps a folder to a conversation. The `cli-<time>.log` that started within 10 s of the process names its conversation. | aw |
| State | Hooks: `PreInvocation`, `PostInvocation`, `Stop`. A deny or Esc gives no hook. | facts 028, 041 |
| State | The log line "Surfacing tool confirmation" = a permission wait. The transcript step `WAITING` = permission. | aw |

## Cursor CLI

| Step | Rule | Source |
|---|---|---|
| Find | The program is `cursor-agent`, or `.../cursor-agent/versions/<version>/...`, or `agent` with `index.js` of that folder. | facts 021, 022, aw |
| Skip | An editor agent worker: `anysphere.cursor-agent-worker` in the path, no tty, `VSCODE_PID` set. A `worker-server` child. `-p` and `--print`. | facts 022, 069, aw |
| Link | The open `~/.cursor/chats/<32 hex>/<chat id>/store.db`. The chat ID is the transcript ID. | fact 021 |
| Link | The project folder name: the folder path with `:` removed and each `\` or `/` changed to `-`, for example `D-Projects-shop`. | fact 072, aw |
| State | On the screen: "Run this command?" with `(y)` … `(esc or n)` = permission; `ctrl+c to stop` or a spinner = busy; the placeholder `Plan, search, build anything` or `Add a follow-up` in the box = idle. | aw |
| State | The transcript ends with `{"type": "turn_ended", "status": "success"}` after a turn. | facts 021, 072 |

## psmux on Windows

| Rule | Source |
|---|---|
| Each pane is a `pwsh.exe` child of `tmux.exe`, with a start script of about 4 KB. | fact 070 |
| A tool finds the sessions from the `<session>.port` file names in the psmux data folder. | aw |
| The process names are `psmux.exe`, `pmux.exe` and `tmux.exe`. | facts 070, aw |

## Open questions

These need a measurement on a real machine. The roadmap tracks them.

1. Codex 0.164 and later: the records during a streamed answer, and the
   time to `task_complete`.
2. Codex: the open files after `/new` and `/resume`; the effect of `-C` on
   the process folder; the parent of `codex-linux-sandbox`.
3. Windows: the link type of the Codex install path
   `~\AppData\Local\Programs\OpenAI\Codex\bin\codex.exe`.
4. Cursor: the chat database after `/new-chat` and `--resume`; a
   `turn_ended` record after an interrupt; the parent of `worker-server`;
   the project folder name for spaces, dots and Unicode.
5. Claude: `status` and `waitingFor` during a plan approval and an
   AskUserQuestion dialog; how long a `.key` file is alone; the pid file
   after a crash.
6. agy: a transcript record for a permission wait; the open files with
   `--continue` and `--conversation <id>`; which presence lock belongs to
   the live process on Windows.
7. macOS: the time of `lsof -p` for one process; the terminal names of
   iTerm2, VS Code and the Cursor editor.
8. Windows: whether a process of the same account can read the command
   line and the folder of another process without administrator rights.
