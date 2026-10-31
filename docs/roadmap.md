# Roadmap

The agents to cover, in order, and the state of each cell of the matrix.
Updated 2026-10-31, third round.

## Order

1. The agents that aw and tg-bridge read now: Claude Code, Codex CLI,
   Antigravity CLI (agy), Cursor CLI.
2. opencode, Gemini CLI and GitHub Copilot CLI: CLI agents with many users
   that a tool can drive in a terminal.
3. Other terminal agents: Aider, Goose, Amp, Crush, Qwen Code, Kimi Code
   CLI, Kilo Code CLI, Auggie, OpenHands CLI, Kiro CLI, Factory Droid, Cline
   CLI, Continue CLI.
4. More terminal agents (fact 61): Junie CLI, Codebuff, Qoder CLI,
   CodeBuddy Code, Letta Code, Neovate Code, Every Code, iFlow CLI, Mistral
   Vibe, gptme, Open Interpreter, Grok CLI, opencode 2.

## The agents

`not checked` means that nobody in this project ran or read it yet.

| Agent | Command | Install | Login for CI | State folders |
|---|---|---|---|---|
| Claude Code | `claude` | npm `@anthropic-ai/claude-code` (fact 29) | `CLAUDE_CODE_OAUTH_TOKEN` or `ANTHROPIC_API_KEY` (not checked in CI) | `~/.claude/` (`sessions/`, `projects/`), `/tmp/claude-<uid>/` |
| Codex CLI | `codex` | standalone install (seen: the version is in the package path); npm `@openai/codex` (fact 29) | `OPENAI_API_KEY` through `codex login --with-api-key` (from `codex login --help`) | `~/.codex/` (`sessions/`, `thread-writer-locks/`, `packages/`); `$CODEX_HOME` when it is set, on all three systems (fact 62) |
| Antigravity CLI | `agy` | not checked | not known: OAuth in a browser; no key login found | `~/.gemini/antigravity-cli/`, `~/.gemini/config/` |
| Cursor CLI | `cursor-agent`, `agent` | `curl https://cursor.com/install \| bash` (fact 29); Windows `irm 'https://cursor.com/install?win32=true' \| iex` to `%LOCALAPPDATA%\cursor-agent\versions\<version>\` (fact 47) | `CURSOR_API_KEY` (from `cursor-agent --help`) | `~/.cursor/` (`chats/`, `projects/`) |
| opencode | `opencode` | npm `opencode-ai` gives the 1.x line (fact 29) | provider keys through `opencode auth` (not checked) | `~/.local/share/opencode/` |
| Gemini CLI | `gemini` | npm `@google/gemini-cli` (fact 30) | `GEMINI_API_KEY` (not checked) | `~/.gemini/` (`tmp/`, `history/`, `projects.json`), shared with agy |
| GitHub Copilot CLI | `copilot` | npm `@github/copilot` (fact 30) | a GitHub token (not checked) | `~/.copilot/` (`session-state/<id>/inuse.<pid>.hold`); the version in `~/.cache/copilot/pkg/linux-<cpu>/<version>/` or `~/Library/Caches/copilot/pkg/darwin-<cpu>/<version>/` (fact 50) |
| Aider | `aider` | `pipx install aider-chat`; on macOS and ubuntu-26.04 only `uv tool install --python 3.12 aider-chat` works (facts 30, 49) | a provider key (not checked) | `~/.aider/` |
| Goose | `goose` | `curl -fsSL https://github.com/block/goose/releases/download/stable/download_cli.sh \| CONFIGURE=false bash` (fact 46) | not checked | `~/.local/share/goose/`, `~/.local/state/goose/` |
| Amp | `amp` | npm `@ampcode/cli` (fact 46; `@sourcegraph/amp` is renamed to it); no Windows arm64 binary (fact 48) | not checked | `~/.cache/amp/`, `~/.local/share/amp/` |
| Crush | `crush` | npm `@charmland/crush` (fact 46) | not checked | `~/.local/share/crush/` |
| Qwen Code | `qwen` | npm `@qwen-code/qwen-code` (fact 30) | a provider key (not checked) | `~/.qwen/` |
| Kiro CLI | `kiro-cli` | `curl -fsSL https://cli.kiro.dev/install \| bash`; Windows `irm https://cli.kiro.dev/install.ps1 \| iex` (fact 61) | not checked | `~/.kiro/`, `~/.local/share/kiro-cli/data.sqlite3`; Windows: the real `%USERPROFILE%\.kiro` (fact 64) |
| Factory Droid | `droid` | npm `@factory/cli` (fact 46) | not checked | `~/.factory/` |
| Cline CLI | `cline` | npm `cline` (fact 46) | not checked | `~/.cline/data/` (SQLite files in `db/`; a hub daemon with no tty) |
| Continue CLI | `cn` | npm `@continuedev/cli` (fact 46) | not checked | `~/.continue/` |
| Kimi Code CLI | `kimi` | `curl -fsSL https://code.kimi.com/kimi-code/install.sh \| bash`; Windows `irm https://code.kimi.com/kimi-code/install.ps1 \| iex` (facts 46, 47) | not checked | `~/.kimi-code/`; cache `~/.cache/kimi-code/` (Linux), `~/Library/Caches/kimi-code/` (macOS) |
| Kilo Code CLI | `kilo` | npm `@kilocode/cli` (fact 46) | not checked | `~/.local/share/kilo/` (`kilo.db`, `log/`), `~/.config/kilo/` |
| Auggie | `auggie` | npm `@augmentcode/auggie` (fact 46) | not checked | `~/.augment/` |
| OpenHands CLI | `openhands` | `uv tool install --python 3.12 openhands` (fact 46) | not checked | none in the first 20 s |
| Junie CLI | `junie` | `curl -fsSL https://junie.jetbrains.com/install.sh \| bash`; Windows `install.ps1` (fact 61) | not checked | binary in `~/.local/share/junie/`; Windows state in the real `%USERPROFILE%\.junie`; Linux state not checked |
| Codebuff | `codebuff` | npm `codebuff` (fact 61) | not checked | `~/.config/manicode/` |
| Qoder CLI | `qodercli` | npm `@qoder-ai/qodercli` (fact 61) | not checked | `~/.qoder/` |
| CodeBuddy Code | `codebuddy` | npm `@tencent-ai/codebuddy-code` (fact 61) | not checked | `~/.codebuddy/` |
| Letta Code | `letta` | npm `@letta-ai/letta-code` (fact 61) | not checked | `~/.letta/` |
| Neovate Code | `neovate` | npm `@neovate/code` (fact 61) | not checked | none in the first 20 s |
| Every Code | `coder` | npm `@just-every/code` (fact 61) | not checked | `~/.code/`; Windows: the real `%USERPROFILE%\.code` (fact 64) |
| iFlow CLI | `iflow` | npm `@iflow-ai/iflow-cli` (fact 61) | not checked | `~/.iflow/` |
| Mistral Vibe | `vibe` | `uv tool install mistral-vibe` (fact 61) | not checked | `~/.vibe/` |
| gptme | `gptme` | `uv tool install gptme` (fact 61) | not checked | none in the first 20 s |
| Open Interpreter | `interpreter` | `curl -fsSL https://www.openinterpreter.com/install \| sh`; Windows `install.ps1` (fact 61) | not checked | `~/.openinterpreter/` with the Codex file layout (fact 65); Windows: the real `%USERPROFILE%\.openinterpreter` |
| Grok CLI (superagent-ai) | `grok` | `install.sh` of `superagent-ai/grok-cli`; builds for darwin-arm64, linux-x64 and windows-x64 only (fact 61) | not checked | none in the first 20 s |
| opencode 2 | `opencode` | npm `@opencode/cli`, or `curl -fsSL https://opencode.ai/v2/install \| bash`; the opencode 1 installer refuses 2.x (fact 63) | not checked | `~/.local/share/opencode/`, `~/.config/opencode/service.json`; a second process `serve --service` with no tty |

