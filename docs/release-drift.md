# Release drift, 2026-11-04

> **Caution: nothing in this file is measured.** Each finding is a line from
> a release note or a changelog. A line tells what a vendor says it changed.
> It does not tell what a screen, a file or a process shows now. Measure a
> finding before you change a fact, and write the result as a new fact.

This file compares the newest version that the facts measured with the
newest version that the vendor released, as of 2026-11-04. Then it lists the
changelog lines that can make a fact stale, in order of impact.

## Versions

"Newest measured" is the highest version that a fact in `facts/` names.
"Newest released" is the npm `latest` tag or the newest GitHub release that
is not marked as a pre-release. A pre-release is in parentheses.

| Agent | Newest measured | Newest released | Facts that use the measured version |
|---|---|---|---|
| Claude Code | 2.1.316 (facts 66, 73) | 2.1.318 | 23-25, 31-35, 51, 52, 66, 70, 71, 73 |
| Codex CLI | 0.166.0 (facts 51-53, 62, 65) | 0.166.0 (0.168.0-alpha.2) | 19, 20 (0.163.0); 26, 27, 36-40, 67 (0.164.0) |
| Antigravity CLI (agy) | 1.4.12 (facts 68, 70-73) | 1.5.0 | 17, 18, 28, 41-45, 68, 72, 73 |
| Cursor CLI | 2026.10.22-27dcf5f | 2026.10.22 | 21, 22, 51, 54 |
| Gemini CLI | 0.66.0 (facts 52, 56) | 0.67.0 (0.68.0-preview.0) | 30, 52, 56 |
| GitHub Copilot CLI | 1.0.105 (facts 50-52) | 1.0.105 (1.0.106-9) | 30, 50, 51, 52 |
| opencode 1 | 1.19.5 | 1.19.5 | 29, 51, 52, 63 |
| opencode 2 | 2.2.5 | 2.2.5 | 63 |

Cursor CLI, opencode 1 and opencode 2 have no release after the measured
version. Codex CLI has no stable release after 0.166.0. Many Codex facts
were measured on 0.163.0 and 0.164.0, so the 0.165.0 and 0.166.0 notes
apply to them.

## How the quotes were checked

The quotes come from release notes that were downloaded on 2026-11-04. On
the same day, these quotes were compared with the live source pages, and
each one matched:

- agy 1.5.0: the lines of findings 3, 10, 14 and 19.
- Copilot CLI 1.0.106-6: the lines of findings 1 and 2. 1.0.106-7: the
  line of finding 13.
- Gemini CLI 0.67.0: the lines of findings 4 and 21.
- Claude Code 2.1.317 and 2.1.318: the lines of findings 5, 7, 8, 11 and 12.
- Codex CLI 0.166.0: the lines of findings 6, 9, 15 and 16.
- Codex CLI alpha commits #58127 and #58166: the titles in the compare of
  `rust-v0.166.0...rust-v0.168.0-alpha.2`.

The other quotes were not compared with the live page. They come from the
same downloaded notes.

## Findings, in order of impact

"High" means that a finding can change a screen in `corpus/` or a signal
that aw or tg-bridge reads now. "Medium" means that it can change a fact
that no tool reads yet, or a signal in a mode that the tools do not use.
"Low" means that a fact can need one more line.

### 1. Copilot CLI sends the program status to the terminal (high)

- Version: 1.0.106-6 (pre-release).
- Line: "Interactive CLI reports program status to supporting terminals,
  including when attention is needed."
- Source: <https://github.com/github/copilot-cli/releases/tag/v1.0.106-6>
- Facts at risk: 30, 69. A new escape sequence can be a busy and wait
  signal that does not come from the screen text.
- Measurement: run `scenarios/first-run.sh copilot copilot` on 1.0.106-6 or
  later and keep the raw pane bytes. Search them for OSC 9;4 and other OSC
  sequences.

### 2. Copilot CLI shows no startup tips (high)

- Version: 1.0.106-6 (pre-release).
- Line: "New sessions no longer show startup tips under the header."
- Source: <https://github.com/github/copilot-cli/releases/tag/v1.0.106-6>
- Facts at risk: 30, 52, and the Copilot first screens in `corpus/`.
- Measurement: the scenarios workflow, job `first-run`, when npm `latest`
  moves past 1.0.105. Compare the screen after 20 s with the corpus screen.

