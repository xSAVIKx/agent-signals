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

| Scenario | Agent | Facts |
|---|---|---|
| `claude/permission-dialog.sh` | Claude Code | 23, 24 |
| `codex/approval.sh` | Codex CLI | 26, 27 |
| `codex/two-sessions.sh` | Codex CLI | 26 |
| `agy/turn-signals.sh` | Antigravity CLI | 28 |
