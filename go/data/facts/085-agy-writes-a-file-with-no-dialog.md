# 085. agy writes a file with no dialog

## Measured

2026-11-08 (UTC), agy 1.5.1, Claude Code 2.1.319 and Codex CLI 0.167.0 on
Linux (x64), with the agent kit (`--home fixture`, backend tmux) and the
fake model of the kit. Each step ran one time. Measured on: real machine.

This text replaces the first text of this fact (corpus-v0.17.0). That text
came from a manual run that did not record the settings in effect.

## Conditions

The kit steps `write-AGENT-MODE` and `write-outside-AGENT-MODE`
(`probes/agent/steps.tsv`) recorded the conditions of each run:

- A new home that the kit made, with only the files of the fake model:
  - agy: `onboarding.json`, and no settings file.
  - Claude Code: `settings.json` with `defaultMode: default`, and
    `.claude.json`.
  - Codex: `config.toml` with `approval_policy = "on-request"` and
    `sandbox_mode = "workspace-write"`.
- A new, empty work folder, with no project settings file in it or in a
  folder above it.
- A clean environment: only HOME, PATH, TERM, USER, LANG, and the
  variables of the fake model and of the step.
- Machine files:
  - Claude Code: `/etc/claude-code/managed-settings.json` was present. It
    has only the keys `attribution` and `env`, and `env` sets no variable
    of Claude Code.
  - agy and Codex: no machine file.
- The Codex sandbox did not start on this host:
  `bwrap: No permissions to create a new namespace`.

The fake model answers the prompt with one call of the file-write tool:
`write_file` (agy), `Write` (Claude Code) or `apply_patch` (Codex). It
answers a review request with "allow", or with "deny" in the `-deny`
steps.

## What was measured

In the table:

- "dialog": the agent asked before the write.
- "written": the file was there at the end of the step.
- "work" is a write in the work folder. "outside" is a write to a new
  folder outside the work folder.

| Agent and mode (arguments) | Work | Outside |
|---|---|---|
| agy, no `--mode` option | written, no dialog | written, no dialog |
| agy `--mode accept-edits` | written, no dialog | written, no dialog |
| agy `--mode auto` | written, no dialog | written, no dialog |
| agy `--mode plan` | written, no dialog | not run |
| agy `--dangerously-skip-permissions` | written, no dialog | not run |
| Claude Code `--permission-mode manual` | dialog | dialog |
| Claude Code `--permission-mode acceptEdits` | written, no dialog | dialog |
| Claude Code `--permission-mode auto` | written, no dialog, no review | review allow: written, no dialog |
| Claude Code `--permission-mode auto`, review deny | not run | not written, no dialog |
| Claude Code `--permission-mode dontAsk` | not written, no dialog | not run |
| Claude Code `--permission-mode plan` | dialog | not run |
| Codex `-a on-request -s workspace-write` | dialog | dialog |
| Codex `-a never -s workspace-write` | not written, no dialog | not written, no dialog |
| Codex `--approve-for-me` | review allow: written, no dialog | review allow: written, no dialog |
| Codex `--approve-for-me`, review deny | not written, no dialog | not written, no dialog |
| Codex `-a on-request -s read-only` | dialog | not run |
| Codex `--dangerously-bypass-approvals-and-sandbox` | written, no dialog | not run |

More results:

1. agy 1.5.1 sent no review request in any mode. The fake model got only
   a title request, the `write_file` call, and the reply after it.
2. agy 1.5.1 in `--mode plan` ran the `write_file` call. The mode text in
   the agy binary says that plan mode does "research and plan without
   making changes".
3. In the agy log of a manual run (not a kit step) with no `--mode`
   option and no settings file, the line was
   `CLI settings initialized: permissions=<nil>,
   toolPermission=request-review`.
4. The Claude Code dialog was `Do you want to create
   agent-signals-write.txt?`. In plan mode, Claude Code showed the same
   dialog.
5. Claude Code in auto mode sent no review request for the write in the
   work folder. For the write outside it, Claude Code sent one review
   request (allow), or two (deny: stage 1 and stage 2), and then showed
   `Blocked by auto mode`.
6. The Codex dialog in `on-request` mode said `command failed; retry
   without sandbox?`. In `read-only` mode it said `Apply proposed file
   edits`.
7. With `--permission-mode bypassPermissions`, Claude Code 2.1.319 shows
   a warning before its idle screen. The warning says "By proceeding, you
   accept all responsibility" and has the options `No, exit` and
   `Yes, I accept`. The kit does not accept it, so the kit has no step
   for this mode.

## Mechanism

Not known for agy. The agy 1.5.1 binary describes its default mode as
"Ask before edits and commands, per your permission settings". With no settings file,
it did not ask before `write_file`. agy 1.4.5 asks before a shell command
(fact 004).

The Codex results for `on-request` and `never` come from the failed
sandbox. Codex first runs the edit in its sandbox. When the sandbox fails:

- in `on-request` mode, Codex asks to run the edit with no sandbox;
- in `never` mode, Codex gives the error back to the model.

On a host where the sandbox works, these two rows can differ.

The review rows show how the agent acts on a verdict. They do not show
what a real review decides: that is the decision of a model.

## Incident

None. The tg-bridge project asked whether agy 1.5.1 asks before a file
write.

## Screens

None.

## Not measured

- An agy settings file, or a permission rule `write_file(<path>)`.
- agy, Claude Code and Codex with a real model and a real login.
- Codex on a host where its sandbox works.
- Claude Code auto mode with the review of the API server
  (`CLAUDE_CODE_AUTO_MODE_SERVER` not set).
- The backends pty, conpty and psmux, and macOS and Windows.
- More than one run of each step.
