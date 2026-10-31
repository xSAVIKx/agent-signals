# 061. The first start of thirteen more agents with no login

## Measured

2026-10-31, the scenario `scenarios/first-run.sh <agent> <command>` in the
scenarios workflow (run 41151440753, and before it run 41149533184), with
a throwaway `HOME`, no login and no key. The workflow installed each agent
on the runner. Each install command comes from the page of the vendor or
from the package registry:

| Agent | Command | Version | Install |
|---|---|---|---|
| Kiro CLI | `kiro-cli` | 2.37.0 | `curl -fsSL https://cli.kiro.dev/install \| bash` |
| Junie CLI | `junie` | 26.10.27 (build 3893.6) | `curl -fsSL https://junie.jetbrains.com/install.sh \| bash` |
| Codebuff | `codebuff` | 1.0.688 | npm `codebuff` |
| Qoder CLI | `qodercli` | 1.1.81 | npm `@qoder-ai/qodercli` |
| CodeBuddy Code | `codebuddy` | 2.179.0 | npm `@tencent-ai/codebuddy-code` |
| Letta Code | `letta` | 0.34.35 | npm `@letta-ai/letta-code` |
| Neovate Code | `neovate` | 0.28.5 | npm `@neovate/code` |
| Every Code | `coder` | 0.6.196 | npm `@just-every/code` |
| iFlow CLI | `iflow` | 0.5.19 | npm `@iflow-ai/iflow-cli` |
| Mistral Vibe | `vibe` | 3.0.4 | `uv tool install --python 3.12 mistral-vibe` |
| gptme | `gptme` | 0.35.1 | `uv tool install --python 3.12 gptme` |
| Open Interpreter | `interpreter` | 0.0.56 | `curl -fsSL https://www.openinterpreter.com/install \| sh` |
| Grok CLI | `grok` | 1.1.7 | the `install.sh` of the `superagent-ai/grok-cli` README |

Node.js was 22.23.4 (from `actions/setup-node`) on each runner. Grok CLI is
a project of superagent-ai for the xAI API, not a program of xAI.

Measured on: CI runner ubuntu-22.04, ubuntu-24.04, ubuntu-26.04 (x64);
CI runner ubuntu-22.04-arm, ubuntu-24.04-arm, ubuntu-26.04-arm (arm64);
CI runner macos-15, macos-26 (arm64); CI runner macos-15-intel,
macos-26-intel (x64). Each agent installed and started on each of these
runners, except Grok CLI. The Grok CLI installer stopped with
"Unsupported platform: linux-arm64" on the three arm64 Linux images and
with "Unsupported platform: darwin-x64" on the two Intel macOS images.

## What was measured

The screen after 20 s, the processes, the files below the throwaway `HOME`,
and the files that the processes held open, on ubuntu-24.04 (x64) unless
an item names another label. The paths are relative to `HOME`.

1. Kiro CLI writes "Welcome to Kiro CLI, let's get you signed in!" and
   "Press enter to continue to the browser or esc to cancel". It runs as
   one native process `kiro-cli`. It holds
   `.local/share/kiro-cli/data.sqlite3` open and makes
   `.kiro/settings/cli.json`. On macos-26-intel the screen after 20 s was
   a menu "You are not logged in. Login now?" with "❯ Yes" and "No".
2. Junie CLI draws a logo of slashes and asks "Share anonymous statistics"
   with "→ Yes, share anonymous statistics" and "No, don't share". The
   process is `~/.local/share/junie/versions/3893.6/junie-app/bin/junie`
   in the real `HOME`: the scenario passes `JUNIE_DATA`, because the shim
   finds the binary below `$HOME/.local/share/junie`. Below the throwaway
   `HOME`, Junie made only `.rpmdb/rpmdb.sqlite` with `-wal` and `-shm`.
   The logo has an animation: on macos-26-intel some of its characters
   were other characters.
3. Codebuff draws CODEBUFF in large letters and "Press ENTER to login...".
   It runs as `node .../bin/codebuff` with a native child. On Linux, `ps`
   shows the work folder as the command of the child. A third process
   `/bin/sh -c cat >/dev/null 2>&1; printf '\033[?1049l...` with no tty
   waits as a child of the native process. Codebuff makes
   `.config/manicode/` and holds
   `.config/manicode/projects/example/chats/<time>/log.jsonl` open. The
   first `codebuff --version` downloads the binary and prints "Download
   complete! Starting Codebuff..." before the version.
4. Qoder CLI shows "Qoder CLI v1.1.81", "Not Login Please Auth", a box
   "Tips for getting started", and a menu "❯ 1. Sign in to continue",
   "2. Exit the application". It runs as `node .../bin/qodercli`. It makes
   about 230 files in `.qoder/` and holds a log in `.qoder/logs/runs/` and
   a `.jsonl` file in `.qoder/logs/sessions/-work-example/<uuid>/segments/`
   open. On ubuntu-22.04 and ubuntu-22.04-arm it adds a warning "Limited
   color support detected (TERM=screen)".
5. CodeBuddy Code asks "Do you trust the files in this folder?" with four
   numbered options, "1. Trust folder only (example)" under the mark. It
   runs as `node .../bin/codebuddy`. It makes `.codebuddy/` with about
   5,400 files in `.codebuddy/plugins/marketplaces`, and
   `sessions/<pid>.json`, `web-ui-port.json` and `user-state.json`.
