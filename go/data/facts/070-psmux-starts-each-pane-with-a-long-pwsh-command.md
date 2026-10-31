# 070. psmux starts each pane with a long pwsh command that defines a claude function

## Measured

2026-10-31, psmux with `tmux 3.4.0` from Chocolatey
(`C:\ProgramData\chocolatey\bin\psmux.exe` and `tmux.exe`), PowerShell
7.6.7, Antigravity CLI (agy) 1.4.12 and Claude Code 2.1.314, on Windows 11
Pro 10.0.26300 (x64). The probe kit (`probes/run.ps1`) read the processes
with CIM (`Win32_Process`): the name, the parent, the start time and the
command line.
Measured on: real machine.

## What was measured

1. Two psmux servers ran, each as `tmux.exe`. Each pane was a `pwsh.exe`
   child of a `tmux.exe`. Six pane shells ran.
2. The command line of each pane shell was about 4 KB:
   `pwsh.exe -NoLogo -NoProfile -NoExit -Command "<script>"`. The script:
   - sets PSReadLine options, and the history file from
     `PSMUX_PSREADLINE_HISTORY`;
   - loads the PowerShell profiles by hand, because of `-NoProfile`;
   - replaces `Set-Location`, `Push-Location` and `Pop-Location`, so that
     the process folder follows the shell folder;
   - defines a function `env` that runs a command with variables, in the
     form of the Unix `env`;
   - when `PSMUX_CLAUDE_TEAMMATE_MODE` is set, defines a function
     `claude` that adds `--teammate-mode $env:PSMUX_CLAUDE_TEAMMATE_MODE`,
     unless the settings of Claude Code already set `teammateMode`.
3. An agy process ran as `tmux.exe` > `pwsh.exe` > `agy.exe`.
4. The Claude probe matched the six pane shells as Claude processes,
   because their command line holds the word `claude`. They had no pid
   file. The two real Claude processes ran as `idea64.exe` > `pwsh.exe` >
   `claude.exe`, in the terminal of IntelliJ IDEA, not in psmux.
5. `psmux ls` and `tmux ls` gave the same session list: one session with
   one window and one pane.

## Mechanism

psmux runs the pane shell with `-NoProfile` and its own start script. The
`claude` function exists only in a psmux pane where the variable is set.
A user who types `claude` there starts `claude.exe` with an extra flag,
so the command line of the agent differs from the command line that the
user typed.

A reader that finds agent processes by a word in the command line also
finds psmux pane shells. It must match the program name, `claude.exe`.

## Incident

The kit printed the six command lines in full, 24 KB in total. The probe
fix matches on the program name and cuts each command line.

## Screens

None.

## Not measured

- A Claude Code process in a psmux pane, and the effect of
  `--teammate-mode`.
- Cursor CLI and Codex CLI in psmux: no TUI of these agents ran.
- The values of the psmux variables.
