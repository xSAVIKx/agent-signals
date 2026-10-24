# 007. The input box draws late, and early keys are lost

## Measured

Claude Code, from the first deployment of tg-bridge in August 2026. The fact
records no exact date and no version.

## What was measured

The Claude Code TUI takes about 15 seconds to draw its input box on a warm
machine, and longer on a cold one. Keys that arrive before the box go nowhere.
`C-u` empties one line only, so a message that wrapped keeps the rest.

## Mechanism

A tool must prove that its text reached the box before it sends Enter: clear
the box, type, read the screen, and repeat until the text is visible. A box
that does not clear must be refused, not typed over.

## Incident

None recorded apart from facts 8 and 9.

## Screens

None.

## Not measured

The time for agy. The distribution of the time on a loaded machine.

## Source

Measured by the tg-bridge project. The text is a summary of its notes, and it
holds no host details and no session details.
