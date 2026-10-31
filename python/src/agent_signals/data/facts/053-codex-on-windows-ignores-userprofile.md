# 053. Codex CLI on Windows ignores USERPROFILE and HOME

## Measured

2026-10-30, the scenario `scenarios/first-run-windows.py codex codex` in
the scenarios workflow (run 41146500448, and again in run 41145363320),
Codex CLI 0.166.0 from npm `@openai/codex`. The driver set USERPROFILE,
HOME, HOMEDRIVE, HOMEPATH, APPDATA, LOCALAPPDATA, TEMP and TMP to folders
in a throwaway folder for the agent. It listed the real profile folders
(USERPROFILE and APPDATA to two levels, LOCALAPPDATA to two levels without
`Temp`, and TEMP to one level) before the start, and again after 5 s and
after 20 s.

Measured on: CI runner windows-2022 (x64), CI runner windows-2025 (x64) and
CI runner windows-11-arm (arm64).

## What was measured

1. Codex CLI made no file in the throwaway home on the three images.
2. On the three images, Codex CLI made these entries in the real
   `%USERPROFILE%\.codex` after 5 s, and they were the same after 20 s:
   `config.toml`, `installation_id`, `version.json`, `.sandbox`, `.tmp`,
   `skills`, and the SQLite files `state_5`, `logs_2`, `goals_1`,
   `memories_1` and `queue_1`, each with `-wal` and `-shm`. These are the
   same names as in `~/.codex` on Linux (fact 29).
3. Its screen was the normal first screen (fact 52). The processes were
   `node codex.js` and `codex.exe` (fact 51).
4. Each other agent of fact 51 that started made its own files in the
   throwaway home. Amp on windows-11-arm and Factory Droid in run
   41146500448 did not start (fact 51).

## Mechanism

`codex.exe` is a Rust program. A Rust program that asks Windows for the
profile folder (for example with `SHGetKnownFolderPath`) does not read
USERPROFILE or HOME. This was not checked in the source. `CODEX_HOME` was
not set. Codex CLI has the variable `CODEX_HOME` for the folder of
`~/.codex`. It was not tested here.

A scenario on Windows that must not touch the real profile must set
`CODEX_HOME` for Codex CLI. A tool that looks for the Codex files of a
Windows user must look in the profile folder of the account, not in a
folder from the environment of the process.

## Incident

The first-run scenario wrote a Codex state into the real profile of each
runner. The runner is thrown away after the job, so this did no harm in CI.
On a real machine, the same scenario would add files to the user's
`.codex` folder.

## Screens

None.

## Not measured

- Whether `CODEX_HOME` moves all these files on Windows.
- Whether Codex CLI on Windows reads a login from the real `.codex` when
  USERPROFILE points elsewhere.
- Codex CLI on Linux or macOS with HOME changed: there, the first-run
  scenario found the files in the throwaway HOME (fact 29).
- The standalone Windows installer of Codex CLI.
