# 071. A Windows update renames the running program of Claude Code and agy

## Measured

2026-10-31, Claude Code 2.1.314 and Antigravity CLI (agy) 1.4.12, on
Windows 11 Pro 10.0.26300 (x64). The probe kit (`probes/run.ps1`) listed
the install folders with names, sizes and times, and the processes.
Measured on: real machine.

## What was measured

1. `~\.local\bin\` held `claude.exe` (2.1.314) and two files of the form
   `claude.exe.old.<Unix time in ms>.<pid>`. In one of them, `<pid>` was
   the pid of a Claude process that still ran. That process started 9
   days before the probe.
2. `~\.local\share\claude\versions\` held 2.1.311, 2.1.312 and 2.1.314
   as single files. The size of each `.old` file was the size of one of
   these versions.
3. `~\AppData\Local\agy\bin\` held `agy.exe` and two files of the form
   `agy.exe.<hex>.old`.
4. The Claude process that started 9 days before the probe had a pid file
   with `version` of its own, older version (see fact 066). Two Claude pid
   files existed, one for each live process. They had the same keys as on
   macOS and Linux, and no `tmux` key.
5. A third `claude.exe` ran as `chrome.exe` > `cmd.exe` > `claude.exe
   --chrome-native-host`, with no pid file, as on Ubuntu (fact 066).

## Mechanism

Windows does not let a program replace the file of a running program, but
it lets the program rename the file. The updater renames the old file and
writes the new file in its place. The name keeps the pid of the process
that ran the old file. The `.old` files stay after that process stops.

A reader can take the version of a live process from its pid file. The
file `claude.exe` gives only the newest version.

## Incident

None.

## Screens

None.

## Not measured

- When the updaters delete the `.old` files.
- The meaning of the hex part in the agy name.
- Whether the time in the Claude name is the time of the update. It is in
  ms, and it was within a day of the file time of the `.old` file.
