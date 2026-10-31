# 017. The screen shape of agy

## Measured

2026-10-23, agy 1.4.5, in a pane 120 columns wide.

## What was measured

agy draws the same input box as Claude Code: one rule of `─` above the input
line and one below it. Five details differ.

1. The mark is `>`, not `❯`. A message of the history also starts with `> `.
   The live box is the last one.
2. The footer of a busy pane is "esc to cancel". Claude Code draws that text
   under a permission dialog, and "esc to interrupt" during a turn.
3. A permission dialog has no frame: "Requesting permission for:", the
   command, "Run this command?", then numbered options. A digit answers it
   with no Enter.
4. The folder-trust menu starts on "Yes, I trust this folder" (fact 10).
5. The setup wizard (a colour scheme, then the terms of service) and the
   `/config` screen draw `>` with no frame and no numbered option.

## Mechanism

A reader for agy reads each line-starting `>` as the mark. It reads "esc to
cancel" as BUSY only under a framed box. It gives UNKNOWN for a setup screen,
because the answers of that screen belong to the operator. The frame test
stays last (fact 1).

## Incident

None recorded.

## Screens

`agy/idle`, `agy/typed`, `agy/busy`, `agy/permission`, `agy/trust`,
`agy/terms`, `agy/color-scheme`.

## Not measured

The trust menu with the mark on "No, exit". Other agy versions. Every corpus
screen of agy has shorter rules than the real screen.

## Source

Measured by the tg-bridge project. The text is a summary of its notes, and it
holds no host details and no session details.
