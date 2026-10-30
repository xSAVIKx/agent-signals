# 023. The Claude pid file shows a dialog wait

## Measured

2026-10-30, Claude Code 2.1.314, on Linux (Debian 13, x64), in a private
tmux server with a throwaway `HOME` and a copied login. The scenario
`scenarios/claude/permission-dialog.sh` read the file at each step and
every 2 s while a dialog waited. Live sessions of 2.1.310 and 2.1.314 on
the same machine gave the field list and the `busy` value.
Measured on: real machine.

## What was measured

1. Each interactive process writes `~/.claude/sessions/<pid>.json`. Its
   fields are `pid`, `sessionId`, `cwd`, `startedAt`, `procStart`,
   `version`, `kind` (`interactive`), `entrypoint` (`cli`), `status`,
   `statusUpdatedAt`, `updatedAt`, `name`, `tmux`, `messagingSocketPath`,
   and others.
2. `status` had four values:

   | Value | When |
   |---|---|
   | `idle` | The input box waits for a prompt. |
   | `busy` | A turn runs. |
   | `waiting` | A permission dialog waits. |
   | `shell` | Seen in a live session of 2.1.310 that ran shell commands for a long time. The cause is not measured. |

   The value changed to `waiting` when the dialog opened. It stayed
   `waiting` for the whole wait (5 reads in 10 s). It changed to `idle`
   after an answer: "1. Yes", and also Esc.
3. `sessionId` is the `session_id` of the hooks. The transcript file name
   holds the same ID. After `/clear`, `sessionId` changed to the ID of the
   new session.
4. `tmux` has the form `<session>:@<window id>.%<pane id>` when the process
   runs in tmux. It is empty when the process does not have `TMUX` and
   `TMUX_PANE` in its environment.
5. While the folder-trust question waits, there is no `<pid>.json`. Only
   `~/.claude/sessions/<pid>.<64 hex characters>.key` exists. `<pid>.json`
   appears after the answer. No hook fires before the answer.

## Mechanism

A reader can link a process to its session with no screen: it takes the
pid of the pane process, reads `<pid>.json`, and gets `sessionId` and
`status`. `claude --resume <sessionId>` then resumes that exact session,
not the last session of the folder.

A process with a `.key` file and no `.json` file waits on the trust
question, or has just started.

## Incident

None. tg-bridge and aw asked for these signals: a signal for the trust
wait, an exact link from a pane to its session, and a dialog wait with no
screen parse.

## Screens

None.

## Not measured

- Whether `status` is `waiting` for other dialogs: a question from the
  agent, an MCP dialog, a plan approval.
- How long `.key` exists alone after a normal start, with a folder that is
  already trusted.
- macOS and Windows.
- What happens to `<pid>.json` after a crash.

## 2026-10-30, 2.1.314: more waits, and a resume

Measured on: real machine. Scenarios `scenarios/claude/dialog-states.sh`
(three runs) and `scenarios/claude/plan-and-resume.sh` (one run), on the
same Linux machine. They read the file every 1 s while each wait lasted.

1. `status` is `waiting` also for a question from the agent, a Bash
   command dialog, and a plan approval. A field `waitingFor` is in the
   file while `status` is `waiting`: `input needed` for a question, and
   `permission prompt` for a tool dialog or a plan approval (fact 031).
2. `shell` means: no turn runs, and a background shell of the session
   still runs. A background `sleep 30` gave `busy`, then `shell` for
   26 to 27 s, then `busy` for the turn that the task notification starts,
   then `idle` (fact 031). The `shell` row of the table above, "The cause
   is not measured", is superseded.
3. After "No" on a Bash dialog, `status` was `idle` from 1 s after the
   key (fact 033).
4. After `/exit`, `<pid>.json` and the `.key` file were gone. A new
   process with `claude --resume <sessionId>` wrote a new `<pid>.json`
   with a new pid and the same `sessionId` (fact 035).
