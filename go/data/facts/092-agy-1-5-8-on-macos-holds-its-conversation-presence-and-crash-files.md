# 092. agy 1.5.8 on macOS holds its conversation, presence and crash files open

## Measured

2026-11-13 (UTC), Antigravity CLI (agy) 1.5.8, on macOS 26.6.2 (arm64),
with the real home and login of the operator, in tmux and in a
pseudo-terminal. The kit steps of kit 0.22.0 ran each session. The guided
watch listed the files that the session processes held open before and
after each step (`lsof`). The probe of the same run listed the agy
process of the orchestrator in Terminal.app. It read no conversation
text. Measured on: real machine.

This answers request 11 of aw in `docs/roadmap.md` for agy 1.5.8. Fact
068 has agy 1.4.12 on macOS, and fact 089 has agy 1.5.8 on Linux.

## What was measured

1. In Terminal.app the process chain was `Terminal` > `login` > `-zsh` >
   `agy`.
2. A session held these files open after its first turn:
   `~/.gemini/antigravity-cli/conversations/<uuid>.db`, `.db-shm` and
   `.db-wal`, and `presence/<uuid>.lock`, as agy 1.4.12 (fact 068).
3. Each process held `crashes/crash_<pid>_<uuid>.log` open, with its own
   pid in the name. Example, from `25-resume-agy@tmux.txt`: the first
   process held `crash_71749_<uuid>.log`, and the process that started
   again with `--continue` held `crash_72745_<uuid>.log`. This is the same
   as on Linux (fact 089).
4. The process that started with `--continue` held the conversation
   database and the presence file.

## Mechanism

The file layout and the open files of agy 1.5.8 on macOS are the same as
on Linux. A reader can use the rules of fact 089 on macOS: find the live
agy processes from `crashes/`, then test that each pid runs and is agy.

## Incident

None.

## Screens

None.

## Not measured

- The lock type of the presence file on macOS (fact 044 has the flock on
  Linux).
- The order of the opens: the watch compares two snapshots.
- Whether the crash file stays after `kill -9` on macOS.
- The process chain of the test sessions: the probe records only the
  process of the orchestrator.
- Other macOS versions than 26.6.2, an Intel Mac, and agy versions other
  than 1.5.8. Windows: fact 072 has older versions.
