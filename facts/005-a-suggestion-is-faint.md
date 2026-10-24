# 005. The suggestion in the input box is faint

## Measured

The suggestion: tg-bridge finding F12. The screen module of tg-bridge dates
its first screens to Claude Code 2.1.226 on 2026-08-10. The faint style:
2026-10-24, Claude Code 2.1.309, with `capture-pane -e`. agy: 2026-10-24, agy
1.4.5.

## What was measured

After a turn, the input box of Claude Code can show a probable next
instruction that nobody typed. An Enter does not submit it. `capture-pane -p`
draws it in the same way as typed text. With `capture-pane -p -e`, the
suggestion `run git status` and the placeholder `Try "how does <filepath>
work?"` of a new box have SGR 2 (faint). The same text, typed, has no SGR 2. A
`C-u` does not remove the suggestion.

## Mechanism

Text in the input region of a plain capture is not proof that the box holds
it. A tool that must know the text of the box reads the box with `-e` and
removes each faint character. agy 1.4.5 drew no suggestion and no placeholder
in the turns that were measured. agy draws its model name faint in the footer,
outside the box.

## Incident

A message that was equal to the suggestion read as a box that does not clear.
The tool typed nothing, and it failed after its whole timeout.

## Screens

`claude/suggestion`, `claude/styled-suggestion`, `claude/styled-typed-same`,
`claude/styled-placeholder`.

## Not measured

Other terminal types and other colour themes. Whether each suggestion is faint
in each version.

## Source

Measured by the tg-bridge project. The text is a summary of its notes, and it
holds no host details and no session details.
