# 008. A pane redraws after a key, not with it

## Measured

2026-08-13. The Claude Code version was not recorded.

## What was measured

The screen showed a `C-u` after 0.12 s and typed text after 0.13 s.

## Mechanism

Each read of the screen after a key must poll until the screen agrees. Each
poll needs a budget of its own as well as the deadline of the whole send. A
pane that starts cold draws no input line, so one attempt must not use the
whole send.

A unit test that gives a fixed list of screens models no delay and proves
nothing. Keep the state of one box in the fake, and make each key take effect
one capture later.

## Incident

A read with no wait made every message fail while the text sat in the box. The
tool typed again on each attempt, and the box held up to thirty copies of one
message.

## Screens

None.

## Not measured

The delay for agy. The delay on a loaded machine.

## Source

Measured by the tg-bridge project. The text is a summary of its notes, and it
holds no host details and no session details.
