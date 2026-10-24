# 004. A digit answers a numbered dialog at once

## Measured

Claude Code permission dialog: tg-bridge finding F8. The files read for this
port do not give its date. The gated contract lane of tg-bridge checks it
again for each new version. Claude Code wizard: 2026-09-08, 2.1.263. agy
command permission: 2026-10-23, agy 1.4.5.

## What was measured

A digit key sent to a numbered permission dialog activates that option with no
Enter. The same is true for each question of an AskUserQuestion wizard and for
its review screen. In agy, a digit answers the command permission dialog with
no Enter.

## Mechanism

A digit is the safest answer to a numbered dialog, because it names one
option. It does not depend on where the mark is. A digit that goes to an idle
box becomes text in the box. A tool must therefore read the state again just
before it sends the digit.

## Incident

None recorded.

## Screens

`claude/permission`, `claude/ask`, `claude/review`, `agy/permission`,
`agy/file-permission`, `agy/question`.

## Not measured

The dialog above a live box (fact 2). The agy file-write dialog and the agy
question tool: their state was measured, but this port found no record that a
digit answers them.

## Source

Measured by the tg-bridge project. The text is a summary of its notes, and it
holds no host details and no session details.
