# 056. Gemini CLI warns about limited colors on ubuntu-22.04

## Measured

2026-10-30, Gemini CLI 0.66.0 (npm `@google/gemini-cli`), the scenario
`scenarios/first-run.sh gemini gemini` in the scenarios workflow (run
41142220844), with a throwaway `HOME`, no login and no key. The scenario
starts the agent in a private tmux server with `tmux -f /dev/null`, so tmux
uses its default settings. The workflow uploaded the scrubbed screen after
20 s of each label as an artifact.

Measured on: CI runner ubuntu-22.04 (x64), ubuntu-22.04-arm (arm64),
ubuntu-24.04, ubuntu-26.04 (x64), ubuntu-24.04-arm, ubuntu-26.04-arm
(arm64), macos-15, macos-26 (arm64), macos-15-intel and macos-26-intel
(x64).

## What was measured

1. On ubuntu-22.04 and ubuntu-22.04-arm, Gemini CLI printed four more lines
   above its folder-trust dialog:

   ```
   ⚠  Warning: Limited color support detected (TERM=screen). Some visual elements may not render correctly. For better
      color support in tmux, add to ~/.tmux.conf:
            set -g default-terminal "tmux-256color"
            set -ga terminal-overrides ",*256col*:Tc"
   ```

2. On the other eight labels, Gemini CLI printed no such warning. The rest of
   the screen was the same on all ten labels: the dialog "Do you trust the
   files in this folder?" with the same three options.
3. The warning moves the dialog down by six lines. The question, the options
   and the selected mark do not change.

## Mechanism

The warning names `TERM=screen`. Gemini CLI reads the terminal type, and on
the two ubuntu-22.04 images it found a type with limited colors. The tmux of
an image sets `TERM` in the pane from its `default-terminal` option. The
tmux version and the `TERM` value of the other images were not recorded, so
the cause of the difference is not proved.

A reader that finds the trust dialog by its line number fails on
ubuntu-22.04. A reader that finds it by its text works on all ten labels.

## Incident

None.

## Screens

- `gemini/trust-v0-66-0` (ubuntu-24.04, no warning)
- `gemini/trust-color-warning-v0-66-0` (ubuntu-22.04, with the warning)

## Not measured

- The tmux version and the value of `TERM` in the pane on each image.
- Whether the warning goes away with `default-terminal "tmux-256color"`.
- Whether other agents change their screen with `TERM=screen`.
- Windows.
