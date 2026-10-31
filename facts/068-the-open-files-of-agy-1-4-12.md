# 068. The open files of agy 1.4.12 on macOS and Ubuntu

## Measured

2026-10-31, Antigravity CLI (agy) 1.4.12, on macOS 26.6.2 (arm64), one
process started as `agy --dangerously-skip-permissions -c` in
Terminal.app. The probe kit (`probes/run.sh`, probe `agy/unix.sh`) read
`ps` and `lsof`.

The same day, the kit ran on Ubuntu 24.04.5 (x64). One process of agy
1.4.12 ran as `agy --dangerously-skip-permissions` in GNOME Terminal. It
had started the day before.
Measured on: real machine.

## What was measured

1. The process chain was `Terminal` > `login` > `-zsh` > `agy`, with a
   tty. The environment had `TERM_PROGRAM=Apple_Terminal` and
   `__CFBundleIdentifier=com.apple.Terminal`.
2. The process held these files open:
   - `~/.gemini/antigravity-cli/conversations/<uuid>.db`, with its
     `-shm` and `-wal` files.
   - `~/.gemini/antigravity-cli/presence/<uuid>.lock`.
3. These are the same paths as on Linux with agy 1.4.7 (fact 028, fact
   044).
4. The process on Ubuntu held only `presence/<uuid>.lock` open, and no
   conversation database. Its chain was `gnome-terminal-server` >
   `zsh` > `agy`.

## Mechanism

The open conversation database links an agy process to its conversation
on macOS too. The link is not always there: the process on Ubuntu held
no database open. The presence lock is there in both cases. The presence lock is the flock lock of fact 044.

## Incident

The probe printed the command line of the process in place of the folder
`~/.gemini/antigravity-cli/` in its layout and log sections. A helper of
`probes/lib.sh` changed a variable of the probe. The fix gives the helper
variables their own names, and `tools/test-probe-lib.sh` checks it.

## Screens

None.

## Not measured

- The layout of `~/.gemini/antigravity-cli/`, because of the probe bug.
- Why the process on Ubuntu held no conversation database: no
  conversation yet, or a database that agy closes when it is idle.
- Whether the presence lock is a flock lock on macOS.
- agy hooks on macOS. The machine had no `~/.gemini/config/hooks.json`.
