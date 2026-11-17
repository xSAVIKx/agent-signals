# 095. A trusted Codex user hook runs in every folder

## Measured

2026-11-17, Codex CLI 0.169.0, on Linux. The TUI ran as
`codex --no-daemon -s danger-full-access -a on-request` in a private tmux
server, in a new git repository for each run, with no
`--dangerously-bypass-hook-trust`. The hooks were command hooks for
`UserPromptSubmit` and `Stop`. tg-bridge made the measurement and sent the
results to this repository. Measured on: real machine.

## What was measured

1. Codex reads user hooks from `~/.codex/hooks.json`. The file has the
   format of a project file:
   `{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "..."}]}]}}`
   (fact 038).
2. A user hook also needs a review. The first start showed this dialog,
   and no hook ran before an answer:

   ```
     Hooks need review
     2 hooks are new or changed.
     Hooks can run outside the sandbox after you trust them.

   › 1. Review hooks
     2. Trust all and continue
     3. Continue without trusting (hooks won't run)

     enter confirm · esc skip
   ```

3. `2. Trust all and continue` writes one table for each hook into
   `~/.codex/config.toml`:

   ```
   [hooks.state."<home>/.codex/hooks.json:stop:0:0"]
   trusted_hash = "sha256:..."
   ```

   The key holds the hooks file, the event and two indexes. It holds no
   project.
4. A trusted user hook runs in each later session, also in a different
   folder. No review dialog shows.
5. A project file `.codex/hooks.json` gets its own review dialog
   ("1 hook is new or changed."). After `3. Continue without trusting`, the
   trusted user hooks ran (`UserPromptSubmit` and `Stop`), and the project
   hook did not run.
6. The folder trust dialog of 0.169.0:

   ```
     Folder access
     Trust this folder? Codex can read, edit, and run files here, ...

   › 1. Trust and continue
     2. Back to Agent Command Center

     enter continue · esc back
   ```

   `-c 'projects."<dir>".trust_level="trusted"'` did not skip the dialog.
   `1. Trust and continue` writes `[projects."<dir>"]` into
   `~/.codex/config.toml`.
7. The idle screen of 0.169.0 has a new line below the box,
   `← for agents · ? for shortcuts`. It is below `› Ask Codex to do
   anything` and the line with the model and the work folder.
8. The `UserPromptSubmit` payload has `prompt`. The `Stop` payload has
   `last_assistant_message`. `permission_mode` was `default`.

## Mechanism

Codex keeps the hook trust for each hook, not for each project. The key
names the hooks file, so one trust of a user hook covers all folders. A
project hook needs its own trust. When a user does not trust a project
hook, the user hooks still run.

A tool that installs a user hook must expect the review dialog at the
next start. After one trust, the hook runs in each folder. A tool that
waits for the input box must also handle the review dialog and the
folder trust dialog (fact 020).

## Incident

None.

## Screens

None.

## Not measured

- Whether a change to the hook script, with the same `hooks.json`, needs a
  new review.
- The input of the `trusted_hash` digest.
- The default daemon mode: all runs used `--no-daemon`.
- The OS version, macOS and Windows.
