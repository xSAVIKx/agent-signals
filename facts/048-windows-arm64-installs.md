# 048. The agent installs on Windows arm64

## Measured

2026-10-30, the scenario `scenarios/windows-installs.ps1` in the scenarios
workflow (run 41137353062, and again in run 41138908257), with the same
agents, versions and install commands as in fact 47. Node.js 22.23.4 for
arm64.

Measured on: CI runner windows-11-arm (Windows NT 10.0.26200, arm64),
compared with CI runner windows-2022 and windows-2025 (x64).

## What was measured

1. Amp does not run on Windows arm64. npm installed `@ampcode/cli` with
   no error, but `bin\amp.exe` was a file of 141 bytes, and
   `amp --version` printed "This version of
   C:\npm\prefix\node_modules\@ampcode\cli\bin\amp.exe is not compatible
   with the version of Windows you're running." and exited with 1. On x64,
   `bin\amp.exe` was 134,019,408 bytes and gave the version. The npm
   registry lists these platform packages of `@ampcode/cli`:
   `linux-x64`, `linux-arm64`, `darwin-x64`, `darwin-arm64` and
   `win32-x64`. There is no `win32-arm64` package.
2. Each other agent of fact 47 installed and gave its version on arm64.
   These agents use a native arm64 package:
   - Claude Code: `@anthropic-ai\claude-code-win32-arm64\claude.exe`.
   - Codex CLI: `@openai\codex-win32-arm64\vendor\aarch64-pc-windows-msvc\bin\codex.exe`.
   - opencode: `opencode-windows-arm64\bin\opencode.exe`. There is no
     `baseline` package on arm64.
   - Copilot CLI: `@github\copilot-win32-arm64\copilot.exe`.
   - Factory Droid: `@factory\cli-win32-arm64\bin\droid.exe`.
   - Cline CLI: `@cline\cli-windows-arm64\bin\cline.exe`.
   - Kilo Code CLI: `@kilocode\cli-windows-arm64\bin\kilo.exe`. There is
     no `baseline` package on arm64.
   - Cursor CLI: `versions\<version>\file_service.win32-arm64-msvc.node`
     and `merkle-tree-napi.win32-arm64-msvc.node`.
3. Qwen Code on arm64 has `vendor\ripgrep\x64-win32\rg.exe`, an x64
   binary, and no arm64 `rg.exe`. Its native modules for the terminal and
   the clipboard are arm64 (`@lydell\node-pty-win32-arm64`,
   `@teddyzhu\clipboard-win32-arm64-msvc`).
4. The `.exe` files of opencode, Amp (x64), Factory Droid and Kilo Code CLI
   have the file version 1.4.4, and `cline.exe` has 1.4.2, on both CPU
   types. The npm registry has `@oven/bun-*` packages with the version
   1.4.4 (an optional dependency of Qwen Code).

## Mechanism

An npm package with a native binary can install on a platform that it has
no binary for, and fail only when it starts. A tool that sees the command
on `PATH` must not take that as a working install.

The file version 1.4.4 is probably the version of Bun, if these
executables are made with Bun. This was not checked in the binaries.

## Incident

None.

## Screens

None. The output is in the logs of the runs.

## Not measured

- Whether Amp has another install for Windows arm64 (for example an x64
  binary under emulation).
- Whether Qwen Code can search files on arm64 with the x64 `rg.exe`.
- The process tree of a running agent on Windows arm64.
- Goose, OpenHands CLI and Aider on Windows.
