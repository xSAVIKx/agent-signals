# 082. An agy update deletes the old logs and leaves `cli.log` broken

## Measured

2026-11-07 (UTC), on Ubuntu 24.04.5 (x64), with a real login. The probe kit
ran twice, at 15:07:22 and at 15:08:17. Between the two runs, the operator
updated the agents. The installed agy changed from 1.4.12 to 1.5.3. Claude
Code changed from 2.1.314 to 2.1.319, Codex from 0.164.0 to 0.167.0, and
the Cursor CLI from 2026.10.22-27dcf5f to 2026.11.05-86047df. The kit read
names, sizes and times only. Measured on: real machine.

## What was measured

1. Before the update, `~/.gemini/antigravity-cli/log/` held five logs.
   After the update, it held one: the log of the agy process that started
   on 2026-10-30.
2. In the first run, `~/.gemini/antigravity-cli/cli.log` had the size of
   the newest of the five logs (38894 bytes). In the second run, it was a
   link to a file that did not exist. The probe printed
   `cannot open ~/.gemini/antigravity-cli/cli.log: No such file`.
3. `crashes/` went from two entries to one.
4. The agy process of 1.4.12 (`agy --dangerously-skip-permissions`, in GNOME
   Terminal) ran in the first run. It did not run in the second run. Its
   log and `history.jsonl` were last written at 15:07:35. The kit did not
   record whether the update or the operator stopped it.
5. The Claude Code process of 2.1.292 and the Cursor CLI process of
   2026.10.22-27dcf5f ran in both runs, with the same pid and start time.
   Their updates did not stop them. The Claude pid file kept `version`
   2.1.292 (fact 066).
6. The Codex app-server daemon stayed at 0.166.0 while the standalone
   Codex went to 0.167.0 (fact 039).

## Mechanism

Not known. `cli.log` is a link to one file in `log/`. The update, or the
first start of 1.5.3, deletes old files in `log/` and does not change the
link.

A reader must not take `cli.log` as proof that an agy log exists. It must
resolve the link and accept a missing target.

## Incident

The probe `agy/unix.sh` printed a shell error for the broken link. The
helper `layout` in `probes/lib.sh` now prints `l broken <mtime> <path>`
for a link to a missing file.

## Screens

None.

## Not measured

- What stopped the agy process.
- Which step deletes the logs: the update or the first start of 1.5.3.
- How many logs agy keeps, and by which rule.
- macOS and Windows.
