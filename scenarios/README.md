# Scenarios

A scenario starts an agent, sends scripted keys, and records the signals:
screens, hook payloads, session files, and open files. A probe only reads
sessions that already run (see `probes/README.md`). A scenario makes its
own session.

Path: `scenarios/<agent>/<name>.sh`. Shared functions: `scenarios/lib.sh`.

## Rules for a scenario

1. It runs the agent in a throwaway `HOME` and a private tmux server
   (`tmux -L`). The cleanup trap kills the server and deletes the
   throwaway folder.
2. It copies a login into the throwaway `HOME` only with `copy_login`.
   `copy_login` refuses a login that is near its expiry, because a token
   refresh in the copy could make the original login fail.
3. An API key goes to the agent through a file that only the owner can
   read, never through the command line.
4. Its prompts are neutral text that can be public. A prompt that must
   open a permission dialog asks for a file write in the throwaway folder.
5. Its output goes to `out/`, which git ignores. Do not commit it. Send it
   through the scrub before it goes into a CI log or an artifact.
6. The header of the script says what it needs, what it costs, and which
   questions it answers.

## Scenarios

CI (`.github/workflows/scenarios.yml`) runs `first-run.sh` for each agent
on 10 Linux and macOS labels, in two agent groups, and
`windows-installs.ps1` and `first-run-windows.ps1` on windows-2022,
windows-2025 and windows-11-arm, in two agent groups, by hand and once a
week. It needs no secret. A start by hand can select one job with the
input `job`.

| Scenario | Agent | Facts |
|---|---|---|
| `first-run.sh <agent> [command]` | each agent, no login | 29, 30, 46, 49, 50, 56, 57 |
| `windows-installs.ps1 NAME=CMD[=NPMPKG] ...` | each agent on Windows, not started | 47, 48 |
| `first-run-windows.py <agent> [command]` (through `first-run-windows.ps1`) | each agent on Windows, no login | 51, 52, 53, 54, 55 |
| `claude/permission-dialog.sh` | Claude Code | 23, 24 |
| `claude/dialog-states.sh` | Claude Code | 31, 32, 33, 34 |
| `claude/plan-and-resume.sh` | Claude Code | 31, 32, 35 |
| `codex/approval.sh` | Codex CLI | 26, 27 |
| `codex/two-sessions.sh` | Codex CLI | 26 |
| `codex/screens.sh` | Codex CLI | 20 (screens of 0.164.0) |
| `codex/deny.sh` | Codex CLI | 36, 38 |
| `codex/interrupt.sh` | Codex CLI | 37, 38 |
| `codex/daemon-life.sh` | Codex CLI | 39, 40 |
| `agy/turn-signals.sh` | Antigravity CLI | 28; superseded in part by 42 |
| `agy/deny-and-tools.sh` | Antigravity CLI | 41, 42, 44, 45 |
| `agy/continue.sh` | Antigravity CLI | 43, 44 |
