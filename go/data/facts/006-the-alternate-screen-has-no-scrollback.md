# 006. A pane in the alternate screen has no scrollback

## Measured

On a live Claude Code session. The fact records no date and no version. The
gated contract lane of tg-bridge checks it again for each new version.

## What was measured

Claude Code switches to the alternate screen. tmux keeps that screen apart
from the history. The live session gave `alternate_on=1` and
`history_size=0/2000` after two hours. `capture-pane -S -200` returned about
24 lines.

## Mechanism

`capture-pane` returns the visible screen and nothing more. Text that scrolled
away is absent, not short. A tool that needs the reply of a turn must take it
from a hook or a session file, not from the pane.

## Incident

The first capture tests captured a plain shell. A plain shell uses the normal
screen, which has scrollback, so the tests passed one step away from the
defect.

## Screens

None.

## Not measured

agy. The fact names Claude Code only.

## Source

Measured by the tg-bridge project. The text is a summary of its notes, and it
holds no host details and no session details.
