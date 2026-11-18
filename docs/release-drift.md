# Release drift, 2026-11-18

> **Caution: nothing in this file is measured.** Each finding is a line from
> a release note or a changelog. A line tells what a vendor says it changed.
> It does not tell what a screen, a file or a process shows now. Measure a
> finding before you change a fact, and write the result as a new fact.

This file compares three versions for each agent, as of 2026-11-18: the
newest version that a fact in `facts/` names, the newest version that a
file in `corpus/` names, and the newest version that the vendor released.
Then it lists the changelog lines that can make a fact or a screen stale,
in order of impact. The file of 2026-11-04 is in the git history.

## Versions

"Newest in facts" is the highest version that a fact names for that agent.
"Newest in corpus" is the highest `agent_version` or `version` in
`corpus/<agent>/`. "Newest released" is the npm `latest` tag, or the newest
GitHub release that is not marked as a pre-release. A pre-release is in
parentheses.

| Agent | Newest in facts | Newest in corpus | Newest released | Source of the release |
|---|---|---|---|---|
| Claude Code | 2.1.319 (facts 080, 084, 087) | 2.1.325 | 2.1.327 | npm `@anthropic-ai/claude-code` |
| Codex CLI | 0.169.0 (facts 093, 095) | 0.169.0 | 0.170.0 | npm `@openai/codex`, GitHub `openai/codex` |
| Antigravity CLI (agy) | 1.5.8 (facts 089, 092) | 1.5.9 | 1.5.11 | GitHub `google-antigravity/antigravity-cli` |
| Cursor CLI | 2026.11.05-86047df (facts 078, 081, 091, 093, 094) | 2026.11.13-eacade1 | 2026.11.17-f532c45 | the URL in `https://cursor.com/install` |
| Gemini CLI | 0.68.0 (fact 090) | 0.68.0 | 0.68.0 (0.69.0-preview.0) | npm `@google/gemini-cli` |
| GitHub Copilot CLI | 1.0.105 (facts 030, 047, 050-052) | 1.0.105 | 1.0.114 | npm `@github/copilot` |
| opencode 1 | 1.19.5 (facts 029, 047, 051, 052, 063) | 1.19.5 | 1.19.6 | npm `opencode-ai` |
| opencode 2 | 2.2.5 (facts 063, 086) | 2.2.5 | 2.3.2 | npm `@opencode/cli` |

Gemini CLI has no stable release after the corpus version. Each other
agent has a release after the newest corpus version. Copilot CLI is 9
releases behind, and its corpus screens come only from the first start.

For the Cursor CLI, the version is the download URL in the install script.
The Cursor CLI has no public release notes on GitHub. Its changelog was
not checked.

## How the quotes were checked

The quotes were downloaded on 2026-11-18 from these sources:

- Claude Code: `CHANGELOG.md` on the `main` branch of
  `anthropics/claude-code`. The sections 2.1.320 to 2.1.327 were read.
- Codex CLI: the GitHub releases `rust-v0.169.1` and `rust-v0.170.0`.
- agy: the GitHub releases `1.5.10` and `1.5.11`.
- Copilot CLI: the GitHub releases `v1.0.106` to `v1.0.114`.
- Gemini CLI: the GitHub release `v0.69.0-preview.0`.
- opencode: the GitHub releases `v1.19.6`, `v2.2.6`, `v2.2.7`, `v2.3.0`,
  `v2.3.1` and `v2.3.2` of `anomalyco/opencode`.

A keyword search selected the lines. The search words were about screens,
dialogs, hooks, sessions, processes, files and terminal status. A line
that the search did not find can also make a fact stale.

## Findings, in order of impact

"High" means that a finding can change a screen in `corpus/` or a signal
that aw or tg-bridge reads now. "Medium" means that it can change a fact
that no tool reads yet, or a signal in a mode that the tools do not use.
"Low" means that a fact can need one more line.

### 1. Claude Code permission dialogs stop at No (high)

- Version: 2.1.327.
- Line: "Changed the arrow keys on most permission prompts to stop at No
  instead of wrapping around; a number past the last answer moves to No"
- Source: <https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md>
- Facts at risk: 004, 033, 074. A tool that sends a digit past the last
  option now selects No.
- Measurement: the kit step `permission-bash` with each digit from 1 to 9.
  Record the selected option.

### 2. Claude Code reads Esc on a new permission dialog (high)

- Version: 2.1.327.
- Line: "Fixed Esc being ignored on a permission prompt that had just
  appeared"
- Source: <https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md>
- Facts at risk: 074. An early Esc can now close the dialog.
- Measurement: send Esc 0 ms, 100 ms and 500 ms after the first frame of
  the dialog. Capture the screen after each key.

### 3. Copilot CLI sends the program status to the terminal (high)

- Version: 1.0.106 (stable). The 2026-11-04 file had this line only in a
  pre-release.
