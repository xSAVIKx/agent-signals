# 090. Gemini CLI asks before a write in the workspace only, and runs on a local fake model

## Measured

2026-11-14 (UTC), Gemini CLI 0.68.0 (npm `@google/gemini-cli`), on Linux
(Debian 13, x64), with the agent kit (`--home fixture`, backends tmux and
pty) and the fake model of the kit. Two runs of the 21 Gemini steps of
`probes/agent/steps.tsv`: the first with an answer to the trust question,
the second with `--skip-trust`. Then kit sessions for the corpus screens,
and one kit session in the modes `plan` and `default` to read the tool
result in the chat file of the fixture home. The fixture home holds only
the fixed text of the fake model. Measured on: real machine.

## What was measured

1. Gemini CLI runs against a local server with `GEMINI_API_KEY=dummy`,
   `GOOGLE_GEMINI_BASE_URL=http://127.0.0.1:<port>` and
   `security.auth.selectedType` `gemini-api-key` in
   `~/.gemini/settings.json`. Plain HTTP is accepted for 127.0.0.1.
2. Each prompt sent two requests. The first was `generateContent` for the
   model `gemini-3.5-flash-lite` with a JSON schema: the model router of
   the model setting "Auto". The second was `streamGenerateContent?alt=sse`
   for the model `gemini-3.1-pro-preview-customtools`, with 16 tools, among
   them `run_shell_command`, `write_file` and `replace`. The first user
   message names the work folder below "Workspace Directories".
3. In a new work folder, Gemini CLI asks "Do you trust the files in this
   folder?". The answer "Trust folder" restarts it ("Gemini CLI is
   restarting to apply the trust changes..."). In the first run, in 4 of 22
   session steps, the question came after the idle screen showed, about
   3 s after the start, and the prompt that the kit typed went into the
   dialog. With `--skip-trust`, no question showed, and no step of the
   second run had to type its prompt again.
4. The idle screen shows the placeholder "Type your message or
   @path/to/file" in the input box. The box stays while Gemini CLI works.
   The busy line above the box is "⠸ Thinking... (esc to cancel, 1s)". One
   Esc cancels the turn and prints "Request cancelled.". After that, one
   Ctrl+C prints "Press Ctrl+C again to exit." and does not end the
   session.
5. A shell command in the default approval mode opens a framed dialog in
   place of the input box: "Allow execution of [Shell]?" with three
   numbered options. Esc takes "No, suggest changes (esc)" and cancels the
   turn.
6. A file write in the work folder, by approval mode:

   | Mode (`--approval-mode`) | Dialog | File written |
   |---|---|---|
   | `default` | "Apply this change?", four options | no (Esc) |
   | `auto_edit` | none | yes |
   | `yolo` | none | yes |
   | `plan` | none | no |

   In the mode `plan`, the tool result was "Access denied: plan path (...)
   must be within the designated plans directory (...)". The plans
   folder is below `~/.gemini/tmp/<project>/<session id>/plans`.
7. A file write outside the work folder, in a new folder next to it that
   is not a temp folder, gave no dialog and no file in the modes
   `default`, `auto_edit` and `yolo`. The tool result was "Path not in
   workspace: Attempted path "..." resolves outside the allowed workspace
   directories: <work folder> or the project temp directory:
   ~/.gemini/tmp/<project>". The screen showed only the text reply of
   the fake model.
8. Each session wrote its chat to
   `~/.gemini/tmp/<project>/chats/session-<date>T<time>-<id>.jsonl` and
   changed `~/.gemini/tmp/<project>/logs.json` and `~/.gemini/state.json`.

## Mechanism

Gemini CLI checks the path of a file tool against the workspace before it
asks. A path outside the work folder and the project temp folder is an
error for the model, not a question for the person. So the question
"does the agent ask before a write outside the work folder" has the answer
"no dialog, and no write" for Gemini CLI. Claude Code and agy ask in that
case (fact 085). A reader that waits for a dialog after such a write waits
for nothing: the turn ends with a text reply.

The idle screen and the busy screen both show the input box. A reader
must look for the busy line ("esc to cancel") or a dialog, as for Codex
and Claude Code. The kit rows of Gemini CLI use these regexes.

The trust question can come after the first idle screen. A driver that
types at once can lose the prompt. `--skip-trust` trusts the folder for
one session. The Gemini CLI documentation says that it writes nothing to
`~/.gemini/trustedFolders.json`. That was not measured.

## Incident

The first run lost the prompt in 4 of 22 steps to the late trust question
(item 3). The kit rows now start Gemini CLI with `--skip-trust` and keep
the trust question for the step `first-run-gemini`.

## Screens

`gemini/idle-v0-68-0`, `gemini/busy-v0-68-0`,
`gemini/permission-shell-v0-68-0`, `gemini/permission-write-v0-68-0`.

## Not measured

- A real model and a Google login. The fake model gives fixed answers.
- macOS and Windows, and the backends conpty and psmux.
- `--include-directories`, policy files below `~/.gemini/policies/`, and
  the settings `tools.allowed` and `tools.exclude`.
- A write in the project temp folder.
- Whether `--skip-trust` writes `~/.gemini/trustedFolders.json`.
- The resume step changed `~/.gemini/settings.json`. Which key changed
  was not read.