## The matrix

Each cell gives the work that exists, and where it was measured:

- "probe": a probe script exists.
- "CI": the probes workflow runs the probe on a runner with no agent
  installed.
- "real": the probe ran against live sessions on a real machine.

| Agent | Linux | macOS | Windows |
|---|---|---|---|
| Claude Code | probe, CI, real; scenarios `permission-dialog`, `dialog-states`, `plan-and-resume`, `first-run`; facts 23-25, 29, 31-35 | probe, CI; scenario `first-run` (CI); fact 29 | probe, CI; install layout (CI); scenario `first-run-windows` (CI); facts 47, 48, 51, 52 |
| Codex CLI | probe, CI; scenarios `approval`, `two-sessions`, `screens`, `deny`, `interrupt`, `daemon-life`, `first-run`; facts 19, 20, 26, 27, 29, 36-40 | probe, CI; scenario `first-run` (CI); fact 29 | probe, CI; install layout (CI); scenario `first-run-windows` (CI); facts 47, 48, 51, 52, 53 |
| agy | probe, CI; scenarios `turn-signals`, `deny-and-tools`, `continue`; facts 28, 41-45 | probe, CI | probe, CI |
| Cursor CLI | probe, CI; scenario `first-run`; first screen in the corpus; no login on the Linux server; fact 29 | probe, CI, real; scenario `first-run` (CI); facts 21, 22, 29 | probe, CI; install layout (CI); scenario `first-run-windows` (CI); facts 47, 48, 51, 52, 54 |
| opencode | probe, CI; scenario `first-run`; first screen in the corpus; fact 29 | probe, CI; scenario `first-run` (CI); fact 29 | probe, CI; install layout (CI); scenario `first-run-windows` (CI); facts 47, 48, 51, 52 |
| Gemini CLI, Copilot CLI, Qwen Code | scenario `first-run` (CI); first screens in the corpus; facts 30, 56 | scenario `first-run` (CI); fact 30 | install layout (CI); scenario `first-run-windows` (CI); facts 47, 48, 51, 52 |
| Aider | scenario `first-run` (CI); first screens in the corpus; fact 30 | scenario `first-run` (CI, through uv); fact 49 | scenario `first-run-windows` (CI) on x64; the uv install fails on arm64; fact 64 |
| Amp, Goose, Crush, Kimi Code, Continue, Droid, Cline, Kilo Code, Auggie, OpenHands | scenario `first-run` (CI); first screens in the corpus; facts 46, 50 | scenario `first-run` (CI); facts 46, 50, 57 | install layout and scenario `first-run-windows` (CI) for the npm agents and Kimi Code; facts 47, 48, 51, 52 (Amp fails on arm64); Goose and OpenHands: scenario `first-run-windows` (CI) on x64, fail on arm64 (fact 64) |
| Kiro CLI, Junie CLI, Qoder CLI, CodeBuddy Code, Letta Code, Neovate Code, iFlow CLI, Open Interpreter, opencode 2 | scenario `first-run` (CI) on x64 and arm64; first screens in the corpus; facts 61, 63, 65 | scenario `first-run` (CI) on arm64 and x64; fact 61 | scenario `first-run-windows` (CI) on x64 and arm64 (Kiro: the x64 MSI); fact 64 |
| Codebuff, Every Code | scenario `first-run` (CI) on x64 and arm64; first screens in the corpus; Every Code drew an empty pane on 3 of 6 labels; fact 61 | scenario `first-run` (CI); Every Code empty on 2 of 4 labels; fact 61 | scenario `first-run-windows` (CI) on x64; no arm64 build; fact 64 |
| Mistral Vibe, gptme | scenario `first-run` (CI) on x64 and arm64; first screens in the corpus; fact 61 | scenario `first-run` (CI); fact 61 | scenario `first-run-windows` (CI) on x64; the uv install fails on arm64; fact 64 |
| Grok CLI | scenario `first-run` (CI) on x64; no linux-arm64 build; first screen in the corpus; fact 61 | scenario `first-run` (CI) on arm64; no darwin-x64 build; fact 61 | not checked: bash installer only |
| Codex CLI with `CODEX_HOME` | scenario `first-run` as `codex-home` (CI); fact 62 | the same (CI); fact 62 | `first-run-windows` as `codex-home` (CI); fact 62 |

