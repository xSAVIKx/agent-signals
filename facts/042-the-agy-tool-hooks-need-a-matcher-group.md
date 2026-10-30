# 042. The agy tool hooks need a matcher group

## Measured

2026-10-30, Antigravity CLI (agy) 1.4.7, on Linux (Debian 13, x64). The
hook shape comes from the documentation text in the agy binary
(`strings -n 6` on the installed binary, the section "Lifecycle Hooks
(`hooks.json`)"). The scenario `scenarios/agy/deny-and-tools.sh` ran two
times in a private tmux server with a throwaway `HOME` and a copied login,
with hooks in `~/.gemini/config/hooks.json`. Each hook printed nothing.
The first run used an earlier copy of the script, with a different list of
tool names in the third matcher (item 2).
Measured on: real machine.

## What was measured

1. The documentation in the binary says that `PreToolUse` and
   `PostToolUse` take a group with a `matcher` regex and a `hooks` list.
   The other four events take a flat list of handlers. The shape is:

   ```json
   {"<name>": {"PreToolUse": [{"matcher": "*", "hooks": [{"type": "command", "command": "...", "timeout": 10}]}]}}
   ```

2. With this shape, `PreToolUse` and `PostToolUse` fired. The matchers
   `"*"` and `""` fired in both runs. The matcher `"write_file|read_file"`
   fired in the second run (the first run did not have it). The matchers
   `"write_to_file|view_file|run_command|code_action|list_dir"` (first run)
   and `"write_to_file|view_file|code_action|list_dir"` (second run) did
   not fire. In fact 28, the flat shape with no group did not fire.
3. The tool names were `write_file` (the file write) and `read_file` (a
   file read).
4. The payload keys:

   | Event | Keys |
   |---|---|
   | `PreToolUse` | `artifactDirectoryPath`, `conversationId`, `lastUserInput`, `modelName`, `stepIdx`, `toolCall`, `transcriptPath`, `workspacePaths` |
   | `PostToolUse` | the keys of `PreToolUse`, and `error` (empty for a tool that ran) |

   `toolCall` has `name` and `args`. The `args` keys of `write_file` were
   `Content`, `Overwrite` and `Path`. The `args` key of `read_file` was
   `Path`. The hook process had `ANTIGRAVITY_CONVERSATION_ID` in its
   environment.
5. The order of the hooks:

   | Turn | Hooks |
   |---|---|
   | A read with no dialog | `PreInvocation`, `PreToolUse`, `PostToolUse` (about 0.1 s later), `PostInvocation`, `PreInvocation`, `PostInvocation`, `Stop` |
   | A write, "1" on the dialog | `PreInvocation`, `PreToolUse` (before the dialog draws), `PostToolUse` (after the answer), `PostInvocation`, `PreInvocation`, `PostInvocation`, `Stop` |
   | A write, "2" or Esc on the dialog | `PreInvocation`, `PreToolUse`, then nothing (fact 41) |

6. A hook that printed nothing did not change the dialog. The dialog drew,
   and the read ran with no dialog.
7. `Stop` came with `terminationReason` `NO_TOOL_CALL` and `fullyIdle`
   `true` for each turn that ended normally.

## Mechanism

The documentation in the binary says that a `PreToolUse` hook can print a
`decision` (`allow`, `deny`, `ask`, `force_ask`). An observer must print
nothing, or `ask`, so that it does not answer the dialog for the operator.
The scenario measured only "nothing".

`PreToolUse` with no `PostToolUse` means that a tool runs or that a dialog
waits. The hooks do not tell these two apart. The screen does.

## Incident

None recorded.

## Screens

`agy/file-permission-v1-4-7`.

## Not measured

- A hook that prints a `decision`.
- Other tools: a shell command (`run_command` in the documentation), a
  web search, an MCP tool.
- A matcher that is not a valid regex.
- `.agents/hooks.json` in the work folder, and hooks in a plugin.
- macOS and Windows. Other agy versions.
