# 013. A long text becomes a paste marker

## Measured

2026-10-24, Claude Code 2.1.309 and agy 1.4.5, in a pane 120 columns wide.

## What was measured

`send-keys -l` typed text into an empty box. In Claude Code, text of 801
characters or more shows as `[Pasted text #N]`, and as `[Pasted text #N +K
lines]` when it holds K line breaks. Text of 800 characters or fewer stays
text, also on 60 lines. N counts the pastes of the process from 1. The Enter
submits the whole text. The prompt in the `UserPromptSubmit` hook holds that
text inside `<pasted_content id="…">` and `</pasted_content id="…">`.

agy 1.4.5 draws no marker: a text of 3000 characters stayed text.

## Mechanism

A tool that waits to see its own text in the box never sees a long text. It
accepts the marker as its text only when the box held no marker after the
clear, and the box then holds the marker alone.

## Incident

A message of 910 characters failed after the whole send timeout with "Nothing
was sent".

## Screens

`claude/paste`, `claude/paste-lines`, `claude/paste-and-text`.

## Not measured

Other pane widths. Whether the limit of 800 characters depends on the width.

## Source

Measured by the tg-bridge project. The text is a summary of its notes, and it
holds no host details and no session details.