6. Letta Code shows "Welcome to Letta Code" and a menu "> Sign in with
   Letta (default)", "Proceed locally", "Exit". It runs as
   `node .../bin/letta` and makes `.letta/settings.json`. On the four
   macOS labels the first line shows "^[[?1;2;4c" as text.
7. Neovate Code shows a framed list of providers with "/login" and
   "/model" as suggested actions, and below it an empty input line ">"
   between two rules, with a status line that ends in "🆔" and eight hex
   digits. The digits changed from start to start. It runs as
   `node --no-warnings=ExperimentalWarning .../bin/neovate`. It made no
   file below `HOME` in 20 s.
8. Every Code shows ">_ Welcome to Code" and a menu "> 1. Sign in with
   ChatGPT", "2. Provide your own API key" on five labels. On ubuntu-24.04,
   ubuntu-26.04, ubuntu-26.04-arm, macos-26 and macos-15-intel the pane
   was still empty after 20 s. It runs as `node .../bin/coder` with a
   native child `code-<target>` (on Linux x64
   `code-x86_64-unknown-linux-musl`). It makes `.code/version.json` and
   holds `.code/debug_logs/critical.log.<date>` open.
9. iFlow CLI shows a framed header with tips and a form "OpenAI Compatible
   API Configuration" with "Base URL:" and "https://api.openai.com/v1" in
   the field. It runs as `node .../bin/iflow` with a second `node` child.
   It makes `.iflow/` and holds `.iflow/log/console-<time>-<pid>.log` open.
10. Mistral Vibe shows "Welcome to Mistral Vibe - Let's get you started!"
    and "Enter continue". It runs as the native `vibe-rs` from its uv tool
    folder, with a child `vibe-app-server`. It makes `.vibe/` and holds
    `.vibe/logs/vibe-rs.log` and `.vibe/logs/vibe.log` open.
11. gptme asks "New conversation or load previous?" with "* New
    conversation" and "Load more". It runs as the Python of its uv tool
    folder. It made no file below `HOME` in 20 s.
12. Open Interpreter shows "Welcome to Open Interpreter" and a menu "> 1.
    Sign in with ChatGPT", "2. Sign in with Device Code", "3. Provide your
    own API key". It runs as one native process `interpreter`. Its files
    are in `.openinterpreter/` (fact 65).
13. Grok CLI asks on plain lines "Run grok directly on the host for this
    directory?" with "[Y] Yes, remember host mode", "[s] Yes, this session
    only" and "Choice [Y/s]:". On macos-15 and macos-26 (arm64) it asks
    "Run grok in sandbox mode for this directory?" with three choices. It
    runs as one native process `grok` and made no file below `HOME` in 20 s.

## Mechanism

Only Neovate Code starts at an input line. The other twelve agents first
show a login, a key or provider form, a trust question, a statistics
question or a choice of the conversation.

Junie CLI and the first `--version` call of Codebuff and Every Code show
two install patterns. The Junie shim runs a binary from a data folder
below `HOME`, so a throwaway `HOME` needs `JUNIE_DATA`. Codebuff and Every
Code download or install their binary at the first call. The scenario
takes the version from a second call when the first line says "Download"
or "Installing".

Codebuff and Open Interpreter run their native process with the work
folder or a short name as the command line, so a reader that finds an
agent by its command line must not expect the package path.

## Incident

The first run (41149533184) installed Junie CLI with npm
`@jetbrains/junie`. The shim of that package looked for its binary below
the throwaway `HOME`, stopped before 5 s, and the pane closed, so the
capture was "no pane". The scenario now keeps the pane of an agent that
stops (`remain-on-exit`), and the workflow installs Junie with its own
installer.

## Screens

- `corpus/kiro/screens/login-v2-37-0`
- `corpus/junie/screens/statistics-v26-10-27`
- `corpus/codebuff/screens/login-v1-0-688`
- `corpus/qoder/screens/login-v1-1-81`
- `corpus/codebuddy/screens/trust-v2-179-0`
- `corpus/letta/screens/backend-v0-34-35`
- `corpus/neovate/screens/no-model-v0-28-5`
- `corpus/everycode/screens/login-v0-6-196`
- `corpus/iflow/screens/base-url-v0-5-19`
- `corpus/vibe/screens/welcome-v3-0-4`
- `corpus/gptme/screens/conversation-v0-35-1`
- `corpus/interpreter/screens/login-v0-0-56`
- `corpus/grok/screens/host-mode-v1-1-7`

## Not measured

- The screens after a login, and any turn.
- Where Junie CLI writes its state on Linux and macOS. The Linux scenario
  does not list the real `HOME`, and Junie made no `.junie` folder below
  the throwaway `HOME`. On Windows it wrote to the real profile (fact 64).
- Why Every Code drew nothing in 20 s on five labels, and whether it draws
  later.
- Whether the Codebuff process with no tty stays after the TUI stops.
- The npm package `@jetbrains/junie` after a fix of the shim lookup.
- Grok CLI on arm64 Linux and on Intel macOS.
- Agents that the workflow does not install (see the pull request): Warp
  Oz, Plandex, Mentat, Trae Agent, Roo Code, Zed and Charm Mods.
