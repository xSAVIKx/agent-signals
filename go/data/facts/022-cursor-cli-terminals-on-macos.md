# 022. The terminals and the worker processes of the Cursor CLI on macOS

## Measured

2026-10-30, Cursor CLI 2026.10.22-27dcf5f, Cursor editor (version not
recorded), macOS 26.6 (arm64), with no tmux installed.
Measured on: real machine. The probe
`probes/cursor/macos.sh` read `ps` and one AppleScript call to Terminal.

## What was measured

1. An interactive Cursor CLI process runs as
   `~/.local/bin/agent --use-system-ca ~/.local/share/cursor-agent/versions/<version>/index.js`.
   Its parent is the shell of the terminal (`zsh`). It has a tty, for example
   `ttys023`.
2. The parent of that shell is the terminal program:
   - A JetBrains IDE (PyCharm) for nine processes: `pycharm` > `/bin/zsh` >
     `agent`.
   - Terminal.app for one process: `Terminal` > `login` > `-zsh` > `agent`.
3. `osascript -e 'tell application "Terminal" to get tty of every tab of every window'`
   gives the tty of each Terminal tab, for example `/dev/ttys001`. The tty of
   the Terminal process in item 2 was in that list.
4. The Cursor editor runs agent workers as
   `~/Library/Application Support/Cursor/User/globalStorage/anysphere.cursor-agent-worker/agent-cli/.local/bin/cursor-agent`.
   Their parent is process 1, and they have no tty. Each one has a working
   folder. Four ran at the same time.
5. The editor runs an extension host with the title "Agents Window".

## Mechanism

The tty of a process names its terminal tab. Terminal.app can find a tab by
its tty, so a tool can bring that tab to the front. A JetBrains IDE has no
known scripting access to its terminal tabs, so a tool can only bring the
window of the IDE to the front.

The editor's agent workers are not CLI sessions: no person types in them.
A reader of CLI sessions must not show them as sessions.

## Incident

None.

## Screens

None.

## Not measured

- iTerm2, Ghostty, WezTerm, kitty and Warp (not installed).
- Whether a JetBrains IDE can select a terminal tab from a script.
- What the editor's agent workers do, and whether they write transcripts.
- Linux and Windows.
