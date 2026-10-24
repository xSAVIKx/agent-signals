# 001. An idle input box must be proved by its frame

## Measured

2026-08-18. The Claude Code version was not recorded. tg-bridge documents
2.1.226 on 2026-08-10 and 2.1.238 on 2026-08-20, so the version is in that
range.

## What was measured

The Rewind dialog of Claude Code draws the input mark `❯` as its list cursor,
at the start of a line. No rule of `─` is above or below that cursor. The
folder-trust menu and the permission dialog also draw an unframed `❯`. A real
input box has one rule immediately above the mark and one more rule below it.

## Mechanism

A reader that finds the input box by the last line-starting mark finds the
cursor of the modal. The text after that mark holds no known marker. A reader
that gives IDLE when no marker matches therefore gives IDLE for a live modal.

The safe order of the tests is:

1. Test the known markers: the trust question, the permission footer, the busy
   footer.
2. Test for a numbered list under an unframed cursor (fact 3).
3. Test for a dialog above a framed box (fact 2).
4. Test the frame last. A screen with no frame gives UNKNOWN. A screen with a
   frame gives IDLE.

A frame test before step 1 makes the trust menu and the permission dialog give
UNKNOWN, because both draw an unframed mark.

## Incident

A tool read the Rewind dialog as IDLE. It typed a message into the live dialog
for its whole send timeout, and it then reported that the text did not reach
the pane.

## Screens

`claude/idle`, `claude/busy`, `claude/rewind`, `claude/typed-list`,
`claude/permission`, `claude/trust`.

## Not measured

The size of the pane. The exact version. Modals other than Rewind and the
Remote Control modal (fact 16).

## Source

Measured by the tg-bridge project. The text is a summary of its notes, and it
holds no host details and no session details.
