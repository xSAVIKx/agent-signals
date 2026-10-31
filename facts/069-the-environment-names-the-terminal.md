# 069. The environment of an agent process names its terminal

## Measured

2026-10-31, on macOS 26.6.2 (arm64): seven Claude Code processes, 13
Cursor CLI processes (2026.10.22-27dcf5f and 2026.10.01-e373342), four
Cursor editor agent workers, and one agy process. The probe kit
(`probes/run.sh`) read the terminal variables of each process with
`ps eww`. It reads only a fixed list of names (`terminal_env` in
`probes/lib.sh`), because the environment can hold secrets.

The same day, the kit ran on Ubuntu 24.04.5 (x64) with GNOME, with one
Claude Code and one agy process in GNOME Terminal.
Measured on: real machine.

## What was measured

1. A process in the terminal of a JetBrains IDE had
   `TERMINAL_EMULATOR=JetBrains-JediTerm`, `TERM=xterm-256color` and
   `__CFBundleIdentifier=com.jetbrains.pycharm`. The parent chain ended in
   `~/Applications/PyCharm.app/Contents/MacOS/pycharm`.
2. A process in Terminal.app had `TERM_PROGRAM=Apple_Terminal`,
   `TERM_PROGRAM_VERSION=470.2` and `__CFBundleIdentifier=com.apple.Terminal`.
3. A Cursor editor agent worker had no tty and no `TERM`. It had
   `VSCODE_PID=<pid of the editor>` and
   `__CFBundleIdentifier=com.todesktop.230313mzl4w4u92`. The workers held
   no chat database open (compare fact 021).
4. One Cursor CLI process of 2026.10.01-e373342 ran, but
   `~/.local/share/cursor-agent/versions/` held only 2026.10.18,
   2026.10.19 and 2026.10.22. The update deleted the folder of a version
   that a process still ran.
5. The probe found 505 chat folders below `~/.cursor/chats/`.
6. On Ubuntu, a process in GNOME Terminal had only `TERM=xterm-256color`
   from the list. The list then had no GNOME name. The parent chain was
   `systemd` (the user manager) > `gnome-terminal-` > `zsh` > the agent.
   `ps` cuts the name `gnome-terminal-server` to 15 characters.

## Mechanism

On Linux, the parent chain names the terminal. A reader that matches the
name must accept the 15-character form `gnome-terminal-`. The kit now
also reads `VTE_VERSION`, `GNOME_TERMINAL_SCREEN` and `KONSOLE_VERSION`.

`__CFBundleIdentifier` names the application that started the terminal,
and `TERMINAL_EMULATOR` or `TERM_PROGRAM` names the terminal. A reader can
use them when the parent chain is long or when the terminal program has
a helper process between it and the shell.

The bundle ID of the Cursor editor is not a readable name. A reader must
know it, or use `VSCODE_PID` and the absence of a tty, to tell an editor
worker from a CLI session (fact 022).

## Incident

None.

## Screens

None.

## Not measured

- Other JetBrains IDEs. Their bundle IDs follow the form
  `com.jetbrains.<name>` (not checked).
- iTerm2, Ghostty, WezTerm, kitty, Konsole and the terminal of VS Code.
  None ran.
- The values of `VTE_VERSION` and `GNOME_TERMINAL_SCREEN`. The kit did not
  read them on that run.
- Which terminal tab of PyCharm holds which process. A JetBrains IDE has
  no known scripting access to its tabs (fact 022).
