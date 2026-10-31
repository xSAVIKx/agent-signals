# 051. The Windows process trees of the agents in a pseudo console

## Measured

2026-10-30, the scenario `scenarios/first-run-windows.py <agent> <command>`
in the scenarios workflow (run 41146500448, and again in run 41145363320).
The driver `scenarios/conpty.py` started each agent in a pseudo console of
120 x 40 with pywinpty 3.1.2 and a throwaway profile, and sent no key. After
5 s and after 20 s it listed each process below the driver with psutil
7.2.2. The workflow installed the agents with
`scenarios/install-windows-agents.ps1`, the same commands and versions as in
fact 47 (Claude Code 2.1.314, Codex CLI 0.166.0, opencode 1.19.5, Gemini CLI
0.66.0, Copilot CLI 1.0.105, Qwen Code 0.26.4, Cursor CLI 2026.10.22-27dcf5f,
Amp 0.0.1793390435-g08e9ec, Crush v0.99.0, Continue CLI 1.5.47, Factory
Droid 1.0.0, Cline CLI 3.0.74, Kilo Code CLI 7.8.18, Auggie 0.36.0, Kimi
Code CLI 2.4.1). Node.js 22.23.4. Python 3.12.16 from uv, for the CPU of
the image.

Measured on: CI runner windows-2022 (Windows NT 10.0.20348, x64), CI
runner windows-2025 (10.0.26100, x64) and CI runner windows-11-arm
(10.0.26200, arm64).

## What was measured

1. The console host is `OpenConsole.exe` from the pywinpty wheel, not the
   `conhost.exe` of Windows:
   `<venv>\Lib\site-packages\winpty\OpenConsole.exe --headless --width 120
   --height 40 --signal 0x<n>`. It is a child of the driver, next to the
   agent, not a child of the agent. It was the same on the three images.
2. The driver starts an npm shim as `cmd.exe /d /c C:\npm\prefix\<cmd>.cmd`,
   as cmd.exe finds the command with PATHEXT. It starts an `.exe` directly.
   Below `cmd.exe`, the trees after 20 s were:

   | Agent | Processes below `cmd.exe` |
   |---|---|
   | Claude Code | `claude.exe` (from `@anthropic-ai\claude-code\bin\`) |
   | Codex CLI | `node codex.js`, then `codex.exe` from `@openai\codex-win32-<cpu>\vendor\<target>\bin\` |
   | opencode | `opencode.exe` |
   | Gemini CLI | `node gemini.js`, then `node.exe --max-old-space-size=8189 gemini.js`, then `powershell.exe -NoProfile -NoLogo -InputFormat Text -NoExit -ExecutionPolicy Unrestricted -C ...`, then `conhost.exe 0x4` |
   | Copilot CLI | `node npm-loader.js`, then `copilot.exe`, then two processes that stopped before psutil read them |
   | Qwen Code | three `node.exe` processes, one below the other |
   | Cursor CLI | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File %LOCALAPPDATA%\cursor-agent\...`, then `versions\<version>\node.exe` |
   | Amp | `amp.exe` (x64 only) |
   | Crush | `node`, then `crush.exe` |
   | Continue CLI | `node` |
   | Factory Droid | `node bin\droid`, then `droid.exe` (run 41145363320) |
   | Cline CLI | `node bin\cline`, then `cline.exe`, then `cline.exe --cline-hub-daemon --cwd <work folder> --host ...` |
   | Kilo Code CLI | `node bin\kilo`, then `kilo.exe` |
   | Auggie | `node` |
   | Kimi Code CLI | no `cmd.exe`: `kimi.exe` is a child of the driver |

3. On windows-11-arm, opencode (run 41146500448) and Kilo Code CLI (run
   41145363320) had a child `choco list --limit-output <name>`, with a
   second `choco.exe` and a `conhost.exe 0x4` below it. The x64 images did
   not show this process at 5 s or at 20 s.
4. Gemini CLI starts a PowerShell with `-NoExit`, which stays after 20 s.
   That PowerShell gets its own `conhost.exe`, outside the pseudo console.
5. No agent left a process with the throwaway folder in its command line
   or folder outside the tree below the driver.
6. Factory Droid 1.0.0 ran in run 41145363320. In run 41146500448, npm
   installed `@factory/cli` with exit 0, but `droid` printed "Error: Could
   not find the droid binary for win32-x64." (and win32-arm64), and
   exited with 1. The npm registry gives 2026-10-30T23:47:30Z as the
   release time of `@factory/cli` 1.1.0, a few minutes before that install.

## Mechanism

The pywinpty wheel holds `conpty.dll` and `OpenConsole.exe` from the
ConPTY package of Microsoft, and its ConPTY backend uses them (the build
script `build.rs` of pywinpty 3.1.2). Windows Terminal also uses its own
OpenConsole. A tool that looks for the terminal of an agent process on
Windows must look at the parent side of the agent, not at its children.

The `choco list` call is probably an update check that asks which package
manager installed the agent. This was not checked in the source.

## Incident

pyte 0.8.2 raised a TypeError on `CSI ? 6 n` (Copilot CLI, Kimi Code CLI)
and on `CSI > ... m` or `CSI ? ... m` (Gemini CLI, Crush), and dropped the
rest of the output chunk (run 41145363320). The driver now ignores these
forms. Run 41146500448 had no parse error.

## Screens

None. The screens and process lists are in the logs of the runs.

## Not measured

- Windows Terminal, conhost.exe and PowerShell as the shell of a real
  user. A user in PowerShell starts `<cmd>.ps1`, not `<cmd>.cmd`.
- The two short-lived children of `copilot.exe`.
- Whether the Gemini CLI PowerShell stays after the agent stops.
- Goose, OpenHands CLI and Aider on Windows.
