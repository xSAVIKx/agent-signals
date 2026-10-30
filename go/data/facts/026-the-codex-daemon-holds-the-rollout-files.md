# 026. The Codex daemon holds the rollout files

## Measured

2026-10-30, Codex CLI 0.164.0 (standalone install, x86_64-unknown-linux-musl),
on Linux (Debian 13, x64), in a private tmux server with a throwaway
`HOME` and a copied login. The scenarios `scenarios/codex/approval.sh`
(with and without `--no-daemon`) and `scenarios/codex/two-sessions.sh`
read `/proc/<pid>/fd` of each process at each step.
Measured on: real machine.

## What was measured

1. In the default mode, the TUI starts an app-server daemon:
   `~/.codex/packages/app-server-daemon/releases/<version>-<target>/bin/codex app-server --listen unix:// --analytics-default-enabled --managed-daemon`.
   It has no tty. Its parent is the TUI. A second child,
   `codex app-server daemon pid-update-loop`, also starts.
2. The daemon, not the TUI, holds the session files open:
   - `~/.codex/thread-writer-locks/<session id>.lock`, from the start of
     the session, before the first prompt.
   - `~/.codex/sessions/YYYY/MM/DD/rollout-<time>-<session id>.jsonl`, from
     the first prompt.
   The TUI holds neither file.
3. Two TUIs with the same `HOME` share one daemon. The daemon is a child
   of one of the two TUIs. It holds the lock and the rollout file of both
   sessions.
4. After the TUI exits, the daemon keeps running. Its parent becomes
   process 1. It keeps the lock and the rollout file of the ended session
   open.
5. `codex resume --last` uses the daemon that runs. It appends to the same
   rollout file. It makes no new file. No process in the tree of the
   resumed TUI holds the file.
6. With `--no-daemon`, the TUI itself holds the lock from the start and the
   rollout file from the first prompt. `resume` also appends to the same
   file in this mode.

## Mechanism

The daemon writes the sessions for all TUIs of one `HOME`. Thus an open
rollout file in the process tree of a TUI does not prove that the session
belongs to that TUI, and an open rollout file does not prove that its
session is live. Only with `--no-daemon` does an open file link one TUI to
one session.

The session ID in the lock file name is known before the first prompt,
when no rollout file exists yet.

## Incident

aw planned an exact binding from a Codex TUI to its rollout file through
the open files of the process tree. In the default mode that binding can
pick the session of another TUI.

## Screens

None.

## Not measured

- macOS and Windows.
- Whether a file links a TUI to its thread in daemon mode, for example
  `~/.codex/state_5.sqlite`. It was not read.
- When the daemon exits after the last TUI exits. It still ran 20 s after.
- The sandbox helper: on this machine `bwrap` could not make a namespace,
  so the commands ran with no sandbox helper process.
