# 016. Remote Control draws on the same pane

## Measured

2026-08-20 (Claude Code 2.1.238), 2026-09-01 (2.1.251), 2026-09-30 (2.1.284).

## What was measured

`claude --remote-control` gives a session a second control channel. It answers
to the Claude account of the session user, from claude.ai/code and the Claude
mobile app, and it acts on the same pane.

1. 2.1.238: a pane with the flag drew a `/rc` marker at the end of the footer.
   A plain pane drew none.
2. 2.1.251: a plain pane also drew the marker, and Remote Control was on by
   default. This measurement is superseded.
3. 2.1.284: a plain pane drew no marker, not the word `remote`, and no session
   address. A pane with the flag drew all three. The marker moved to the
   header line at the top of the pane, beside the working directory.

On 2.1.251 the `/remote-control` command opened a modal with "Disconnect this
session", "Show QR code" and "Continue". The mark started on "Continue". The
modal draws the input mark with no frame. Escape closed it.

## Mechanism

A tool that reads or drives a pane is not the only actor on it. The screen can
change between two reads for a reason that the tool did not cause. A reader
must give UNKNOWN for the Remote Control modal, and a tool must send no key to
it.

## Incident

None recorded.

## Screens

None. The corpus holds no capture of the modal yet.

## Not measured

A plain session on 2.1.284 that carries no channel is an inference from the
absence of its address. Nobody opened claude.ai/code for a plain session.

## Source

Measured by the tg-bridge project. The text is a summary of its notes, and it
holds no host details and no session details.
