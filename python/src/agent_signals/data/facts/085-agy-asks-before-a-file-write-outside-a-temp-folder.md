# 085. agy asks before a file write outside a temp folder

## Measured

2026-11-08 (UTC), agy 1.5.1, Claude Code 2.1.319 and Codex CLI 0.167.0 on
Linux (x64), with the agent kit (`--home fixture`, backend tmux) and the
fake model of the kit. Each step ran one time. Measured on: real machine.

### History of this fact

- The first text (corpus-v0.17.0) said "agy writes a file with no
  dialog". It came from a manual run that did not record the settings in
  effect.
- The second text (corpus-v0.18.0) came from the kit, but the run folder
  was below `/tmp`. So the work folder and the outside folder were in a
  temp folder, and agy did not ask. The tg-bridge project measured a
  dialog for a write outside the work folder, in a folder that was not a
  temp folder. That result showed the fault.
- This text comes from a kit run with the run folder outside the temp
  folders. The kit now records whether each folder is in a temp folder.

## Conditions

The kit steps `write-AGENT-MODE` and `write-outside-AGENT-MODE`
(`probes/agent/steps.tsv`) recorded the conditions of each run:

- The work folder and the outside folder were not in a temp folder
  (`work folder in a temp folder: no`, `outside folder in a temp folder:
  no`).
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

- "dialog": the agent asked before the write. The step then pressed Esc,
  and no file was written.
- "written": the file was there at the end of the step.
- "work" is a write in the work folder. "outside" is a write to a new
  folder in the run folder, outside the work folder.

| Agent and mode (arguments) | Work | Outside |
|---|---|---|
| agy, no `--mode` option | dialog | dialog, `Reason: outside workspace` |
| agy `--mode accept-edits` | written, no dialog | dialog, `Reason: outside workspace` |
| agy `--mode auto` | dialog | dialog, `Reason: outside workspace` |
| agy `--mode plan` | dialog | not run |
| agy `--dangerously-skip-permissions` | written, no dialog | not run |
| agy `--settings {"permissions":{"ask":["write_file(*)"]}}` | dialog | dialog, `Reason: outside workspace` |
| agy `--settings {"toolPermission":"strict"}` | dialog | dialog, no reason line |
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

1. The agy dialog in the work folder:
   `Allow creation of this file?` with `1. Yes, allow creation` and
   `2. No, deny creation`.
2. The agy dialog outside the work folder adds the line
   `Reason: outside workspace` and the option
   `2. Yes, and always allow non-workspace access`. With
   `toolPermission` `strict`, the dialog outside the work folder had
   neither.
3. In the earlier run with the work folder below `/tmp`, agy 1.5.1
   wrote with no dialog in each mode, in the work folder and outside it.
   The recorded conditions of the agy steps in the two runs differ only
   in the place of the run folder.
4. agy 1.5.1 sent no review request in any mode. In `--mode plan`, the
   prompt line showed `/plan` before the text.
5. The Claude Code dialog was `Do you want to create
   agent-signals-write.txt?`. In plan mode, Claude Code showed the same
   dialog.
6. Claude Code in auto mode sent no review request for the write in the
   work folder. For the write outside it, Claude Code sent one review
   request (allow), or two (deny: stage 1 and stage 2), and then showed
   `Blocked by auto mode`.
7. The Codex dialog in `on-request` mode said `command failed; retry
   without sandbox?`. In `read-only` mode it said `Apply proposed file
   edits`.
8. With `--permission-mode bypassPermissions`, Claude Code 2.1.319 shows
   a warning before its idle screen. The warning says "By proceeding, you
   accept all responsibility" and has the options `No, exit` and
   `Yes, I accept`. The kit does not accept it, so the kit has no step
   for this mode.

## Mechanism

agy 1.5.1 gives access to temp folders with no question. The tg-bridge
project reports that the agy documentation of the default permission
preset says so. This project did not read that documentation. These runs
agree with it: the place of the run folder alone
changed the agy result. The kit did not measure which folders count as
temp folders for agy.

The tg-bridge project measured no dialog for a write in the work folder
with the real home of the operator and no options. These runs, with no
agy settings file, showed a dialog. The difference is not known. The
settings of that real home were not recorded.

The Codex results for `on-request` and `never` come from the failed
sandbox. Codex first runs the edit in its sandbox. When the sandbox fails:

- in `on-request` mode, Codex asks to run the edit with no sandbox;
- in `never` mode, Codex gives the error back to the model.

On a host where the sandbox works, these two rows can differ.

The review rows show how the agent acts on a verdict. They do not show
what a real review decides: that is the decision of a model.

## Incident

The second text of this fact was wrong for agy (see History). The
tg-bridge project uses `--settings
{"permissions":{"ask":["write_file(*)"]}}` for its agy ask mode.

## Screens

None.

## Not measured

- Which folders agy counts as temp folders, and `TMPDIR`.
- agy with a settings file in the home, and the real home of an
  operator.
- agy, Claude Code and Codex with a real model and a real login.
- Codex on a host where its sandbox works.
- Claude Code auto mode with the review of the API server
  (`CLAUDE_CODE_AUTO_MODE_SERVER` not set).
- The backends pty, conpty and psmux, and macOS and Windows.
- More than one run of each step.
