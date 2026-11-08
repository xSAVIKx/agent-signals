# 085. agy writes a file with no dialog

## Measured

2026-11-08 (UTC), agy 1.5.1, Claude Code 2.1.319 and Codex CLI 0.167.0 on
Linux (x64), in tmux, with the fake model of the Go package `fakemodel`
and a new throwaway home for each run. Measured on: real machine.

## What was measured

The fake model answered the prompt `Write a file please` with one call of
the file-write tool of the agent, for `agent-signals-write.txt` in the work
folder. It answered `Write outside PATH` with the same call for PATH, a
folder outside the work folder. The work folder was trusted at the start.

1. agy 1.5.1 with no `--mode` option: the `write_file` call wrote the file
   in the work folder. agy showed `Edited 1 file` and no dialog.
2. agy 1.5.1 with `--mode default`: the same result. The help of agy lists
   only `accept-edits`, `auto` and `plan` for `--mode`. agy started with
   `default` and showed no error.
3. agy 1.5.1, `Write outside PATH`: the `write_file` call wrote PATH outside
   the work folder, with no dialog.
4. Claude Code 2.1.319, permission mode `default`: the `Write` call showed
   the dialog `Do you want to create agent-signals-write.txt?` with three
   options. For PATH outside the work folder, option 2 also offered to
   allow access to the folder of PATH for the session.
5. Codex CLI 0.167.0, `approval_policy = "on-request"` and
   `sandbox_mode = "workspace-write"`: the `apply_patch` call (a custom tool
   call) showed the dialog `Would you like to make the following edits?`
   with the description `command failed; retry without sandbox?`. The
   result was the same in the work folder and outside it.

## Mechanism

Not known for agy. The fake home has no agy settings file other than
`onboarding.json`. agy 1.4.5 asks before a shell command (fact 004).

For Codex, the description says that the sandbox refused the write first.
The host of the measurement runs the agents under a systemd unit that
limits namespaces. Thus the Codex dialog in item 5 can come from the host,
not from the approval policy.

## Incident

None. The tg-bridge project asked for the write texts of the fake model to
test the approval of a file write.

## Screens

None.

## Not measured

- An agy settings file or a permission rule `write_file(<path>)`.
- agy with a real model or a real gateway.
- Codex on a host where its sandbox works.
- macOS and Windows.
