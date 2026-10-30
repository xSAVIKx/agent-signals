# 039. The Codex daemon outlives its TUIs and updates itself

## Measured

2026-10-30, Codex CLI 0.164.0 (standalone install,
x86_64-unknown-linux-musl), on Linux (Debian 13, x64), in a private tmux
server with a throwaway `HOME` and a copied login. The scenario
`scenarios/codex/daemon-life.sh` ran two TUIs in the default daemon mode,
then a `--no-daemon` TUI next to them, then a third daemon-mode TUI after
the first ones exited. It read `/proc/<pid>/fd` of each process and the
command line of the daemon, and logged the daemon each 10 s for 300 s
after the last TUI exited. Two runs. The update of item 5 has a time only
in the second run.
Measured on: real machine.

## What was measured

1. Two TUIs with the same `HOME` used one app-server daemon, as in fact 26.
   The daemon held the rollout file and the lock of both sessions.
2. A `codex --no-daemon` TUI that started next to the running daemon held
   its own rollout file and its own lock
   (`~/.codex/thread-writer-locks/<session id>.lock`). The daemon did not
   hold them. The daemon pid did not change.
3. After the TUIs exited, the daemon kept running, with parent pid 1. A TUI
   that started 30 s later used the same daemon pid. No second daemon
   started. The daemon then held the lock and the rollout file of the new
   session too.
4. The daemon did not exit in the 300 s after the last TUI exited, in
   either run.
5. The daemon replaced itself with a newer version. In the second run,
   between 203 s and 213 s after the last TUI exited (about 6 minutes
   after the daemon started):
   - The daemon of 0.164.0 stopped.
   - `~/.codex/packages/app-server-daemon/releases/0.166.0-x86_64-unknown-linux-musl/`
     appeared, and a daemon from that folder started with a new pid.
   - The `pid-update-loop` process kept its pid, but its command line now
     named the 0.166.0 folder. It became the parent of the new daemon.
   - The new daemon held no rollout file and no lock of the ended
     sessions.
   In the first run, the same change happened between 0 s and 304 s after
   the last TUI exited. The installed `codex` stayed 0.164.0, and each TUI
   drew "Update available! 0.164.0 -> 0.166.0".

## Mechanism

The daemon has its own release folder below `~/.codex/packages/`, apart
from the installed CLI. The `pid-update-loop` process updates it with no
TUI. Thus the daemon can run a newer version than the TUI, and the pid of
the daemon is not stable while it runs.

## Incident

None recorded. A reader that keeps the daemon pid, or that reads the
version of the daemon from its path, can be wrong after an update.

## Screens

None.

## Not measured

- When the daemon exits, if ever.
- What starts the update: the age of the daemon, a timer, or the end of
  the last TUI. Whether it also happens while a TUI runs.
- Whether a TUI of 0.164.0 can use the daemon of 0.166.0.
- A machine with no newer version to download.
- Two Ctrl+C left two TUIs running in the first run (fact 37). The
  hangup of the tmux server ended them.
- macOS and Windows.
