# 031. The Claude pid file names the wait and a background shell

## Measured

2026-10-30, Claude Code 2.1.314 with `--model haiku`, on Linux (Debian 13,
x64), in a private tmux server with a throwaway `HOME` and a copied login.
The scenarios `scenarios/claude/dialog-states.sh` (three runs) and
`scenarios/claude/plan-and-resume.sh` (one run) read
`~/.claude/sessions/<pid>.json` every 1 s while each wait lasted. They
kept one copy of the file for each status and recorded every hook payload.
Measured on: real machine.

## What was measured

1. The `status` field and a `waitingFor` field had these values:

   | Wait | `status` | `waitingFor` |
   |---|---|---|
   | The input box waits for a prompt | `idle` | not in the file |
   | A turn runs | `busy` | not in the file |
   | A question from the agent (`AskUserQuestion`) | `waiting` | `input needed` |
   | A Bash command dialog | `waiting` | `permission prompt` |
   | A plan approval (`ExitPlanMode`) | `waiting` | `permission prompt` |
   | The turn ended, and a background shell runs | `shell` | not in the file |

   `status` stayed `waiting` for each read of the wait: 10 reads in 10 s
   for each dialog. The `waitingFor` field is in the file only while
   `status` is `waiting`.
2. The prompt "Run the command sleep 30 with your Bash tool in the
   background ..." gave this order of `status` values, read every 1 s:
   `busy` for 2 to 4 s, `shell` for 26 to 27 s, `busy` for 2 s, then
   `idle`. This order was the same in the three runs. With `sleep 3`,
   `shell` lasted 1 to 2 s. So `shell` means: no
   turn runs, and a background shell of the session still runs. This
   explains the `shell` value of fact 023.
3. When the background shell ends, Claude Code starts a new turn by
   itself. That is the second `busy`. The hooks for that turn are
   `UserPromptSubmit`, whose `prompt` starts with `<task-notification>`,
   and then `Stop`. No key was sent for that turn.
4. The `Stop` payload has a `background_tasks` list. At the end of the
   turn that started the shell, it had one item with the keys `id`,
   `type` (`shell`), `status` (`running`), `description` and `command`.
   The `id` is the `backgroundTaskId` of the `PostToolUse` `tool_response`
   of that Bash call. At the end of the turn that the task notification
   started, the list was empty. `Stop` also has `session_crons` (an empty
   list in each run) and `stop_hook_active` (`false`).
5. After "1." on the plan approval, `status` was `waiting` for one more
   read (1 s), then `busy`, then `idle`.
6. The other fields of the file in 2.1.314: `peerProtocol`,
   `peerFeatures`, `pidDomain`, `asksForConvertedSkills`, `nameSource`
   and `nameSince`, next to the fields of fact 023.

## Mechanism

A reader can tell a question from a permission dialog with no screen:
`waitingFor` is `input needed` for a question, and `permission prompt`
for a tool dialog or a plan approval. The reader cannot tell a plan
approval from a tool dialog by the pid file.

A reader must not show `shell` as a wait for the operator. The agent
starts its next turn by itself when the shell ends. A reader that wants
the task list reads `background_tasks` from `Stop`.

## Incident

None. tg-bridge and aw asked which dialog waits, and what `shell` means.

## Screens

None.

## Not measured

- An MCP dialog, a question wizard of more than one question, and a
  dialog of a subagent.
- A background shell that runs while a turn also runs.
- A background shell that the operator stops, and a shell that fails.
- Whether `waitingFor` has other values.
- Other models, macOS and Windows.
