# 033. The Claude Bash dialog has four options, and "3." is not "No"

## Measured

2026-10-30, Claude Code 2.1.314 with `--model haiku` and
`--permission-mode default`, on Linux (Debian 13, x64), in a private tmux
server with a throwaway `HOME`. The scenario
`scenarios/claude/dialog-states.sh` ran three times. It recorded every
hook payload, and read the pid file every 1 s for 10 s after each answer.
Measured on: real machine.

## What was measured

1. The commands `ls` and `sleep 30` (in the background) ran with no
   dialog in the default mode. Each gave `PreToolUse` and `PostToolUse`,
   and no `PermissionRequest`.
2. The command `mkdir build` opened this dialog (the path is shortened):

   ```
    Bash command
    Tip: auto mode handles these prompts for you — choose "switch to auto mode" below
    Create build directory in the work folder
    mkdir /work/example/build
    Do you want to proceed?
    ❯ 1. Yes
      2. Yes, and always allow access to /work/example from this
      3. Yes, and switch to auto mode · auto mode handles these prompts for you
      4. No
    Esc to cancel · Tab to amend
   ```

   The file-write dialog of fact 024 has three options, and its "3." is
   "No". The Bash dialog has four options, and its "No" is "4.".
3. In run 2, the scenario sent "3" to this dialog. The command ran, and
   the mode changed to auto mode for the rest of the session. The screen
   showed `⏵⏵ auto mode on`, and the next hooks had
   `permission_mode: auto`. After that, the hooks were `PostToolUse` and
   `Stop`.
4. In run 3, the scenario sent "4" ("No"). The command did not run. The
   screen showed `⎿  Interrupted · What should Claude do instead?`. No
   hook fired: no `PostToolUse` and no `Stop`. The next hook was the
   `UserPromptSubmit` of the next prompt. The pid file `status` was
   `idle` at each read, from 1 s after the key. This is the same result
   as Esc in fact 024.
5. The `PermissionRequest` payload of the Bash dialog had two
   `permission_suggestions`: `{"type": "addDirectories", "directories":
   ["/work/example"], "destination": "session"}` and `{"type": "setMode",
   "mode": "acceptEdits", "destination": "session"}`. The screen option
   "3. Yes, and switch to auto mode" has no suggestion in the payload. Its
   `tool_input` keys were `command` and `description` (run 3), or also
   `dangerouslyDisableSandbox`, `run_in_background` and `timeout`
   (run 2). The model sets these keys.

## Mechanism

The digit of "No" depends on the dialog. A tool that sends "3" as "No"
approves a Bash command and turns on auto mode. A tool must read the
digit of the "No" row from the screen, or send Esc. Esc and "No" gave the
same signals.

The number of `permission_suggestions` does not give the number of
options: two suggestions, four options.

## Incident

None. tg-bridge asked which hooks fire after "3. No", and the answer
showed that "3." is "No" only in some dialogs.

## Screens

None.

## Not measured

- "No" with text after Tab ("Tab to amend").
- "2." on the Bash dialog.
- Which commands open no dialog, other than `ls` and `sleep`.
- A Bash dialog in a folder that is not trusted, and in acceptEdits
  mode.
- Other models, macOS and Windows.
