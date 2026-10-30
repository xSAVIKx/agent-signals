# 029. The first start of each agent with no login

## Measured

2026-10-30, the scenario `scenarios/first-run.sh` in the scenarios
workflow (run 41126049221), with a throwaway `HOME`, no login and no key.
Each agent was installed on the runner by the workflow:

| Agent | Version | Install |
|---|---|---|
| Claude Code | 2.1.314 | npm `@anthropic-ai/claude-code` |
| Codex CLI | 0.166.0 | npm `@openai/codex` |
| Cursor CLI | 2026.10.22-27dcf5f | `curl https://cursor.com/install` |
| opencode | 1.19.5 | npm `opencode-ai` |

Measured on: CI runner ubuntu-latest (x64) and CI runner macos-latest
(arm64). The two runners gave the same screens and the same files.

## What was measured

1. Claude Code first shows "Choose the text style that looks best with your
   terminal", with "Dark mode" selected. Below `~/.claude` it made only
   `sessions/<pid>.<hex>.key`, `backups/`, `cache/changelog.md`, and
   `~/.claude.json`. There is no `sessions/<pid>.json`, as before the trust
   answer in fact 23.
2. Codex CLI first shows "Choose how you want to use Codex." with
   "1. Sign in with ChatGPT", "2. Sign in with Device Code", "3. Use an
   OpenAI API key" and "4. Use Amazon Bedrock". Only the TUI runs: no
   app-server daemon starts before a login. The TUI holds the SQLite files
   `state_5`, `logs_2`, `goals_1`, `memories_1` and `queue_1` below
   `~/.codex` open. It made about 5,500 files in `~/.codex/.tmp/plugins`.
   The npm install runs the binary from
   `node_modules/@openai/codex/node_modules/@openai/codex-<os>-<cpu>/vendor/<target>/bin/`.
3. Cursor CLI shows "Press any key to log in...". It made
   `~/.cursor/agent-cli-state.json`, `cli-config.json` and
   `statsig-cache.json`. The process is
   `~/.local/bin/cursor-agent --use-system-ca ~/.local/share/cursor-agent/versions/<version>/index.js`.
4. opencode 1.19.5 holds `~/.local/share/opencode/opencode.db` (with
   `-wal` and `-shm`) and `log/opencode.log` open. It made a Node project in
   `~/.config/opencode` with about 3,600 files in `node_modules`. Its screen
   says "/update to upgrade to OpenCode 2.0". The npm package `opencode-ai`
   is the 1.x line; the operator's server runs opencode 2.1.4.

## Mechanism

A tool that sees a new process of one of these agents with no session file
can show "waits for setup or login" in place of "idle". The screens above
are the first screens a person sees after an install.

## Incident

None.

## Screens

None. The screens are in the log of the run, not in the corpus.

## Not measured

- agy: no install command for a runner is known.
- Windows.
- The screens after the first choice (theme, sign-in method).
- opencode 2.x on a runner.