### Agents not added

Checked on 2026-10-31. These agents are not in the CI:

- Warp Oz (`oz`): Linux needs the Warp apt repository, macOS needs a
  Homebrew cask, and Windows has no standalone CLI.
- Plandex: `https://plandex.ai/install.sh` did not answer. The last
  release is cli/v2.2.1 of 2025-07-16.
- Mentat: the repository `AbanteAI/mentat` was not found.
- Trae Agent: it has no release and no npm or PyPI package.
- Roo Code: it has no CLI package. The releases are of the VS Code
  extension only.
- Zed: it has no agent CLI. Zed runs other agents through ACP.
- Charm Mods: the repository is archived. Crush is in the CI.

## Requests from tools

The tools asked for these signals on 2026-10-30. The answer gives the fact
or says what is left.

### aw

| # | Request | Answer |
|---|---|---|
| 1 | Cursor, macOS: a file signal for a wait on a permission dialog | Open. The kit step `--guided permission cursor` measures it on the Mac. |
| 2 | Codex: does a TUI hold its rollout file open? | Fact 26: no. In the default mode a shared daemon holds it. Fact 39: a `--no-daemon` TUI holds its own file. Fact 40: no table of `state_5.sqlite` links a TUI to its thread. |
| 3 | Cursor: `/new-chat` and `--resume`, old and new `store.db` | Open. Kit steps `new-chat` and `resume`, or a scenario with `CURSOR_API_KEY`. |
| 4 | Cursor: an end record after an interrupt | Open. Kit step `interrupt`. |
| 5 | Claude, Codex, agy: the files that each process holds open | Facts 25, 26, 28 (Linux). Claude: the task folder keeps the first session ID after `/clear` (fact 34). agy: the presence file is a flock lock (fact 44). macOS: the kit. |
| 6 | macOS: bring a tab to the front by its tty | Open. Kit step `front-tab` (Terminal, iTerm2). JetBrains IDEs: `terminals/macos.sh` checks for an AppleScript dictionary. |
| 7 | Cursor: the hash of the chats folder | Open. Needs a chat on a machine with a login. |
| 8 | Cursor, Linux and Windows: the open-file link | Open. Linux: needs a login. Windows: needs `handle.exe`. |
| 9 | Cursor editor agent workers | Open. The kit lists them on macOS. |
| 10 | Codex: the sandbox helper parent, and `resume` | Fact 26 (resume). The helper did not run on the Linux server (no namespaces). |
| 11 | agy, macOS: the process shape and the files | Fact 28 (Linux). macOS: the kit. |
| 12 | Windows: Cursor CLI and Codex in psmux | Open. The Windows probes and kit. |
| 13 | Windows: where the installs keep their version | Fact 47 (x64) and fact 48 (arm64). |
| 14 | An action that opens a permission dialog in the default mode | Claude: a file write with `--permission-mode default` (fact 24). Codex: a file write with `--sandbox read-only` (fact 27). agy: a file write (fact 28). Claude: `ls` and `sleep` open no Bash dialog; `mkdir` opens one (fact 33). |

