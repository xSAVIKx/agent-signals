# 010. The folder-trust menu of Claude Code reversed in 2.1.251

## Measured

2026-09-01, Claude Code 2.1.251. agy: 2026-10-23, agy 1.4.5.

## What was measured

Before 2.1.251, the options were numbered, and the mark started on "1. Yes, I
trust this folder". From 2.1.251, the options have no numbers, the order is
reversed, and the mark starts on "No, exit". A bare Enter ends the session.
One Down moves the mark to "Yes, I trust this folder".

The menu of agy 1.4.5 lists "Yes, I trust this folder" first, and the mark
starts on it.

## Mechanism

A tool must prove which option is selected before it sends Enter, and send
Enter on the accept option only. It sends Down while the mark is elsewhere,
with a limit on the number of moves, and it proves each move on a new screen.

## Incident

A tool sent a bare Enter to the menu, and the session ended. Eleven patch
versions passed with no contract run. The running deployment reported nothing,
because the menu shows only in a folder that Claude Code never opened. The
gated contract lane found it.

## Screens

`claude/trust`, `claude/trust-accept-selected`, `agy/trust`.

## Not measured

The agy menu with the mark on "No, exit": agy started on the accept option.
The exact Claude Code version that made the change.

## Source

Measured by the tg-bridge project. The text is a summary of its notes, and it
holds no host details and no session details.
