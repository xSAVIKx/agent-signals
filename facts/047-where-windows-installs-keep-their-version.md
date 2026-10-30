# 047. Where the Windows installs keep their version

## Measured

2026-10-30, the scenario `scenarios/windows-installs.ps1` in the scenarios
workflow (run 41137353062, and again in run 41138908257). The workflow
installed each agent, then the scenario ran `Get-Command <cmd> -All` and
`<cmd> --version`, read `package.json`, and listed the install folder. It
started no agent interactively.

| Agent | Command | Version | Install |
|---|---|---|---|
| Claude Code | `claude` | 2.1.314 | npm `@anthropic-ai/claude-code` |
| Codex CLI | `codex` | 0.166.0 | npm `@openai/codex` |
| opencode | `opencode` | 1.19.5 | npm `opencode-ai` |
| Gemini CLI | `gemini` | 0.66.0 | npm `@google/gemini-cli` |
| GitHub Copilot CLI | `copilot` | 1.0.105 | npm `@github/copilot` |
| Qwen Code | `qwen` | 0.26.4 | npm `@qwen-code/qwen-code` |
| Amp | `amp` | 0.0.1793390435-g08e9ec | npm `@ampcode/cli` |
| Crush | `crush` | v0.99.0 | npm `@charmland/crush` |
| Continue CLI | `cn` | 1.5.47 | npm `@continuedev/cli` |
| Factory Droid | `droid` | 1.0.0 | npm `@factory/cli` |
| Cline CLI | `cline` | 3.0.74 | npm `cline` |
| Kilo Code CLI | `kilo` | 7.8.18 | npm `@kilocode/cli` |
| Auggie | `auggie` | 0.36.0 | npm `@augmentcode/auggie` |
| Cursor CLI | `agent`, `cursor-agent` | 2026.10.22-27dcf5f | `irm 'https://cursor.com/install?win32=true' \| iex` |
| Kimi Code CLI | `kimi` | 2.4.1 | `irm https://code.kimi.com/kimi-code/install.ps1 \| iex` |

Node.js 22.23.4 and npm 10.9.9 (from `actions/setup-node`).

Measured on: CI runner windows-2022 (Windows NT 10.0.20348, x64), CI
runner windows-2025 (10.0.26100, x64) and CI runner windows-11-arm
(10.0.26200, arm64). The two x64 images gave the same layout. Fact 48
gives the arm64 differences.

## What was measured

1. The npm prefix on all three images is `C:\npm\prefix`. For each npm
   agent, npm writes three shims there: `<cmd>.ps1`, `<cmd>.cmd` and
   `<cmd>` with no extension. `Get-Command <cmd> -All` lists them in this
   order: `ExternalScript <cmd>.ps1`, `Application <cmd>.cmd`,
   `Application <cmd>`. None of the npm paths holds the version. The
   version is in `C:\npm\prefix\node_modules\<package>\package.json`, and
   on the x64 images it was the same as `--version` for each npm agent.
2. The shims point to one of three kinds of target:
   - A native `.exe` in the main package: Claude Code
     (`@anthropic-ai\claude-code\bin\claude.exe`), opencode
     (`opencode-ai\bin\opencode.exe`) and Amp (`@ampcode\cli\bin\amp.exe`).
     The same file is also in a platform package, for example
     `@anthropic-ai\claude-code-win32-x64\claude.exe`,
     `opencode-windows-x64\bin\opencode.exe` and
     `opencode-windows-x64-baseline\bin\opencode.exe`.
   - A JavaScript launcher that starts a native `.exe` from a platform
     package: Codex CLI (`bin\codex.js` to
     `@openai\codex-win32-x64\vendor\x86_64-pc-windows-msvc\bin\codex.exe`,
     next to `codex-code-mode-host.exe`, `codex-path\rg.exe` and
     `codex-resources\codex-command-runner.exe`), Copilot CLI
     (`npm-loader.js` to `@github\copilot-win32-x64\copilot.exe`), Crush
     (`run-crush.js` to `@charmland\crush\bin\crush.exe`), Factory Droid
     (`bin\droid` to `@factory\cli-win32-x64\bin\droid.exe`), Cline CLI
     (`bin\cline` to `@cline\cli-windows-x64\bin\cline.exe`) and Kilo
     Code CLI (`bin\kilo` to `@kilocode\cli-windows-x64\bin\kilo.exe`).
   - JavaScript that runs in `node.exe`: Gemini CLI
     (`bundle\gemini.js`), Qwen Code (`cli-entry.js`), Continue CLI
     (`dist\cn.js`) and Auggie (`augment.mjs`).
3. The file version of a native `.exe` is not the agent version.
   `copilot.exe` had 1.0.105 and `claude.exe` had 2.1.314.0 (run
   41138908257), the agent versions. `opencode.exe`,
   `amp.exe`, `droid.exe` and `kilo.exe` all had 1.4.4. `cline.exe` had
   1.4.2. `codex.exe` and `crush.exe` had no file version.
4. Cursor CLI installs to `%LOCALAPPDATA%\cursor-agent`, and the installer
   adds that folder to the user `PATH`. The folder holds `agent.cmd`,
   `agent.ps1`, `cursor-agent.cmd` and `cursor-agent.ps1`, and
   `versions\<version>\` with `node.exe`, `rg.exe`, `crepectl.exe`,
   `cursorsandbox.exe`, `node_sqlite3.node`, `node_modules\` and a `.running\`
   folder. `versions\promote-staged.cmd` is next to the version
   folders. The version is the name of the folder
   `versions\2026.10.22-27dcf5f`, the same as `--version`.
5. Kimi Code CLI installs one file, `%USERPROFILE%\.kimi-code\bin\kimi.exe`,
   and a file `region` in `.kimi-code`. No path holds the version. Only
   `kimi --version` gave it.
6. `--version` makes files for some agents. After the calls, these
   folders were new: `.codex`, `.cursor`, `.gemini`,
   `%LOCALAPPDATA%\copilot` and `%LOCALAPPDATA%\cursor-compile-cache` (the
   first group of agents), and `.cline`, `.continue`, `.cache`, `.config`,
   `.local`, `%LOCALAPPDATA%\amp` and `%LOCALAPPDATA%\kimi-code` (the second
   group).

## Mechanism

A tool that wants the version of a running agent on Windows can read it
from the path only for Cursor CLI. For an npm agent, it can go from the
process image (for example `codex.exe` in a platform package) up to the
`node_modules\<package>` folder of the main package and read
`package.json`. For Gemini CLI, Qwen Code, Continue CLI and Auggie, the
process image is `node.exe`, so the tool must read the command line of the
process to find the package.

## Incident

None. This answers request 13 of aw (where the Windows installs keep their
version).

## Screens

None. The output is in the logs of the runs.

## Not measured

- The process tree of a running agent on Windows: the scenario starts no
  agent interactively.
- The standalone Windows installer of Codex CLI, and installs with
  `winget`, Scoop or Chocolatey.
- Which agent of the second group made `.cache`, `.config` and `.local`.
- The Goose and OpenHands CLI installs on Windows.
- An npm prefix other than `C:\npm\prefix`, for example the default
  `%APPDATA%\npm` of a new Node.js install.
