# 054. Cursor CLI on Windows uses the account name of Windows and its install folder

## Measured

2026-10-30, the scenario `scenarios/first-run-windows.py cursor
cursor-agent` in the scenarios workflow (run 41146500448, and again in run
41145363320), Cursor CLI 2026.10.22-27dcf5f from
`irm 'https://cursor.com/install?win32=true' | iex`. The driver set the
throwaway profile of fact 53 and USERNAME=dev. It logged each file path
below the throwaway home that held the real account name, and the changes
in the real profile folders.

Measured on: CI runner windows-2022 (x64), CI runner windows-2025 (x64) and
CI runner windows-11-arm (arm64).

## What was measured

1. Cursor CLI made `.cursor\agent-cli-state.json`, `cli-config.json` and
   `statsig-cache.json` in the throwaway home, the same files as on Linux
   (fact 29). It reads USERPROFILE for these.
2. It made a log
   `AppData\Local\Temp\cursor-agent-logs-<account>\session-<time>-<pid>-1.log`
   in the throwaway TEMP, and held it open. `<account>` was the account name
   of Windows, not the USERNAME value `dev`. The driver logged "2 paths
   below the throwaway home hold the Windows account name" at 5 s and at
   20 s on the three images (run 41146500448).
3. In the real profile, the folder `%LOCALAPPDATA%\cursor-agent\versions`
   changed on the three images. This is the install folder. The `.cmd`
   shim starts `powershell.exe -NoProfile -ExecutionPolicy Bypass -File`
   with a script in that folder, and the script starts
   `versions\<version>\node.exe` (fact 51).
4. In run 41145363320, the real `%USERPROFILE%\.cursor` also changed on
   windows-2025 and windows-11-arm. In run 41146500448, it did not change.

## Mechanism

The shim finds the install from its own path, not from LOCALAPPDATA, so
the agent starts also when LOCALAPPDATA points elsewhere. The account name
probably comes from `os.userInfo()` of Node.js, which asks Windows and not
the environment. This was not checked in the source.

The `.cursor` change in run 41145363320 can come from the `--version` call,
which ran with the real profile before the start. This was not checked.

A tool that wants the log folder of a Cursor CLI session on Windows must
use the account name of the process, not USERNAME.

## Incident

The account name of the runner showed in a CI log of an earlier run of
this scenario (run 41144210399, now deleted). The scrub did not find it,
because a `-` before the name is a word character for the scrub's account
rule. The driver now replaces the account name in each file that it
writes.

## Screens

None.

## Not measured

- Whether the `.running` folder below `versions\` holds a file for each
  running session.
- Cursor CLI started from PowerShell with `cursor-agent.ps1`.
- The `agent` command, which the installer also adds.
