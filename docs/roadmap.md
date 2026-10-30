# Roadmap

The agents to cover, in order, and the state of each cell of the matrix.
Updated 2026-10-30, second round.

## Order

1. The agents that aw and tg-bridge read now: Claude Code, Codex CLI,
   Antigravity CLI (agy), Cursor CLI.
2. opencode, Gemini CLI and GitHub Copilot CLI: CLI agents with many users
   that a tool can drive in a terminal.
3. Other terminal agents: Aider, Goose, Amp, Crush, Qwen Code, Kiro CLI,
   Factory Droid, Cline CLI, Continue CLI.

## The agents

`not checked` means that nobody in this project ran or read it yet.

| Agent | Command | Install | Login for CI | State folders |
|---|---|---|---|---|
| Claude Code | `claude` | npm `@anthropic-ai/claude-code` (fact 29) | `CLAUDE_CODE_OAUTH_TOKEN` or `ANTHROPIC_API_KEY` (not checked in CI) | `~/.claude/` (`sessions/`, `projects/`), `/tmp/claude-<uid>/` |
| Codex CLI | `codex` | standalone install (seen: the version is in the package path); npm `@openai/codex` (fact 29) | `OPENAI_API_KEY` through `codex login --with-api-key` (from `codex login --help`) | `~/.codex/` (`sessions/`, `thread-writer-locks/`, `packages/`) |
| Antigravity CLI | `agy` | not checked | not known: OAuth in a browser; no key login found | `~/.gemini/antigravity-cli/`, `~/.gemini/config/` |
| Cursor CLI | `cursor-agent`, `agent` | `curl https://cursor.com/install \| bash` (fact 29) | `CURSOR_API_KEY` (from `cursor-agent --help`) | `~/.cursor/` (`chats/`, `projects/`) |
| opencode | `opencode` | npm `opencode-ai` gives the 1.x line (fact 29) | provider keys through `opencode auth` (not checked) | `~/.local/share/opencode/` |
| Gemini CLI | `gemini` | npm `@google/gemini-cli` (fact 30) | `GEMINI_API_KEY` (not checked) | `~/.gemini/` (`tmp/`, `history/`, `projects.json`), shared with agy |
| GitHub Copilot CLI | `copilot` | npm `@github/copilot` (fact 30) | a GitHub token (not checked) | `~/.copilot/` (`session-state/<id>/inuse.<pid>.hold`) |
| Aider | `aider` | pipx `aider-chat` (fact 30; failed on macOS) | a provider key (not checked) | `~/.aider/` |
| Goose | `goose` | not checked | not checked | not checked |
| Amp | `amp` | npm (not checked) | not checked | not checked |
| Crush | `crush` | not checked | not checked | not checked |
| Qwen Code | `qwen` | npm `@qwen-code/qwen-code` (fact 30) | a provider key (not checked) | `~/.qwen/` |
| Kiro CLI | not checked | not checked | not checked | not checked |
| Factory Droid | `droid` | not checked | not checked | not checked |
| Cline CLI | `cline` | not checked | not checked | not checked |
| Continue CLI | `cn` | not checked | not checked | not checked |

## The matrix

Each cell gives the work that exists, and where it was measured. "probe" is
a probe script; "CI" means that the probes workflow runs it on a runner
with no agent installed; "real" means a run against live sessions on a
real machine.

| Agent | Linux | macOS | Windows |
|---|---|---|---|
| Claude Code | probe, CI, real; scenarios `permission-dialog`, `dialog-states`, `plan-and-resume`, `first-run`; facts 23-25, 29, 31-35 | probe, CI; scenario `first-run` (CI); fact 29 | probe, CI |
| Codex CLI | probe, CI; scenarios `approval`, `two-sessions`, `screens`, `deny`, `interrupt`, `daemon-life`, `first-run`; facts 19, 20, 26, 27, 29, 36-40 | probe, CI; scenario `first-run` (CI); fact 29 | probe, CI |
| agy | probe, CI; scenarios `turn-signals`, `deny-and-tools`, `continue`; facts 28, 41-45 | probe, CI | probe, CI |
| Cursor CLI | probe, CI; scenario `first-run`; no login on the Linux server; fact 29 | probe, CI, real; scenario `first-run` (CI); facts 21, 22, 29 | probe, CI |
| opencode | probe, CI; scenario `first-run`; fact 29 | probe, CI; scenario `first-run` (CI); fact 29 | probe, CI |
| Gemini CLI, Copilot CLI, Qwen Code | scenario `first-run` (CI); fact 30 | scenario `first-run` (CI); fact 30 | none |
| Aider | scenario `first-run` (CI); fact 30 | install failed | none |
| Others | none | none | none |

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
| 13 | Windows: where the installs keep their version | Open. The Windows probes list the install folders. |
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
