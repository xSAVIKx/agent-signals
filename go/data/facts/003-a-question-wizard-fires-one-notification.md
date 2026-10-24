# 003. A question wizard fires one Notification, and its review screen has no footer

## Measured

2026-09-08, Claude Code 2.1.263, on a live session.

## What was measured

An AskUserQuestion wizard of two questions fires the `Notification` hook for
its first question only. A digit activates an option at once, and the wizard
then shows its next question. No hook fires for that question. The review
screen at the end draws "1. Submit answers" and "2. Cancel" under the cursor,
with no footer, so the "Esc to cancel" marker is absent.

## Mechanism

A tool that waits for a hook does not learn about the next question. A tool
must read the screen again after each key that it sends to a dialog. A reader
must read a numbered list under an unframed cursor as a dialog. The frame
keeps text that is typed into a real box out of this rule. The Rewind list and
the Remote Control modal have no numbers, so the rule does not reach them.

## Incident

A tap answered the first question of a wizard. The session then waited thirty
minutes on the second question, and nobody was told about it. Until that day
the review screen read as UNKNOWN, so the tool refused the one key that ends
the wizard.

## Screens

`claude/ask`, `claude/review`, `claude/typed-list`.

## Not measured

A wizard of more than two questions. The size of the pane.

## Source

Measured by the tg-bridge project. The text is a summary of its notes, and it
holds no host details and no session details.
