# 030. The first start of Gemini CLI, Copilot CLI, Qwen Code and Aider

## Measured

2026-10-30, the scenario `scenarios/first-run.sh <agent> <command>` in the
scenarios workflow (run 41127387845), with a throwaway `HOME`, no login and
no key. Each agent was installed on the runner by the workflow:

| Agent | Version | Install |
|---|---|---|
| Gemini CLI | 0.66.0 | npm `@google/gemini-cli` |
| GitHub Copilot CLI | 1.0.105 | npm `@github/copilot` |
| Qwen Code | 0.26.4 | npm `@qwen-code/qwen-code` |
| Aider | 0.86.2 | pipx `aider-chat` (Linux only) |

Measured on: CI runner ubuntu-latest (x64) and CI runner macos-latest
(arm64). Gemini CLI, Copilot CLI and Qwen Code gave the same screens and
files on both. The Aider install failed on macOS: pip could not build
`numpy==1.24.3`.

## What was measured

1. Copilot CLI asks "Confirm folder trust" before a login, with
   "1. Yes", "2. Yes, and remember this folder for future sessions" and
   "3. No (Esc)". It runs as `node .../bin/copilot` with a native child
   `.../@github/copilot-<os>-<cpu>/copilot`. The child holds
   `~/.copilot/session-state/<session id>/inuse.<pid>.hold` open, where
   `<pid>` is its own pid. It also writes `~/.copilot/config.json`,
   `open-sessions-state.json` and `logs/process-<time>-<pid>.log`.
2. Gemini CLI asks "Do you trust the files in this folder?" before a login,
   with "1. Trust folder (<name>)", "2. Trust parent folder (<name>)" and
   "3. Don't trust". It runs as two node processes (the second with
   `--max-old-space-size`). It writes below `~/.gemini`: `tmp/<folder
   name>/`, `history/<folder name>`, `projects.json`, `state.json` and
   `installation_id`. It held no file below `~/.gemini` open.
3. Qwen Code first shows a choice of the provider ("Choose a built-in
   provider and connect with an API key", "Custom Provider"). It runs as
   one node process and holds `~/.qwen/settings.json`,
   `model-registry.json` and `installation_id` open.
4. Aider first asks "No git repo found, create one to track aider's changes
   (recommended)? (Y)es/(N)o [Yes]:". It runs as a Python process. It
   writes `~/.aider/analytics.json` and `caches/versioncheck`.

## Mechanism

Copilot CLI gives an exact link from a process to its session in the name
of a file that the process holds open: the session ID is the folder, and
the pid is in the file name.

Gemini CLI and agy (fact 28) both use `~/.gemini`. agy keeps its files in
`~/.gemini/antigravity-cli` and `~/.gemini/config`. A reader must not mix
them.

## Incident

None.

## Screens

None. The screens are in the log of the run, not in the corpus.

## Not measured

- The screens after a login, and any turn.
- Whether the Copilot `inuse.<pid>.hold` file stays the same after a new
  session in the same process.
- Aider on macOS.
- Windows.