### 3. agy renames the altscreen option (high)

- Version: 1.5.0.
- Line: "Changed the `no flickering (altscreen)` option under `Rendering
  Mode` in `/config` to `full screen (altscreen)`; the saved setting is
  unchanged."
- Source: <https://github.com/google-antigravity/antigravity-cli/releases/tag/1.5.0>
- Facts at risk: 6, 17. A reader that matches the old label in `/config`
  fails.
- Measurement: open `/config` in agy 1.5.0 and capture the screen.

### 4. Gemini CLI handles ambiguous-width characters as wide (high)

- Version: 0.67.0.
- Line: "fix(cli): handle terminals that render ambiguous-width characters
  as wide" (#29905).
- Source: <https://github.com/google-gemini/gemini-cli/releases/tag/v0.67.0>
- Facts at risk: 30, 52, 56, and the Gemini first screens in `corpus/`. The
  box and the columns can move.
- Measurement: the scenarios workflow, job `first-run`. Compare the screen
  after 20 s with the corpus screen.

### 5. Claude Code drops keys typed before a slow dialog (high)

- Version: 2.1.318.
- Line: "Fixed permission prompts being answered by keys typed just after
  sending a message, or before a slow prompt appeared"
- Source: <https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md>
- Facts at risk: 4, 7, 33. A tool that sends a digit as soon as the dialog
  draws can now send it too early.
- Measurement: the scenario `permission-dialog` with the digit sent 0 ms,
  100 ms and 500 ms after the first frame of the dialog.

### 6. Codex CLI reports the working folder in PreToolUse (high)

- Version: 0.166.0 (fact 38 measured 0.164.0).
- Line: "Report the local command working directory in PreToolUse hooks"
  (#57198).
- Source: <https://github.com/openai/codex/releases/tag/rust-v0.166.0>
- Facts at risk: 38.
- Measurement: the scenario of fact 38 on 0.166.0. Record the PreToolUse
  payload and compare its keys.

### 7. Claude Code `claude -p` inside a session gets its own session ID (medium)

- Version: 2.1.317.
- Line: "Added `CLAUDE_CODE_DISABLE_NESTED_SESSION_ID`: set it to `1` on a
  self-hosted runner to have `claude -p` run inside a session use that
  session's ID and transcript, as in earlier versions"
- Source: <https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md>
- Facts at risk: 23, 31, 34, 66. A nested `claude -p` can write a new pid
  file and a new transcript.
- Measurement: run `claude -p` from the Bash tool of a live session. List
  `~/.claude/sessions/` and the project folder before and after.

### 8. Claude Code version cleanup and running programs (medium)

- Version: 2.1.318.
- Line: "Fixed a running Claude Code process owned by another user (for
  example one left by `sudo claude`) being treated as dead by version
  cleanup, which could delete its binary"
- Source: <https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md>
- Facts at risk: 47, 71.
- Measurement: start Claude Code, update it, and list the versions folder
  and the program of the running process.

### 9. Codex CLI app-server start and stop races (medium)

- Version: 0.166.0 (facts 39 and 67 measured 0.164.0).
- Line: "Fixed app-server thread startup and shutdown races and released
  completed runtimes promptly." (#57787, #57788)
- Source: <https://github.com/openai/codex/releases/tag/rust-v0.166.0>
- Facts at risk: 26, 39, 67. The daemon can now end sooner or hold fewer
  files.
- Measurement: the scenario `daemon-life` on 0.166.0.

### 10. agy runs as an ACP server (medium)

- Version: 1.5.0.
- Line: "Added `acp` to `agy --help`: `agy acp` runs the CLI as an Agent
  Client Protocol (ACP) server over stdio, so editors can use it as their
  agent, [...]"
- Source: <https://github.com/google-antigravity/antigravity-cli/releases/tag/1.5.0>
- Facts at risk: 28, 44, 68, and the process rules in `docs/detection.md`.
  An `agy acp` process has no tty, and a tool can count it as a session.
- Measurement: start `agy acp` from a pipe. Record the process tree, the
  open files and the presence file.

### 11. Claude Code shorter temporary paths on Windows (medium)

- Version: 2.1.317.
- Line: "Windows: Fixed the session scratchpad and other temporary paths
  growing with your project's path length in sessions not started by
  Claude Desktop, which made repositories cloned into them hit the
  260-character path limit"
- Source: <https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md>
- Facts at risk: 25, 34, 51 on Windows. The task folder path can change.
- Measurement: the scenario `first-run-windows` with a long project path.
  List the temporary folders of Claude Code.

### 12. Claude Code no longer installs the IDE extension (medium)

- Version: 2.1.318.
- Line: "Changed Claude Code to no longer install or update the IDE
  extension when started in an IDE terminal; use `/ide` from an outside
  terminal or your editor's extensions view"
- Source: <https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md>
- Facts at risk: 69 (the environment of an IDE terminal), 22.
- Measurement: start Claude Code in a VS Code terminal. Record the child
  processes.

### 13. Copilot CLI moves the XDG folder into `~/.copilot` (medium)

- Version: 1.0.106-7 (pre-release).
- Line: "The move of an older `$XDG_CONFIG_HOME/.copilot` directory into
  `~/.copilot` now also brings over your MCP servers, language servers,
  saved folder permissions, personal instructions, custom agents and
  skills, [...]"
- Source: <https://github.com/github/copilot-cli/releases/tag/v1.0.106-7>
- Facts at risk: 50, and the state folders of Copilot in
  `docs/roadmap.md`.
- Measurement: the scenario `first-run` with `XDG_CONFIG_HOME` set in the
  throwaway folder.

### 14. agy remote sessions change the header (medium)

- Version: 1.5.0.
- Line: "Added `--remote-agent` to `agy --help`, [...] the header shows
  `remote workspace` instead of your local directory, [...]"
- Source: <https://github.com/google-antigravity/antigravity-cli/releases/tag/1.5.0>
- Facts at risk: 17. A reader that takes the folder from the header
  gets no folder.
- Measurement: start `agy --remote-agent` and capture the first screen.
  This needs a login.

### 15. Codex CLI ships the standalone executor (medium)

- Version: 0.166.0.
- Line: "Shipped the standalone executor in canonical CLI and app-server
  release packages." (#57837)
- Source: <https://github.com/openai/codex/releases/tag/rust-v0.166.0>
- Facts at risk: 26, 39, 51. The process tree can hold one more program.
- Measurement: the scenario `first-run` and a turn. Record the process tree.

### 16. Codex CLI reconnects the TUI (medium)

- Version: 0.166.0.
- Line: "Improved TUI reconnection recovery, including offline `/quit` and
  `/exit` handling." (#57820)
- Source: <https://github.com/openai/codex/releases/tag/rust-v0.166.0>
- Facts at risk: 39, 67.
- Measurement: stop the daemon while a TUI runs, and capture the screen.

### 17. Codex CLI opens SQLite with DELETE journaling on NFS (medium)

- Version: 0.166.0 (fact 40 measured 0.164.0).
- Line: "Initialize SQLite databases with DELETE journaling on NFS"
  (#56552).
- Source: <https://github.com/openai/codex/releases/tag/rust-v0.166.0>
- Facts at risk: 40. On NFS a reader finds no `-wal` file.
- Measurement: run Codex CLI with `CODEX_HOME` on an NFS mount and list the
  database files. This needs an NFS server.

### 18. Codex CLI respects the server approval defaults at start (medium)

- Version: 0.165.0 and 0.166.0.
- Lines: "Fixed fresh TUI sessions to honor the server’s default approval
  reviewer when no explicit override is provided." (0.165.0, #56090) and
  "Respect server approval policy defaults during TUI startup" (0.166.0,
  #56516).
- Sources: <https://github.com/openai/codex/releases/tag/rust-v0.165.0>,
  <https://github.com/openai/codex/releases/tag/rust-v0.166.0>
- Facts at risk: 19, 36. The approval dialog can open for other actions.
- Measurement: the scenario `approval` on 0.166.0.

### 19. agy `-p` exit code on a print timeout (low)

- Version: 1.5.0.
- Line: "when `--print-timeout` cuts a turn short, the run now exits with
  code `3`, prints an `AGY_ERROR` line naming the tasks it terminated, and
  writes a `[agy] print timeout after ...` line to stderr."
- Source: <https://github.com/google-antigravity/antigravity-cli/releases/tag/1.5.0>
- Facts at risk: none. The corpus has no agy `-p` fact.
- Measurement: `agy -p --print-timeout 5s` with a long prompt. Record the
  exit code. This needs a login.

### 20. Codex CLI memory v2 for fresh profiles (low)

- Version: 0.165.0.
- Line: "Enabled memory v2 by default for fresh profiles and added support
  for importing external-agent memories into it." (#56211, #56414)
- Source: <https://github.com/openai/codex/releases/tag/rust-v0.165.0>
- Facts at risk: 29, 62. The first start can make more files.
- Measurement: the scenario `first-run` lists the files. Fact 62 measured
  0.166.0, so the result of this finding is in that fact or in the next
  run.

### 21. Gemini CLI lists models (low)

- Version: 0.67.0.
- Line: "feat(cli): add models command and --list-models flag for model
  discovery" (#29880).
- Source: <https://github.com/google-gemini/gemini-cli/releases/tag/v0.67.0>
- Facts at risk: none. A new subcommand can start a process that a tool
  counts as a session.
- Measurement: none needed now.

### 22. Gemini CLI re-renders the history after a resize (low)

- Version: 0.68.0-preview.0 (pre-release).
- Line: "fix(cli): bound inline history re-render after terminal width
  changes" (#29904).
- Source: <https://github.com/google-gemini/gemini-cli/releases/tag/v0.68.0-preview.0>
- Facts at risk: 8. A resize can draw fewer lines.
- Measurement: resize a Gemini pane and record the frames.

### 23. Gemini CLI shows the 429 countdown (low)

- Version: 0.68.0-preview.0 (pre-release).
- Line: "fix(cli): surface 429 rate limit cool-down and countdown in
  loading indicator" (#30012).
- Source: <https://github.com/google-gemini/gemini-cli/releases/tag/v0.68.0-preview.0>
- Facts at risk: none. A busy screen can show a new text.
- Measurement: none until the corpus has a Gemini busy screen.

### 24. Copilot CLI short terminals keep the dialog title (low)

- Version: 1.0.106-3 (pre-release).
- Line: "Confirmation dialogs such as "Enable autopilot mode" and "Confirm
  folder trust" keep their title, highlighted option and key hints on
  screen in a short terminal"
- Source: <https://github.com/github/copilot-cli/releases/tag/v1.0.106-3>
- Facts at risk: 30. The folder-trust screen at 40 lines does not change.
- Measurement: the scenario `first-run` with 20 lines.

### 25. Copilot CLI footer on narrow terminals (low)

- Version: 1.0.106-7 (pre-release).
- Line: "On narrow terminals the footer no longer leaves a stray separator
  where a hint did not fit or cuts the permission mode mid-name."
- Source: <https://github.com/github/copilot-cli/releases/tag/v1.0.106-7>
- Facts at risk: none at 120 columns.
- Measurement: none until the corpus has a narrow Copilot screen.

### 26. Codex CLI rollout recording (low, alpha only)

- Version: commits after 0.166.0, in 0.167.0-alpha and 0.168.0-alpha.
- Lines: "Make rollout recording failures and completion explicit
  (#58166)" and "Honor the tooltip preference for TUI startup help
  (#58127)".
- Source: <https://github.com/openai/codex/compare/rust-v0.166.0...rust-v0.168.0-alpha.2>
- Facts at risk: 19, 27 (the rollout file), 20 (the first screen).
- Measurement: wait for the next stable release. Then run the scenarios
  `interrupt` and `screens`.

### 27. Claude Code exit hint repeats the flags (low)

- Version: 2.1.317.
- Line: "Improved the "Resume this session with" hint shown at exit to
  repeat the flags you launched with (for example `--chrome --debug`) ahead
  of `--resume`"
- Source: <https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md>
- Facts at risk: 35. A reader that parses the exit hint gets more words.
- Measurement: the scenario `plan-and-resume`. Capture the screen after the
  exit.

## Not covered

- Cursor CLI, opencode 1 and opencode 2 have no release after the measured
  version. No finding.
- The agents in groups b, c and d of the scenarios workflow were not
  checked. The newest release of each one was not read.
- Pre-releases are listed only when the change can change a screen or a
  file. A pre-release can change again before it becomes `latest`.
