# 055. The real profile of a Windows runner changes with no agent action

## Measured

2026-10-30, the scenario `scenarios/first-run-windows.py` in the scenarios
workflow (run 41146500448, and again in run 41145363320), with the 15
agents of fact 51. For each agent, the driver listed the real profile
folders before the start and after 20 s (fact 53), and wrote the new,
changed and removed entries to `02-after-20s.outside`.

Measured on: CI runner windows-2022 (x64), CI runner windows-2025 (x64) and
CI runner windows-11-arm (arm64).

## What was measured

1. Only Codex CLI (fact 53) and Cursor CLI (fact 54) made a change in the
   real profile that their own files explain.
2. The other changes have no link to the files of the agent, and they came
   for different agents in the two runs:
   - `%USERPROFILE%\ntuser.dat.LOG1` and `ntuser.dat.LOG2`, the registry
     log of the profile (an earlier run of the scenario; the driver now
     skips them).
   - `%USERPROFILE%\_bazel_<account>` (windows-2022: Claude Code and Amp).
   - `%LOCALAPPDATA%\Temp` (Auggie and Kilo Code CLI on the three images,
     Cursor CLI on windows-2025 and windows-11-arm). The driver gives the
     agent another TEMP.
   - `%LOCALAPPDATA%\D3DSCache` and `%LOCALAPPDATA%\Microsoft` (windows-2025:
     Claude Code, Amp), and `%LOCALAPPDATA%\Microsoft\Credentials`
     (windows-2022: Amp).
   - New `%APPDATA%\Mozilla\Firefox` and `%LOCALAPPDATA%\Mozilla\Firefox`
     (windows-2025: Claude Code in run 41145363320, Continue CLI and Factory
     Droid in the runs).
   - `%LOCALAPPDATA%\Packages` (windows-11-arm: Codex CLI, in both runs).
   - `%USERPROFILE%\.kimi-code` (windows-2025: Amp in run 41145363320). The
     Kimi Code CLI install had put `kimi.exe` there before the run.
3. Each of these changes was a folder entry: a changed folder time or a
   new folder. The driver lists only two levels, so it did not list the
   files in these folders.

## Mechanism

A Windows runner has services that write to the profile of the runner
account while a job runs: the registry, the graphics shader cache, a
Firefox profile, the credential store and the Bazel cache folder. The
driver cannot tell which process made a change. A change that comes for
different agents in different runs is not an agent signal.

A test of "which agents ignore USERPROFILE" on Windows must look for the
agent's own file names in the real profile, not for any change.

## Incident

None.

## Screens

None.

## Not measured

- Which process made each of these changes. The driver did not trace file
  writes (for example with Process Monitor or ETW).
- Changes deeper than two levels below the real profile folders, other
  than below `.codex`.
- A second run of each agent on the same runner.
