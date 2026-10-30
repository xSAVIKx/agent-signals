# 043. agy --continue reuses the files of the conversation

## Measured

2026-10-30, Antigravity CLI (agy) 1.4.7, on Linux (Debian 13, x64), in a
private tmux server with a throwaway `HOME` and a copied login. The
scenario `scenarios/agy/continue.sh` started agy four times in the same
`HOME` and work folder: `agy` with no prompt, `agy --continue` with no
conversation, `agy --continue`, and `agy --conversation <id>`. Each start
after the first had one short turn. It recorded the hooks, the open files,
the kernel locks, the file list and the transcript record types.
Measured on: real machine.

## What was measured

1. `agy --continue` in a folder with no conversation drew the same bytes
   as a new start: the normal idle box and `? for shortcuts`. It held no
   `presence` or `conversations` file open. The first prompt made a new
   conversation, and `SessionStart` fired.
2. `agy --continue` with one conversation, and `agy --conversation <id>`,
   used the same conversation ID. The new process opened the same files:
   - `~/.gemini/antigravity-cli/presence/<conversation id>.lock`;
   - `~/.gemini/antigravity-cli/conversations/<conversation id>.db`, with
     its `-wal` and `-shm` files.
   It opened them at the start, before the first prompt. A new session
   opens them at the first prompt (fact 28).
3. `SessionStart` did not fire for a continued conversation. Each turn gave
   `PreInvocation`, `PostInvocation` and `Stop`, with the same
   `conversationId`.
4. The folder held one `.db` file after the three turns. The `.lock` file
   kept its first modification time. After each exit, the `-wal` and `-shm`
   files were gone, and the `.db` file was larger.
5. A continued turn added a `SYSTEM_MESSAGE` record after its `USER_INPUT`
   record in `transcript.jsonl`. The first turn had no `SYSTEM_MESSAGE`
   record.
6. The screen of a continued session shows the earlier turns above the
   box.

## Mechanism

A reader that links a process to its conversation by the names of the open
files (fact 28) gets the same ID for a continued process. Such a reader
must not wait for `SessionStart` to learn the ID: a continued process
sends none. It can read the ID from the open files at the start, or from
`conversationId` in `PreInvocation`.

## Incident

tg-bridge noted that agy 1.4.7 `--continue` in an empty folder draws an
empty framed box that reads as idle (fact 28). This measurement shows that
the box is idle: the same screen as a new start, and the next prompt ran.

## Screens

`agy/continue-empty-v1-4-7`.

## Not measured

- `--continue` in a folder with two or more conversations, and from a
  subfolder.
- `--conversation` with an ID that does not exist.
- Two processes on one conversation at the same time.
- The text of the `SYSTEM_MESSAGE` record.
- macOS and Windows. Other agy versions.