- Line: "Interactive CLI reports program status to supporting terminals,
  including when attention is needed."
- Source: <https://github.com/github/copilot-cli/releases/tag/v1.0.106>
- Facts at risk: 030. A new escape sequence can be a busy and wait signal
  that does not come from the screen text.
- Measurement: run `scenarios/first-run.sh copilot copilot` on 1.0.114 and
  keep the raw pane bytes. Search them for OSC 9;4 and OSC 7501.

### 4. Copilot CLI shows no startup tips (high)

- Version: 1.0.106 (stable).
- Line: "New sessions no longer show startup tips under the header."
- Source: <https://github.com/github/copilot-cli/releases/tag/v1.0.106>
- Facts at risk: 030, 052, and the Copilot first screens in `corpus/`.
- Measurement: the scenarios workflow, job `first-run`. Compare the screen
  after 20 s with the corpus screen.

### 5. Claude Code redraws less in tmux 3.7 (high)

- Version: 2.1.326.
- Line: "Fixed typing and spinners redrawing the whole pane in tmux 3.7"
- Source: <https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md>
- Facts at risk: none by name. A reader that reads the raw pane output
  in tmux 3.7 gets fewer full frames.
- Measurement: record the pane output with `pipe-pane` in tmux 3.7 during
  a busy turn. Count the full redraws.

### 6. Claude Code OSC 7501 status for dialogs and background work (high)

