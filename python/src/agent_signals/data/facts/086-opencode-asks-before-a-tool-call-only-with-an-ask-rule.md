# 086. opencode asks before a tool call only with an ask rule

## Measured

2026-11-08 (UTC), opencode 2.2.5 on Linux (x64), with the agent kit
(`--home fixture`, backends tmux and pty) and the fake model of the kit.
Each step ran one time on each backend. Measured on: real machine.

## Conditions

The kit steps `permission-opencode`, `interrupt-opencode`,
`write-opencode-MODE` and `write-outside-opencode-MODE`
(`probes/agent/steps.tsv`) recorded the conditions of each run:

- `opencode --standalone`: a private server that ends with the TUI, not
  the background service.
- A new home that the kit made. Its only settings file is
  `.config/opencode/opencode.json`, with the provider of the fake model
  (`@ai-sdk/openai-compatible`) and the keys `autoupdate`, `model`,
  `provider` and `share`. It has no permission rule.
- The permission rule of a step comes from the variable
  `OPENCODE_CONFIG_CONTENT`, for example
  `{"permission":{"edit":"ask"}}`.
- A new, empty work folder with no project settings file in it or in a
  folder above it.
- The work folder and the outside folder were not in a temp folder.
- A clean environment: only HOME, PATH, TERM, USER, LANG, and the
  variables of the fake model and of the step.

The fake model answers the prompt with one call of the tool `write`
(`{path, content}`), or `shell` (`{command}`) for the shell step. It reads
the work folder from the line `Working directory: ` of the system prompt.

## What was measured

| Step (rule in `OPENCODE_CONFIG_CONTENT`, options) | Result, tmux and pty |
|---|---|
| shell command, `{"permission":{"bash":"ask"}}` | dialog |
| write in the work folder, no rule | written, no dialog |
| write in the work folder, `{"permission":{"edit":"ask"}}` | dialog |
| write in the work folder, `{"permission":{"edit":"ask"}}`, `--auto` | written, no dialog |
| write outside the work folder, no rule | written, no dialog |
| write outside the work folder, `{"permission":{"edit":"ask"}}` | dialog |
| write outside the work folder, `{"permission":{"external_directory":"ask"}}` | dialog |

More results:

1. The dialog draws in the transcript area. Its first line is
   `△ Permission required`. The next line names the call:
   `→ Edit agent-signals-write.txt`, `$ touch agent-signals-test.txt`, or
   `← Access external directory DIR` with a `Patterns` list. The options
   are in one row with no numbers: `Allow once   Always allow   Reject`,
   then `⇆ select  enter confirm`.
2. Esc on the dialog stopped the whole turn. The turn line then ended with
   `interrupted`, and no file was written.
3. The busy screen shows a moving bar and `esc interrupt` below the box.
   One Esc changes the text to `esc again to interrupt`. A second Esc 2 s
   later stopped the turn, and the turn line ended with `interrupted`.
4. The idle screen and the busy screen both show `ctrl+p commands` in the
   footer. A reader must check for `esc interrupt` first.
5. The system prompt of opencode 2.2.5 says: "Prefer /tmp/opencode over
   generic system temporary directories such as /tmp; it is pre-created
   and approved for external access."

## Mechanism

The source of opencode at the commit of version 2.2.5 sets the default
permission rule to allow each action, except a read of a `.env` file. The
last rule that matches a call wins. A path outside the work folder asks
for the action `external_directory`, which the default rule also allows.
The legacy key `permission` maps `edit` and `bash` to the actions `edit`
and `shell`. This project read the source; the table above is the measured
result.

## Screens

- `corpus/opencode2/screens/busy-v2-2-5.screen`
- `corpus/opencode2/screens/permission-edit-v2-2-5.screen`
- `corpus/opencode2/screens/permission-shell-v2-2-5.screen`

## Not measured

- opencode with a real model and a real login, and with a settings file
  of an operator.
- opencode without `--standalone`: the background service (fact 63).
- The folder `/tmp/opencode` and other temp folders.
- `Allow once`, `Always allow` and `Reject` as answers.
- opencode 1.x, macOS and Windows, and the backends conpty and psmux.
- More than one run of each step.
