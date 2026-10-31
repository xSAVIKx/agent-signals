# 064. The first start of more agents on Windows, and four that write to the real profile

## Measured

2026-10-31, the scenario `scenarios/first-run-windows.py <agent> <command>`
in the scenarios workflow (run 41153462586, and runs 41155667724,
41151440753 and 41149533184), in a pseudo console of 120 x 40, with USERPROFILE, HOME,
APPDATA, LOCALAPPDATA, TEMP and TMP in a throwaway folder, no login and no
key. `scenarios/install-windows-agents.ps1` installed the agents of
groups c and d:

| Agent | Version | Install on Windows |
|---|---|---|
| Kiro CLI | 2.37.0 | `irm https://cli.kiro.dev/install.ps1 \| iex` (an x64 MSI) |
| Junie CLI | 26.10.27 (build 3893.6) | `irm https://junie.jetbrains.com/install.ps1 \| iex` |
| Codebuff | 1.0.688 | npm `codebuff` |
| Qoder CLI | 1.1.81 | npm `@qoder-ai/qodercli` |
| CodeBuddy Code | 2.179.0 | npm `@tencent-ai/codebuddy-code` |
| Letta Code | 0.34.35 | npm `@letta-ai/letta-code` |
| Neovate Code | 0.28.5 | npm `@neovate/code` |
| Every Code | 0.6.196 | npm `@just-every/code` |
| iFlow CLI | 0.5.19 | npm `@iflow-ai/iflow-cli` |
| Aider | 0.86.2 | `uv tool install --python 3.12 aider-chat` |
| OpenHands CLI | 1.16.0 | `uv tool install --python 3.12 openhands` |
| gptme | 0.35.1 | `uv tool install --python 3.12 gptme` |
| Mistral Vibe | 3.0.4 | `uv tool install --python 3.12 mistral-vibe` |
| Goose | 1.57.0 | `download_cli.ps1` of the `block/goose` repository, with `CONFIGURE=false` |
| Open Interpreter | 0.0.56 | `irm https://www.openinterpreter.com/install.ps1 \| iex` |

Measured on: CI runner windows-2022 (x64), CI runner windows-2025 (x64) and
CI runner windows-11-arm (arm64).

## What was measured

1. These agents started and showed the same first question as on Linux
   (fact 61, fact 46) on the three images: Junie CLI, Qoder CLI, CodeBuddy
   Code, Letta Code and Open Interpreter. Codebuff, Every Code, Aider,
   OpenHands CLI, Mistral Vibe and Goose did the same on the two x64
   images. Aider asked "No git repo found, create one to track aider's
   changes (recommended)? (Y)es/(N)o [Yes]:".
2. Some screens differ from Linux:
   - Kiro CLI shows "You are not logged in. Login now?" with "> Yes" and
     "No", as on macos-26-intel (fact 61), on the three images.
   - iFlow CLI draws IFLOW in large block letters above its header box, in
     place of the small logo at the left of the box on Linux.
   - Neovate Code draws its list bullets as "*", not "•".
   - gptme asks "New conversation or load previous?" with "0: New
     conversation", "1: Load more" and "Select option number:", in place
     of a menu with a mark (x64 only).
3. Four agents wrote to the real profile folders, not to the throwaway
   home, on each image where they started:
   - Open Interpreter: 21 changes in `%USERPROFILE%\.openinterpreter`
     (`config.toml`, `installation_id`, `version.json`, `.tmp`, `skills`,
     and the SQLite files `state_5`, `logs_2`, `goals_1`, `memories_1` and
     `queue_1` with `-wal` and `-shm`), as Codex CLI does (fact 53).
   - Every Code: `%USERPROFILE%\.code` with `debug_logs` and
     `version.json`.
   - Junie CLI: `%USERPROFILE%\.junie` with `settings.json`,
     `history.jsonl`, `sessions`, `processes`, `instances`, `versions`,
     `misc` and `logs`.
   - Kiro CLI: `%USERPROFILE%\.kiro\settings`.
