# 044. The agy presence file is a flock lock

## Measured

2026-10-30, Antigravity CLI (agy) 1.4.7, on Linux (Debian 13, x64), in a
private tmux server with a throwaway `HOME` and a copied login. The
scenarios `scenarios/agy/deny-and-tools.sh` (two runs) and
`scenarios/agy/continue.sh` (one run, three processes) ran, at each step,
`flock -n <file> true` on each file in
`~/.gemini/antigravity-cli/presence/`, from another process. They also
listed the lines of `/proc/locks` for the inode of each file in
`presence/` and `conversations/`. Both only read.
Measured on: real machine.

## What was measured

1. While agy ran, `flock -n` on `presence/<conversation id>.lock` exited
   with 1: another process held the lock. `/proc/locks` showed one
   `FLOCK ADVISORY WRITE` lock on the file. This was so at each step:
   busy, a dialog, after a turn, and after an Esc.
2. After the process exited, `flock -n` exited with 0, and `/proc/locks`
   showed no lock. The file stayed, with size 0.
3. A new session made the file and took the lock at the first prompt.
   Before the first prompt, `presence/` had no file. A process started with
   `--continue` or `--conversation <id>` took the lock at the start
   (fact 43).
4. `conversations/<conversation id>.db` and its `-shm` file each had one
   `POSIX ADVISORY READ` lock while agy ran. The `-wal` file had none.

## Mechanism

agy takes an exclusive `flock` lock on the presence file and keeps it until
the process exits. The kernel drops the lock when the process ends, also
after a crash. A reader can test whether a conversation is open in a live
process with `flock -n <file> true`: exit 1 means open. The test changes
nothing, and it needs no process list. The file alone does not show this:
it stays after the exit.

The `POSIX` read locks on the `.db` and `-shm` files are the locks of
SQLite in WAL mode.

## Incident

None recorded.

## Screens

None.

## Not measured

- A crash or a `kill -9` of agy.
- Two processes on one conversation at the same time.
- The lock on macOS (`flock` is not installed there by default) and on
  Windows.
- A lock file on a network file system.
- Other agy versions.
