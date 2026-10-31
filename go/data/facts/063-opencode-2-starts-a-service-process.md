# 063. opencode 2 installs as @opencode/cli and starts a service process

## Measured

2026-10-31, opencode 2.2.5 from npm `@opencode/cli`, in the scenarios
workflow (run 41151440753, and before it run 41149533184). On Linux and
macOS the scenario was `scenarios/first-run.sh opencode2 opencode2`, on
Windows `scenarios/first-run-windows.py opencode2 opencode2`, with a
throwaway home, no login and no key. The workflow installs opencode 2 in
group b, where the opencode 1 package `opencode-ai` is not installed.

The install method comes from the README of `anomalyco/opencode`:
`curl -fsSL https://opencode.ai/v2/install | bash` or
`npm i -g @opencode/cli@latest`. The opencode 1 installer
(`https://opencode.ai/install`) refuses a 2.x version and names the v2
installer. The npm package `opencode-ai` has the `latest` tag 1.19.5. The
package `@opencode/cli` has the `latest` tag 2.2.5 and two commands,
`opencode` and `opencode2`, for the same `bin/opencode.exe`. The GitHub
releases of `anomalyco/opencode` hold 2.x archives for Linux, macOS and
Windows (x64 and arm64).

Measured on: CI runner ubuntu-22.04, ubuntu-24.04, ubuntu-26.04 (x64);
CI runner ubuntu-22.04-arm, ubuntu-24.04-arm, ubuntu-26.04-arm (arm64);
CI runner macos-15, macos-26 (arm64); CI runner macos-15-intel,
macos-26-intel (x64); CI runner windows-2022, windows-2025 (x64) and
windows-11-arm (arm64).

## What was measured

1. `opencode2 --version` printed "opencode v2.2.5". opencode 1.19.5 prints
   "1.19.5" (fact 29).
2. On each label, opencode 2 started in its input box: the logo, a box
   with "Ask anything… "<example>"" and "Build · Big Pickle OpenCode", the
   folder with "shift+tab agents ctrl+p commands", and "2.2.5" at the
   bottom right. Only the example in the placeholder and the folder
   changed between labels. opencode 1.19.5 shows "tab agents" and the note
   "/update to upgrade to OpenCode 2.0" (fact 29).
3. opencode 2 runs two processes. On ubuntu-24.04 they were `opencode2`
   on the pane tty and a child
   `.../node_modules/@opencode/cli/bin/opencode.exe serve --service` with
   no tty (`?`). On macos-15 the child had no tty too (`??`). On Windows
   the tree was `cmd.exe /d /c ...\opencode2.cmd`, `opencode.exe`, and a
   child `opencode.exe serve --service`.
4. On ubuntu-24.04, opencode 2 held `.local/share/opencode/opencode.db`
   (with `-wal` and `-shm`) and `.local/share/opencode/log/opencode.log`
   open, as opencode 1 does. It made `.config/opencode/service.json`, four
   files in `.local/share/opencode` and two in `.local/state/opencode`. It
   made no `node_modules` in `.config/opencode`: opencode 1.19.5 made
   about 3,650 files there in the same run.
5. On windows-11-arm, opencode 2 also made
   `.cache/opencode/opencode-service-<pid>-<hex>.exe` and 545 files in
   `AppData/Local/Temp` of the throwaway home. It made no change in the real
   profile folders.

## Mechanism

opencode 2 starts its server as a second process (`serve --service`) and
writes `service.json` in its config folder. The TUI is a client of that
service. This explains the second process, but the source was not read.
A reader that maps a process to a terminal must skip the service process,
as it skips the Cline daemon (fact 46).

opencode 1 and opencode 2 use the same folder names (`opencode.db`,
`log/opencode.log`). A reader that finds an opencode database cannot tell
the major version from the folder name.

## Incident

None.

## Screens

- `corpus/opencode2/screens/idle-v2-2-5`

## Not measured

- Whether the service process stays after the TUI stops, and whether a
  second TUI uses the same service.
- The contents of `service.json` and of the database.
- The install with `https://opencode.ai/v2/install`, Homebrew, or the
  release archives.
- opencode 2 and opencode 1 on the same machine, with the same folders.
- A login, a turn, and the update from 1.x with `opencode upgrade --major`.
