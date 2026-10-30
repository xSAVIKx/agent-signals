# 028. The agy hooks and files of a turn

## Measured

2026-10-30, Antigravity CLI (agy) 1.4.7, on Linux (Debian 13, x64), in a
private tmux server with a throwaway `HOME` and a copied login. The
scenario `scenarios/agy/turn-signals.sh` set a hook for each of the six
events in `~/.gemini/config/hooks.json`, and recorded at each step the
screen, the open files of the process, and the record types of the
transcript. It read no content.
Measured on: real machine.

## What was measured

1. agy 1.4.7 knows six hook events: `SessionStart`, `PreInvocation`,
   `PostInvocation`, `PreToolUse`, `PostToolUse` and `Stop`. The file has
   one object for each hook group:
   `{"<group>": {"<event>": [{"type": "command", "command": "...", "timeout": 10}]}}`.
2. The hooks fired in this order:

   | Step | Hooks |
   |---|---|
   | The process starts | none |
   | The first prompt | `SessionStart`, then `PreInvocation` |
   | A file dialog opens ("Allow creation of this file?") | none |
   | Esc on the dialog | none |
   | The next prompt | `PreInvocation` |
   | The turn ends | `PostInvocation`, then `Stop` |

   `PreToolUse` and `PostToolUse` did not fire for the file write, with
   the hook shape of item 1.
3. Each payload has `conversationId`, `transcriptPath`,
   `artifactDirectoryPath`, `workspacePaths`, `lastUserInput` and
   `modelName`. `PreInvocation` and `PostInvocation` add `invocationNum`
   and `initialNumSteps`. `Stop` adds `executionNum`, `fullyIdle`
   (`true`), `terminationReason` (`NO_TOOL_CALL`) and `error` (empty).
   The hook process has `ANTIGRAVITY_CONVERSATION_ID` in its environment.
4. From the first prompt until the process exits, the process holds these
   files open:
   - `~/.gemini/antigravity-cli/conversations/<conversation id>.db`, with
     its `-wal` and `-shm` files.
   - `~/.gemini/antigravity-cli/presence/<conversation id>.lock`.
   Before the first prompt it holds neither file.
5. The transcript is
   `~/.gemini/antigravity-cli/brain/<conversation id>/.system_generated/logs/transcript.jsonl`.
   Each turn added a `USER_INPUT` record and a `PLANNER_RESPONSE` record.
   Esc on the dialog added no record.
6. A new install shows a wizard: a colour page, then a terms page. The
   terms page has a box, checked by default, that agrees to the collection
   of interaction data. The scenario clears it. Down, then Right, selects
   "Done".

## Mechanism

A reader can link a process to its conversation with no screen: the
conversation ID is in the names of the open `presence` and `conversations`
files. `PreInvocation` shows the start of a turn, and `PostInvocation` or
`Stop` shows its end.

An Esc gives no hook and no transcript record. A reader that waits for
`Stop` after an Esc waits for ever. Only the screen shows the end of that
turn.

## Incident

tg-bridge has only screen rules for agy. agy 1.4.7 `--continue` in an
empty folder draws an empty box that looks idle.

## Screens

None.

## Not measured

- A hook shape with a `matcher` for `PreToolUse` and `PostToolUse`.
- "2. No, deny creation" instead of Esc.
- Whether the `presence` lock is an advisory lock (`flock`) that a reader
  can test.
- `--continue` and `--conversation <id>`.
- macOS and Windows.