### tg-bridge

| # | Request | Answer |
|---|---|---|
| 1 | Claude: a structured record of an open dialog | Fact 24: `PermissionRequest` gives the tool and the suggestions, not the labels. Fact 32: for a question, `PreToolUse` and `PermissionRequest` give the question, the header, and the label and description of each option. Fact 33: the digit of "No" depends on the dialog. Fact 31: the pid file names the kind of wait in `waitingFor`. |
| 2 | Claude: a signal that the folder-trust question waits | Fact 23: no `<pid>.json` before the answer. |
| 3 | Claude: an exact link from a pane to its session | Fact 23: `~/.claude/sessions/<pid>.json`. |
| 4 | agy: busy and turn-end signals that do not come from the screen | Fact 28: `PreInvocation`, `PostInvocation`, `Stop`. A deny and an Esc give no hook (fact 41). The `status` in `conversation_summaries.db` shows them (fact 45). |
| 5 | Codex: a signal for an interrupted or denied turn | Fact 27: `turn_aborted` in the rollout file. Fact 36: the digit 3 gives `turn_aborted`, as Esc does. Fact 37: Ctrl+C opens a task dialog. Fact 38: the `Interrupt` hook fires where `Stop` does not. |
| 6 | Cursor: does it load `.claude/settings.json` hooks? A login-state check | Login state: `cursor-agent status` prints `Not logged in` and starts no login (probe section 8). Hooks: open, needs a login. |
| 7 | Codex screens: busy, and the F2 Warnings view | Screens of 0.164.0 in `corpus/codex/screens/`, also the approval dialog, the screen after 3, and the dialog "Task is still running". |
| 8 | agy: `--continue` in an empty folder draws a box that looks idle | Fact 43: it is idle, with the same bytes as a new start. |
