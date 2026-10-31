# 062. CODEX_HOME moves all files of Codex CLI, also on Windows

## Measured

2026-10-31, Codex CLI 0.166.0 from npm `@openai/codex`, in the scenarios
workflow (run 41151440753, and before it run 41149533184). The scenario
name `codex-home` starts `codex` with `CODEX_HOME=<throwaway folder>/.codex`.
That folder is next to the throwaway home, not in it, so that a file in it
cannot be a file of the default `~/.codex`. The scenario makes the folder
before the start. On Linux and macOS the run is
`scenarios/first-run.sh codex-home codex`. On Windows the run is
`scenarios/first-run-windows.py codex-home codex`, before the normal
`codex` run of the same job, with USERPROFILE, HOME, APPDATA, LOCALAPPDATA,
TEMP and TMP in the throwaway folder as in fact 53.

Measured on: CI runner ubuntu-22.04, ubuntu-24.04, ubuntu-26.04 (x64);
CI runner ubuntu-22.04-arm, ubuntu-24.04-arm, ubuntu-26.04-arm (arm64);
CI runner macos-15, macos-26 (arm64); CI runner macos-15-intel,
macos-26-intel (x64); CI runner windows-2022, windows-2025 (x64) and
windows-11-arm (arm64).

## What was measured

1. On each Linux and macOS label, Codex CLI made no file below the
   throwaway `HOME`. It made 5,504 files in the `CODEX_HOME` folder on
   Linux and on macos-15, and 5,505 on the other three macOS labels: the
   same names as in `~/.codex` of the normal run (fact 29): `config.toml`,
   `installation_id`, `version.json`, `.tmp/plugins` (about 5,400 files),
   `skills/.system`, `tmp/` (on Linux `tmp/arg0-linux/`), and the SQLite
   files `state_5`,
   `logs_2`, `goals_1`, `memories_1` and `queue_1`, each with `-wal` and
   `-shm`.
2. On Linux the process held the five SQLite files with `-wal` and `-shm`
   and `tmp/arg0-linux/codex-arg0<random>/.lock` open, all in the
   `CODEX_HOME` folder.
3. On the three Windows images, Codex CLI made 5,507 files in the
   `CODEX_HOME` folder: the same names, `.sandbox`, and three files in
   `tmp`. It made 0 changes in the real profile on windows-2022 and
   windows-2025. On windows-11-arm the one change was
   `%LOCALAPPDATA%\Packages`, which also changes with no agent (fact 55).
4. In the same jobs, the normal `codex` run after it made 22 changes in the
   real profile on windows-2022 and windows-2025, and 23 on
   windows-11-arm: the real `%USERPROFILE%\.codex` of fact 53.
5. The first screen was the same as with no `CODEX_HOME` (fact 52).
6. On Windows, the driver could not delete the throwaway folder after the
   `codex-home` run ("could not delete the throwaway folder"). The
   processes below the driver were stopped before that.

## Mechanism

Codex CLI takes its folder from `CODEX_HOME` when the variable is set, and
from the profile folder of the account when it is not set. On Windows, the
profile folder comes from Windows, not from USERPROFILE or HOME (fact 53).
`CODEX_HOME` is the one variable that keeps Codex CLI out of the real
profile on Windows.

A tool that looks for the Codex files of a session must read `CODEX_HOME`
from the environment of the process first, and use `~/.codex` only when
the variable is not set.

## Incident

Before this fact, each Windows first run wrote a Codex state into the real
profile of the runner (fact 53). The `codex-home` run does not.

## Screens

None. The screen is the screen of fact 52.

## Not measured

- Which process held files in the throwaway folder after the stop on
  Windows.
- A login, a turn, and the session files with `CODEX_HOME`.
- Whether the Codex app-server and its daemon use `CODEX_HOME` too.
- A `CODEX_HOME` folder that does not exist before the start.
