# 093. Cursor CLI and Codex process shapes in psmux on Windows

## Measured

2026-11-07, 2026-11-08 and 2026-11-13 (UTC), Cursor CLI 2026.11.05-86047df
and 2026.11.11-b912975, Codex CLI 0.169.0 (the version on its screen), on
Windows 11 Pro 10.0.26300 (x64), with the real home and login of the
operator, in psmux. The kit steps of kit 0.16.0, 0.18.1 and 0.22.0 ran
each session. The guided watch listed the processes of each agent with
their parent pid and command line. Measured on: real machine.

This answers request 12 of aw in `docs/roadmap.md` in part.

## What was measured

1. The Cursor CLI ran as three processes:
   - `pwsh.exe -NoProfile -ExecutionPolicy <arg> -File
     ~\AppData\Local\cursor-agent\...`;
   - its child `~\AppData\Local\cursor-agent\versions\<version>\node.exe
     ...\index.js`;
   - a child of that `node.exe`, with one more argument.

   Fact 051 saw the first two in a pseudo-console with `powershell.exe`.
   The third process is the child of fact 081 (macOS and Linux).
2. Codex CLI 0.169.0 ran as one process,
   `~\AppData\Local\Programs\OpenAI\Codex\bin\codex.exe`, with its
   arguments. No child process came.
3. The three runs gave the same Cursor process shape.

## Mechanism

A reader that finds a Cursor CLI session on Windows looks for `node.exe`
with `cursor-agent\versions\` in its path, and takes the outer `pwsh.exe`
or `powershell.exe` as the process of the session. For Codex, the
session is the one `codex.exe` process.

## Incident

None. The Cursor steps of 2026-11-13 hit the usage limit of the account
(`Error: You've hit your usage limit`). The process shape before the
error is still valid.

## Screens

None.

## Not measured

- The parent of the outer process. The watch lists only the processes of
  the agent, so the chain from the psmux pane shell (fact 070) is not
  in the data.
- The open files: the laptop had no Sysinternals `handle.exe`.
- The Codex version from the install: the doctor printed `unknown`.
- Other Windows builds than 10.0.26300, Windows on arm64, Windows
  PowerShell 5.1 as the pane shell, and Cursor CLI or Codex versions other
  than the ones above. A pseudo-console without psmux: fact 051.
