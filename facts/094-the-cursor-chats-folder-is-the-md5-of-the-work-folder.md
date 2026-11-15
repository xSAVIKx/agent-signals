# 094. The Cursor chats folder is the MD5 of the work folder path

## Measured

2026-11-15 (UTC), Cursor CLI 2026.11.05-86047df, on Linux (Debian 13,
x64), in a kit session with the fixture home: the Cursor CLI ran against
the local fake server of the kit (fact 078), with a throwaway `HOME`. The
session sent one prompt. Then the test listed `~/.cursor/chats/` and
compared its folder name with the MD5, SHA-1 and SHA-256 digests of four
forms of the work folder path. It read no chat. Measured on: real
machine.

This answers request 7 of aw in `docs/roadmap.md` for Linux.

## What was measured

1. After the first prompt, `~/.cursor/chats/` held one folder. Its name
   was the MD5 digest, in lower-case hex, of the absolute path of the work
   folder, with no `/` at the end.
2. The SHA-1 and SHA-256 digests of the same path did not match. The MD5
   digests of the path with a `/` at the end and of the `file://` URL of
   the path did not match.
3. The session also made `~/.cursor/projects/<path>`, where `<path>` is
   the work folder path with no `/` at the start and each `/` changed to
   `-`.

## Mechanism

A reader can find the chats of a work folder with no process: compute the
MD5 of the absolute path, then list `~/.cursor/chats/<md5>/`. Each chat is
one folder `<chat id>/store.db` in it (fact 021). A reader that has a
Cursor process can also read the path from its open `store.db` (fact
091).

## Incident

None.

## Screens

None.

## Not measured

- macOS and Windows. On Windows the path form (drive letter case,
  backslashes) is not known.
- A work folder that the agent reached through a symbolic link: the test
  path had no link, so the path and its physical form were the same.
- Other Cursor CLI versions, and a real login and model.
