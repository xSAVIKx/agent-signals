# Checks for each OS

How a tool or a probe sees an agent process, its terminal, its open files
and its folder, on each OS. The column "Measured" says where the row was
measured. "Probe" means that a probe uses it and CI runs that probe on a
runner with no agent session.

## Linux

| Question | Command | Measured |
|---|---|---|
| Processes and parents | `ps -axo pid=,ppid=,tty=,args=`; `/proc/<pid>/stat` field 4 | real machine (Debian 13), probe |
| Children | `pgrep -P <pid>` | real machine |
| Working folder | `readlink /proc/<pid>/cwd` | real machine |
| Open files | `readlink /proc/<pid>/fd/*` (no `lsof` needed) | real machine (facts 25, 26, 28) |
| Terminal | `ps -o tty=`; `readlink /proc/<pid>/fd/0` | real machine |
| Environment (own processes) | `/proc/<pid>/environ`, NUL-separated. Print only names from a fixed list: the environment can hold secrets. | real machine |
| ubuntu-slim runner | No `lsof` and no `tmux`. The probes read `/proc`. | CI runner (fact 49) |
| tmux pane of a process | `tmux list-panes -a -F '#{pane_pid} #{pane_id}'`; `TMUX_PANE` in the environment; the `tmux` field of the Claude pid file (fact 23) | real machine |

## macOS

| Question | Command | Measured |
|---|---|---|
| Processes and parents | `ps -axo pid=,ppid=,tty=,args=` | real machine (fact 22), probe |
| Children | `pgrep -P <pid>` | probe |
| Working folder | `lsof -n -P -a -p <pid> -d cwd -Fn` | real machine (aw doctor) |
| Open files | `lsof -n -P -p <pid> -Fn`. 24 agent processes took 0.7 s. | real machine (facts 21, 22; aw doctor) |
| Terminal | `ps -o tty=` | real machine |
| Environment (own processes) | `ps eww -o command= -p <pid>` | probe (no session) |
| Terminal tab of a tty | Terminal: `tell application "Terminal" to get tty of every tab of every window`; iTerm2: `tty of every session of every tab of every window`. The first call can open an Automation dialog. | real machine, Terminal only (fact 22) |
| Bring a tab to the front | Terminal: `set selected of <tab> to true`; iTerm2: `select <tab>`. The kit step `--guided front-tab` tests it. | not measured |
| JetBrains IDE terminal tabs | No known scripting access. `probes/terminals/macos.sh` checks for an AppleScript dictionary. | not measured |
| Ghostty, WezTerm, kitty, Warp | `wezterm cli list`; kitty remote control (`kitten @`). | not measured |
| tmux | Not on the macOS runner images. The scenarios install it with `brew install tmux`. | CI runners (fact 49) |
| `lsof` and `/proc` compared | `lsof -p` lists mapped files (`.node`, `.dylib`) and more; Linux `/proc/<pid>/fd` lists only open descriptors. | CI runners (fact 50) |

## Windows

| Question | Command | Measured |
|---|---|---|
| Processes and parents | `Get-CimInstance Win32_Process` (`ProcessId`, `ParentProcessId`, `CommandLine`) | probe (no session) |
| Working folder | No route without reading the memory of the process. A Claude session shows its folder in its session file. | aw (no route) |
| Open files | psutil `Process.open_files()` lists the log files that an agent holds open (Cursor CLI). Sysinternals `handle.exe -p <pid>` is not part of Windows. | CI runners (fact 54) |
| Terminal driver | A pseudo console (ConPTY) through pywinpty 3.1.2, read with pyte 0.8.2 (`scenarios/conpty.py`). The console host is the `OpenConsole.exe` of the wheel, a child of the driver, not of the agent. | CI runners (fact 51) |
| Home folder of an agent | Most agents read USERPROFILE. Codex CLI ignores USERPROFILE and HOME and writes to the profile of the account. Cursor CLI takes the account name from Windows, not from USERNAME. | CI runners (facts 53, 54) |
| Terminal | A console process has no tty. The parent chain shows the terminal program: `WindowsTerminal`, `OpenConsole`, `conhost`, `Code`, a JetBrains IDE. | probe (no session) |
| Environment of another process | No route without extra tools. | not measured |
| psmux (tmux for Windows) | `psmux ls`, `psmux list-panes -a`. Under PowerShell, `send-keys ... C-m` sends a literal `^M`; `Enter` works. | aw (psmux 3.4.0) |
| Codex CLI keys | Tab sends a message. Enter and C-j add a new line. | aw (Codex 0.164.0) |
| Install folder and version | `Get-Command <cmd> -All` lists an npm agent as `<cmd>.ps1`, `<cmd>.cmd` and `<cmd>`. The version is in `node_modules\<package>\package.json` below the npm prefix (`C:\npm\prefix` on the runners). The file version of an `.exe` is not always the agent version. | CI runners (facts 47, 48) |

## State folders of each agent

The same on Linux and macOS, below the home folder. Windows uses
`%USERPROFILE%` for the same names (not measured).

| Agent | Session link | Live signal | Transcript |
|---|---|---|---|
| Claude Code | `~/.claude/sessions/<pid>.json` (`sessionId`, `tmux`) | `status` in the same file: `idle`, `busy`, `waiting` (with `waitingFor`), `shell` for a background shell (facts 23, 31) | `~/.claude/projects/<key>/<session id>.jsonl` |
| Codex CLI | `~/.codex/thread-writer-locks/<session id>.lock`, open in the daemon (fact 26) | `task_complete`, `turn_aborted` records (fact 27); the `Interrupt` and `Stop` hooks (fact 38) | `~/.codex/sessions/YYYY/MM/DD/rollout-<time>-<session id>.jsonl` |
| agy | `~/.gemini/antigravity-cli/presence/<conversation id>.lock`, a flock lock held by the process (facts 28, 44) | hooks `PreInvocation`, `Stop` (fact 28); `status` in `conversation_summaries.db` (fact 45) | `~/.gemini/antigravity-cli/brain/<conversation id>/.system_generated/logs/transcript.jsonl` |
| Cursor CLI | `~/.cursor/chats/<hex>/<chat id>/store.db`, open in the process (fact 21) | not known | `~/.cursor/projects/<key>/agent-transcripts/<chat id>/<chat id>.jsonl` |
| opencode | not known | not known | not known |
| Copilot CLI | `~/.copilot/session-state/<session id>/inuse.<pid>.hold`, open in the process (fact 30) | not known | not known |
