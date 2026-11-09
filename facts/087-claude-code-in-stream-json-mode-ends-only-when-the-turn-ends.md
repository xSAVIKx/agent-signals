# 087. Claude Code in stream-json mode ends only when its turn ends

## Measured

2026-11-09 (UTC), Claude Code 2.1.319 on Linux (Debian 13, x64), with the
scenario `scenarios/claude/pipe-close.py`, the fake model of the kit and a
new throwaway home for each case. Each case ran two times: one time by
hand and one time with the scenario. Measured on: real machine.

## Conditions

- The command was
  `claude -p --input-format stream-json --output-format stream-json --verbose`,
  with stdin and stdout as pipes, in its own process group. The cases
  `perm-*` added `--permission-prompt-tool stdio`.
- The settings file of the home sets the permission mode `default`.
- `Count from 1 to 100` makes the fake model hold the request with no
  reply, so the turn stays busy. `Create a file now` makes the fake model
  ask for a `Bash` call.
- After the close, the scenario waited 120 s, then stopped the process
  group.

## What was measured

| Case | When the client closed the pipe | Result |
|---|---|---|
| `idle-stdin` | stdin, after the `result` message of a turn | exit 0 at once |
| `busy-stdin` | stdin, 3 s into a busy turn | runs after 120 s |
| `busy-stdout` | stdout, 3 s into a busy turn | runs after 120 s |
| `busy-both` | stdin and stdout, 3 s into a busy turn | runs after 120 s |
| `busy-end` | stdin, 3 s into a busy turn; the fake model stopped 5 s later | see item 3 |
| `perm-stdin` | stdin, while a `can_use_tool` control request waited | exit 0 at once, no file written |
| `perm-both` | stdin and stdout, while a `can_use_tool` request waited | exit 0 within 2 s, no file written |

More results:

1. In the busy cases, one process ran. It had no child process.
2. In the `perm-*` cases the fake model got a second request, with the
   tool result, before the exit. The `Bash` call did not run.
3. In `busy-end` the fake model stopped, so each new connection was
   refused. In the run by hand the process ended with exit code 1, between
   42 s and 102 s after the fake model stopped. In the run of the
   scenario it still ran 115 s after the fake model stopped. Claude Code
   tried the request again during that time; this scenario did not count
   the tries.

## Mechanism

Claude Code reads stdin as a queue of user messages. The end of stdin
does not stop a turn that runs: the process ends when the turn ends. A
closed stdout does not stop the turn either. A turn that waits for a
model that does not answer can run for a long time. A permission request
that waits for the client ends as a denial when stdin closes.

## Use

A client of Claude Code in stream-json mode must stop the process by its
pid, or by its process group, when it ends a session. It must not expect
the close of the pipes to stop a busy process.

## Screens

None.

## Not measured

- A real model and a real login. A real model ends a turn after some
  time, and the process then ends.
- The Claude Agent SDK. This scenario starts the command directly.
- macOS and Windows.
- A busy turn that runs a tool, for example a long `Bash` command.
- The interactive TUI. It does not read its prompt from stdin.
