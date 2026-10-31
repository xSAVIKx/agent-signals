# 065. Open Interpreter 0.0.56 keeps the file layout of Codex CLI

## Measured

2026-10-31, Open Interpreter 0.0.56, the Rust version from the installer
`https://www.openinterpreter.com/install` (Linux and macOS) and
`https://www.openinterpreter.com/install.ps1` (Windows), in the scenarios
workflow (run 41151440753, and runs 41149533184 and 41153462586). The
scenario was `scenarios/first-run.sh interpreter interpreter` and
`scenarios/first-run-windows.py interpreter interpreter`, with no login.
In the same jobs, Codex CLI 0.166.0 ran with the same scenario (facts 29,
53 and 62).

The GitHub releases of `OpenInterpreter/open-interpreter` have the tags
`rust-v0.0.56` and `rust-v0.0.55`. The Linux installer reads the variables
`OPEN_INTERPRETER_INSTALL_DIR` or `CODEX_INSTALL_DIR`, and
`OPEN_INTERPRETER_COMMAND_NAME` or `CODEX_COMMAND_NAME`. It installs
`interpreter`, the alias `i`, and `codex-code-mode-host` in
`~/.local/bin`.

Measured on: CI runner ubuntu-22.04, ubuntu-24.04, ubuntu-26.04 (x64);
CI runner ubuntu-22.04-arm, ubuntu-24.04-arm, ubuntu-26.04-arm (arm64);
CI runner macos-15, macos-26 (arm64); CI runner macos-15-intel,
macos-26-intel (x64); CI runner windows-2022, windows-2025 (x64) and
windows-11-arm (arm64).

## What was measured

1. On ubuntu-24.04, Open Interpreter made `~/.openinterpreter/` with the
   same names as `~/.codex/` of Codex CLI 0.166.0: `config.toml`,
   `installation_id`, `version.json`, `.tmp/plugins` (5,434 files),
   `.tmp/plugins.sha`, `.tmp/plugins.sync.lock`, `skills/.system`, `tmp/`,
   and the SQLite files `state_5`, `logs_2`, `goals_1`, `memories_1` and
   `queue_1`, each with `-wal` and `-shm`. Codex CLI made 49 files in
   `skills/.system`, Open Interpreter 62.
2. The process held the five SQLite files with `-wal` and `-shm` open, and
   `.openinterpreter/tmp/arg0/codex-arg0<random>/.lock`. The lock folder
   of Codex CLI is `tmp/arg0-linux/codex-arg0<random>/`.
3. The first screen has the layout of the Codex CLI screen: "Welcome to
   Open Interpreter", a sign-in text, a numbered menu "> 1. Sign in with
   ChatGPT", "2. Sign in with Device Code", "3. Provide your own API key",
   each with a line of help, and "Press enter to continue". Codex CLI
   0.166.0 has a fourth option "Use Amazon Bedrock".
4. The ten Linux and macOS labels gave the same bytes for the screen.
5. On Windows, Open Interpreter made the same entries in the real
   `%USERPROFILE%\.openinterpreter` (21 changes), and none in the
   throwaway home, on the three images (fact 64).

## Mechanism

The installer variables, the binary `codex-code-mode-host` and the file
names show that Open Interpreter 0.0.56 is built from the source of Codex
CLI, with the folder `.codex` renamed to `.openinterpreter`. The source
was not compared.

A reader of Codex sessions can read the files of Open Interpreter with the
same rules, in another folder. A tool that finds a process by the name
`codex` or by a path with `.codex` does not find Open Interpreter.

## Incident

None.

## Screens

- `corpus/interpreter/screens/login-v0-0-56`

## Not measured

- Whether a variable such as `CODEX_HOME` or `OPEN_INTERPRETER_HOME`
  moves the folder.
- The session files, the hooks and the app-server after a login.
- The Python Open Interpreter (`open-interpreter` on PyPI, 0.4.3). The
  README says that it continues as a fork of the community
  (`endolith/open-interpreter`).