4. The other new agents made no change in the real profile, or only
   changes that also happen with no agent (fact 55): CodeBuddy Code,
   Letta Code, Neovate Code, Qoder CLI, Codebuff, Mistral Vibe, gptme,
   OpenHands CLI, Goose and opencode 2 (fact 63). iFlow CLI changed the
   folder `%USERPROFILE%\.iflow`, which existed before the start.
5. Processes and folders:
   - Kiro CLI runs as one process `kiro-cli.exe` from
     `%LOCALAPPDATA%\Kiro-Cli`. The installer prints "installed to
     C:\Program Files\Kiro-Cli\", but the file is not there. The x64 MSI
     installed and ran on windows-11-arm too.
   - Junie CLI runs as `cmd.exe /d /c ...\.local\bin\junie.bat`, then
     `junie.exe` and a second `junie.exe`, from
     `%USERPROFILE%\.local\share\junie\versions\3893.6\junie\`.
   - Codebuff runs as `node ...\codebuff\index.js` with a child
     `codebuff.exe` from `.config\manicode\` of the throwaway home. A
     `powershell.exe` that is not below the driver writes a file in the
     throwaway folder (`[System.IO.File]::WriteAllText(...)`).
   - Every Code runs as `node ...\coder.js` with a child
     `code-x86_64-pc-windows-msvc.exe` from
     `AppData\Local\just-every\code\0.6.196\` of the throwaway home. Its
     `--version` printed "Installing @just-every/code v0.6.196 for
     x86_64-pc-windows-msvc..." on both calls.
   - Mistral Vibe runs as eight processes: `vibe.exe`, two Python
     processes, `vibe-rs.exe`, `vibe-app-server.exe` and two more Python
     processes.
6. Installs that failed:
   - On windows-11-arm, `uv tool install` of `aider-chat`, `openhands`,
     `gptme` and `mistral-vibe` failed. uv tried to build `hf-xet` or
     `cryptography` from source ("Failed to build `cryptography==50.0.2`",
     "failed to run custom build command for `openssl-sys v0.9.117`").
   - On windows-11-arm, the Goose script stops ("Windows ARM64 is not
     currently supported.").
   - On windows-11-arm, Every Code stopped at the start with "Unsupported
     platform" in `coder.js`.
   - On windows-11-arm, Codebuff stopped with "❌ Failed to download
     codebuff: Unsupported platform: win32 arm64" (run 41155667724). In run
     41153462586 the driver could not print that line in the code page of
     the console ("UnicodeEncodeError"). The driver now writes UTF-8.
   - The npm package `@jetbrains/junie` on Windows (run 41149533184)
     printed "[Junie] Shim not found at ~\.local\bin\junie" also with the
     real profile.

## Mechanism

Open Interpreter has the file layout of Codex CLI (fact 65). Like Codex
CLI, it takes its folder from Windows, not from USERPROFILE or HOME. Every
Code is a fork of Codex CLI (its npm description says so) and does the
same with `.code`. Junie CLI is a JVM program: the JVM takes the home
folder from Windows. Kiro CLI also ignores USERPROFILE. The source of these
agents was not read.

A tool that finds the files of these agents on Windows must look in the
profile folder of the account. A scenario that must not touch the real
profile cannot use these four agents with a throwaway USERPROFILE alone.

## Incident

The first runs wrote state of these four agents into the real profile of
each runner. The runner is thrown away after the job.

## Screens

None. The Linux screens are in the corpus (fact 61).

## Not measured

- A variable like `CODEX_HOME` for Open Interpreter, Every Code, Junie CLI
  or Kiro CLI (fact 62 has the Codex case).
- Grok CLI on Windows: its README gives a bash installer only.
- What the PowerShell process of Codebuff writes.
- Why `%USERPROFILE%\.qoder` changed during the runs of other agents.
