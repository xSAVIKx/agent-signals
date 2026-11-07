# 083. An old Codex shows an update dialog before its input box

## Measured

2026-11-07 (UTC), Codex CLI 0.164.0 on macOS 26.6.2 (arm64), with a real
login and the real home folder. Codex 0.167.0 was the newest version. The
agent kit 0.16.0 ran unattended with the home mode `real`. Measured on:
real machine.

## What was measured

1. At each start in a new work folder, Codex showed the update dialog of
   the screen `update-v0-164-0` before its input box. The dialog has three
   options: "1. Update now", "2. Skip" and "3. Skip until next version".
   The mark starts on "1. Update now". The footer is
   `enter continue · esc skip`.
2. The dialog showed in all 16 Codex session steps of the run, on tmux and
   on pty. It showed again at each new start, so an answer of the earlier
   session did not stop it. The kit sent no key to it.
3. "Update now" runs the install script of Codex
   (`curl -fsSL https://chatgpt.com/codex/install.sh`).
4. The same run on Ubuntu 24.04.5 with Codex 0.167.0 showed no update
   dialog.
5. `first-run-codex` uses a throwaway home. It passed on the same Mac, with
   no update dialog.

## Mechanism

Codex compares its version with the newest release when it starts in a
home that has a login. The details are not known.

## Incident

The session steps of the kit waited 60 s for the idle screen and failed
with `no-idle`. The kit now pushes Escape on this dialog. The footer names
Escape as "skip". "Skip until next version" writes the choice to the home
folder, and "Update now" installs a new version, so the kit uses neither.

## Screens

`codex/update-v0-164-0`.

## Not measured

- Whether Escape skips the update for the session only. The kit change has
  not run on the Mac yet.
- Linux and Windows with an old Codex.
- The throwaway home with a login.
- Where Codex stores "Skip until next version".
