# 002. A dialog can draw above a live input box

## Measured

2026-09-28, Claude Code 2.1.283, on two live sessions.

## What was measured

The auto mode environment dialog draws a numbered list and the footer "Enter
to confirm · Esc to cancel" between two rules ABOVE the input box. The box
below it keeps its frame and the text that the operator did not send. The last
line-starting mark is the mark of the box, so each marker of the dialog is
outside the input region, and the frame test gives IDLE.

## Mechanism

A reader needs two conditions together to find this dialog: a numbered list
under a cursor mark in the block between the rules above the box, and the
footer text in that block. One condition alone is not sufficient. A reply
often holds a numbered list above the box, and a reply can quote the footer as
prose. The corpus holds one negative control for each condition.

A reply that quotes a whole dialog holds both conditions. No text on the
screen tells the quote apart from a real dialog. A reader that reads the quote
as a dialog sends no key, which is safe. This is a known false positive.

The defence that also covers the next new shape is a proof of submission:
after the Enter, prove that the framed box no longer holds the text. The proof
applies to a framed box only. A pane with no frame can keep the echo of the
text below the mark after a submission.

## Incident

A tool typed a message into each of the two sessions, proved that the text was
visible, and sent an Enter. The dialog took the Enter. The text stayed in the
box, and the Enter confirmed the selected option. In one session option 1 was
confirmed, and a setup command ran. Nothing measured who pressed that Enter.

## Screens

`claude/dialog-over-box`, `claude/overlay-without-footer`,
`claude/overlay-plain-list`, `claude/overlay-footer-without-options`,
`claude/quoted-dialog`.

## Not measured

Whether a digit activates an option of this dialog. Its footer says "Enter to
confirm", and no test proves a digit. The size of the pane. Whether other
dialogs draw above the box. agy 1.4.5 draws no dialog above the box (fact 18).

## Source

Measured by the tg-bridge project. The text is a summary of its notes, and it
holds no host details and no session details.