- Version: 2.1.326.
- Lines: "Fixed terminals that support the Program Status Protocol (OSC
  7501) not seeing Claude Code as waiting on you while the folder trust
  prompt is open (anthropics/claude-code#105801)" and "Improved Program
  Status Protocol (OSC 7501) reports: background commands, monitors and
  MCP tasks are listed, and a session waiting on them shows as working
  instead of done"
- Source: <https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md>
- Facts at risk: none. No fact records OSC 7501 yet. It is a busy and wait
  signal that does not come from the screen text.
- Measurement: keep the raw pane bytes of the kit steps `first-run`,
  `permission-bash` and `interrupt`. Search them for OSC 7501.

### 7. agy OSC 7501 status for background work (medium)

- Version: 1.5.10.
- Line: "Fixed OSC 7501 terminal status showing the session as done while
  the agent was paused waiting for background subagents or tasks to
  finish; [...]"
- Source: <https://github.com/google-antigravity/antigravity-cli/releases/tag/1.5.10>
- Facts at risk: 028. The turn signals can now include a terminal status.
- Measurement: keep the raw pane bytes of the agy kit steps and search them
  for OSC 7501.

### 8. Claude Code folder trust under a trusted parent (medium)

- Version: 2.1.326.
- Line: "Fixed Up then Enter answering Yes at the folder trust prompt shown
  under an already trusted parent folder"
- Source: <https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md>
- Facts at risk: 010.
- Measurement: start Claude Code in a new folder under a trusted folder.
  Capture the trust dialog, then send Up and Enter.

### 9. Claude Code agent rows under the box (medium)

- Version: 2.1.326.
- Line: "Fixed the agent rows under the prompt showing an agent as busy
  after its turn ended: the row now says what it is waiting on, and
  `/tasks` names the subagent behind each background command"
- Source: <https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md>
- Facts at risk: none by name. A reader that reads the rows under the box
  as busy can now get a wait text.
- Measurement: start a background subagent and capture the idle screen.

### 10. Claude Code `esc to interrupt` after a paste (medium)

- Version: 2.1.326.
- Line: "Fixed the "paste again to expand" hint hiding the mode and "esc
  to interrupt" after a paste was sent or deleted"
- Source: <https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md>
- Facts at risk: none by name. A busy reader that looks for
  `esc to interrupt` now finds it after a paste.
- Measurement: paste a long text, send it, and capture the busy screen.

### 11. agy blocks `~/.config` in the terminal sandbox (medium)

- Version: 1.5.10.
- Line: "Changed the terminal sandbox to block sandboxed commands from
  reading `~/.config` (or your `XDG_CONFIG_HOME`) and, on Windows,
  `AppData\Roaming` by default, [...]"
- Source: <https://github.com/google-antigravity/antigravity-cli/releases/tag/1.5.10>
- Facts at risk: 085. A hook or a command that reads `~/.config` can fail.
- Measurement: the agy permission steps of the kit. Run a command that
  reads a file in `~/.config`.

### 12. agy `acp` stops subagents on cancel (medium)

- Version: 1.5.10.
- Line: "Fixed `agy acp` leaving a session's subagents and background
  tasks, such as dev servers, running after the editor canceled a prompt
  or closed the session, [...]"
- Source: <https://github.com/google-antigravity/antigravity-cli/releases/tag/1.5.10>
- Facts at risk: 089, 092 (the process tree and the open files).
- Measurement: start `agy acp` from a pipe, cancel a prompt, and record the
  process tree.

### 13. Copilot CLI marks a resumed session as in use (medium)

- Version: 1.0.110.
- Line: "A session reopened with `copilot --resume` is marked in use as
  soon as it opens, so `copilot -p --resume` and a second window no longer
  write into it while it sits idle"
- Source: <https://github.com/github/copilot-cli/releases/tag/v1.0.110>
- Facts at risk: 050 (the state folders of Copilot).
- Measurement: resume a session and list the files in `~/.copilot`.

### 14. Copilot CLI permission dialogs in short terminals (medium)

- Version: 1.0.112.
- Line: "Tool permission prompts keep their title and selected answer
  visible in short terminals, with PgUp/PgDn to scroll command or file
  details"
- Source: <https://github.com/github/copilot-cli/releases/tag/v1.0.112>
- Facts at risk: none. The corpus has no Copilot permission screen.
- Measurement: none until the kit has a Copilot permission step.

### 15. Copilot CLI moves the XDG folder into `~/.copilot` (medium)

- Version: 1.0.106 (stable).
- Line: "The move of an older `$XDG_CONFIG_HOME/.copilot` directory into
  `~/.copilot` now also brings over your MCP servers, language servers,
  saved folder permissions, personal instructions, custom agents and
  skills, [...]"
- Source: <https://github.com/github/copilot-cli/releases/tag/v1.0.106>
- Facts at risk: 050.
- Measurement: the scenario `first-run` with `XDG_CONFIG_HOME` set in the
  throwaway folder.

### 16. opencode 2 shows a short transcript (medium)

- Version: 2.3.0.
- Line: "Transcript verbosity now defaults to `low`, which summarizes each
  run of tools and thoughts into one activity row. [...]"
- Source: <https://github.com/anomalyco/opencode/releases/tag/v2.3.0>
- Facts at risk: 086, and the opencode 2 screens in `corpus/`. A tool call
  can show as one row.
- Measurement: the kit set b of the scenarios workflow. Compare the screens
  with the 2.2.5 screens.

### 17. opencode 2 subagents run in the background (medium)

- Version: 2.3.0.
- Line: "Subagents now always run in the background, return their session
  ID immediately, and report results to their parent whenever they become
  idle."
- Source: <https://github.com/anomalyco/opencode/releases/tag/v2.3.0>
- Facts at risk: 063. An idle parent can have a busy child session.
- Measurement: start a subagent and record the service process and the
  session list.

### 18. opencode 2 shell commands leave no zombie (low)

- Version: 2.3.2.
- Line: "Fixed finished shell commands leaving zombie processes under
  `opencode-pty`. [...]"
- Source: <https://github.com/anomalyco/opencode/releases/tag/v2.3.2>
- Facts at risk: 063. The process tree has fewer children.
- Measurement: run a shell command and record the process tree.

### 19. Codex CLI status lines in unfocused panes (low)

- Version: 0.170.0.
- Line: "#61141 Preserve multiline status lines in unfocused chat panes"
- Source: <https://github.com/openai/codex/releases/tag/rust-v0.170.0>
- Facts at risk: 020. The screen shape can change in a pane without
  focus.
- Measurement: the kit set d of the scenarios workflow. Compare the screens
  with the 0.169.0 screens.

### 20. Codex CLI keeps sandbox rules in permission updates (low)

- Version: 0.170.0.
- Line: "Fixed permission updates and child threads losing existing sandbox
  restrictions. (#60936, #61134)"
- Source: <https://github.com/openai/codex/releases/tag/rust-v0.170.0>
- Facts at risk: 036. The approval dialog can open for other actions.
- Measurement: the Codex permission steps of the kit.

### 21. Claude Code `claude -p` on a terminal (low)

- Version: 2.1.325. Fact 087 measured 2.1.319.
- Line: "Fixed `claude -p` text output on a terminal passing control
  sequences other than text styling; pipes and files are unchanged"
- Source: <https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md>
- Facts at risk: none. Fact 087 uses stream-json on a pipe.
- Measurement: none needed now.

### 22. Gemini CLI folder trust in the macOS sandbox (low, preview only)

- Version: 0.69.0-preview.0 (pre-release).
- Line: "fix(cli): resolve folder trust before entering the macOS Seatbelt
  sandbox"
- Source: <https://github.com/google-gemini/gemini-cli/releases/tag/v0.69.0-preview.0>
- Facts at risk: 090 on macOS.
- Measurement: wait for 0.69.0. Then run the kit set e on macOS.

## Not covered

- The Cursor CLI changelog was not read. The table gives only the version.
- Codex CLI 0.169.1 has no release notes. Its compare page was not read.
- The agents in groups b, c and d of the first-run job were not checked.
  The newest release of each one was not read.
- Pre-releases are listed only when the change can change a screen or a
  file. A pre-release can change again before it becomes `latest`.
- The findings of the 2026-11-04 file that are not repeated here were not
  measured again. Read that file in the git history.
