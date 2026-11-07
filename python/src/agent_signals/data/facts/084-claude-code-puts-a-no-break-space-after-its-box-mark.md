# 084. Claude Code puts a no-break space after its box mark

## Measured

2026-11-07 (UTC), Claude Code 2.1.319 on Linux (x64), in tmux, with the
fake model of the kit. The operator runs of the agent kit 0.16.0 on Ubuntu
24.04.5 and macOS 26.6.2 used the same Claude Code version with a real
login. Measured on: real machine.

## What was measured

1. While the input box holds typed text, the box line is `❯`, then the
   bytes `C2 A0` (U+00A0, a no-break space), then the text. A capture with
   `tmux capture-pane -p` keeps these bytes.
2. After the prompt is sent, the line of the prompt in the chat above the
   box has a plain space (`20`) after `❯`.
3. In the operator run on Ubuntu, the kit typed each Claude prompt three
   times: `grep -E '(^|[[:space:]])TEXT'` did not find the typed text. In
   the operator run on macOS, the same check found the text.
4. On the host of the measurement, with `LANG=en_US.UTF-8`, `[[:space:]]`
   in GNU grep matched `C2 A0`. With `LC_ALL=C`, it did not.

## Mechanism

Not known. Claude Code draws the box line with a no-break space only while
the box holds text.

A reader that looks for the typed text in the box must accept `C2 A0` as a
space. `[[:space:]]` depends on the locale. In .NET, `\s` matches U+00A0.

## Incident

The kit typed the prompt again two times and sent it after 12 s. The step
`send` in `probes/agent/steps/session-step.sh` now accepts the no-break
space.

## Screens

None.

## Not measured

- The locale of the Ubuntu host of the operator.
- Windows.
- Other Claude Code versions.
