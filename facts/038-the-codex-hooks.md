# 038. The Codex hooks

## Measured

2026-10-30, Codex CLI 0.164.0 (standalone install,
x86_64-unknown-linux-musl), on Linux (Debian 13, x64), in the default
daemon mode, in a private tmux server with a throwaway `HOME` and a
copied login. `codex features list` and `strings` on the binary gave the
feature and the event names. The scenarios `scenarios/codex/deny.sh` and
`scenarios/codex/interrupt.sh` wrote `~/.codex/hooks.json` with one
command hook for each event (`codex_hooks` in `scenarios/lib.sh`). Each
hook wrote the time, the event and the sorted top-level keys of its
payload to a log. It wrote no values. Four runs.
Measured on: real machine.

## What was measured

1. `codex features list` shows `hooks  stable  true`. The binary holds
   these event names: `SessionStart`, `SessionEnd`, `UserPromptSubmit`,
   `PreModelRequest`, `PreToolUse`, `PermissionRequest`, `PostToolUse`,
   `PreCompact`, `PostCompact`, `SubagentStart`, `SubagentStop`,
   `Interrupt` and `Stop`. The file
   `{"hooks": {"<event>": [{"hooks": [{"type": "command", "command": "...", "timeout": 10}]}]}}`
   in `~/.codex/hooks.json` loaded all 13. The hooks list showed the
   source "User config - ~/.codex/hooks.json".
2. New hooks do not run until the user trusts them. The first start
   showed this dialog before the input box:

   ```
     Hooks need review
     13 hooks are new or changed.
     Hooks can run outside the sandbox after you trust them.

   › 1. Review hooks
     2. Trust all and continue
     3. Continue without trusting (hooks won't run)

     enter confirm · esc skip
   ```

   Here a digit only moves the selection; Enter confirms it. The trust
   wrote `~/.codex/config.toml` (42 bytes before, 2653 bytes after).
   Codex warned: "clamping SessionEnd hook timeout to 3s" and "clamping
   Interrupt hook timeout to 3s".
3. The payload keys of each event that fired:

   | Event | Keys |
   |---|---|
   | `SessionStart` | `cwd hook_event_name model permission_mode session_id source transcript_path` |
   | `UserPromptSubmit` | `cwd hook_event_name model permission_mode prompt session_id transcript_path turn_id` |
   | `PreModelRequest` | `cwd hook_event_name model session_id transcript_path turn_id` |
   | `PreToolUse` | `cwd hook_event_name model permission_mode session_id tool_input tool_name tool_use_id transcript_path turn_id` |
   | `PermissionRequest` | `cwd hook_event_name model permission_mode session_id tool_input tool_name transcript_path turn_id` |
   | `PostToolUse` | `cwd hook_event_name model permission_mode session_id tool_input tool_name tool_response tool_use_id transcript_path turn_id` |
   | `Interrupt` | `cwd hook_event_name model permission_mode session_id transcript_path turn_id` |
   | `Stop` | `cwd hook_event_name last_assistant_message model permission_mode session_id stop_hook_active transcript_path turn_id` |
   | `SessionEnd` | `cwd hook_event_name reason session_id transcript_path` |

   `PreCompact`, `PostCompact`, `SubagentStart` and `SubagentStop` did
   not fire. The scenarios did not cause a compaction or a subagent.
4. The hooks that fired, in order:

   | Step | Hooks |
   |---|---|
   | The TUI starts | none |
   | The first prompt | `SessionStart`, `UserPromptSubmit`, `PreModelRequest` |
   | Each later prompt | `UserPromptSubmit`, `PreModelRequest` |
   | A normal turn with no tool ends | `Stop` |
   | The approval dialog opens | `PreToolUse`, `PermissionRequest` |
   | `1. Yes, proceed` on a file write | `PostToolUse`, `PreModelRequest`, then `Stop` at the end |
   | `3. No` on the dialog | `Interrupt` |
   | Esc on the dialog | `Interrupt` |
   | Esc while an approved command runs | `Interrupt` |
   | Ctrl+C, then `1. Cancel task` or `3. Exit` | `Interrupt` |
   | Ctrl+C, then Esc on the task dialog; the turn ends | `PreModelRequest`, `Stop` |
   | The TUI exits | `SessionEnd` |

5. `Stop` did not fire after `3. No`, after Esc, or after any interrupt
   that wrote `turn_aborted` (facts 36 and 37). `Interrupt` fired in each
   of these cases, and in no other case.
6. `PostToolUse` did not fire for an approved `sleep 20`, also when it
   ended normally. It fired for an approved `printf` and for a command
   that failed in the sandbox.

## Mechanism

The `Interrupt` hook is the hook signal for an aborted turn. A tool that
waits for `Stop` after Esc or a denial waits for ever. A tool that also
listens to `Interrupt` sees the end of each turn of these runs: `Stop` or
`Interrupt`. Both payloads have `turn_id`.

`PermissionRequest` gives the tool and its input, not the labels of the
dialog.

## Incident

tg-bridge measured that the Stop hook does not fire after Esc or after the
digit 3. These runs confirm it, and show the `Interrupt` hook in its
place.

## Screens

None.

## Not measured

- Whether `SessionEnd` comes from the exit of the TUI or from the stop of
  the daemon: in most runs both happened within 1 s.
- The hook output: a hook that blocks, or that returns JSON.
- A `matcher`, and hooks in a project `.codex/` folder.
- `PreCompact`, `PostCompact`, `SubagentStart`, `SubagentStop`.
- The payload values, and the environment of the hook process.
- `--no-daemon`, and which process runs the hooks.
- macOS and Windows.
