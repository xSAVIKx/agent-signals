# 018. agy draws no dialog above a live box

## Measured

2026-10-24, agy 1.4.5, in a pane 120 columns wide.

## What was measured

Five shapes were checked for a dialog above a live input box (fact 2). None
does that. A dialog that asks (a file write, the question tool) draws IN PLACE
of the box. An overlay that lists items (`/model`, the `/` menu, the `?`
panel) draws BELOW the box, and its cursor line starts with `>`.

## Mechanism

For a dialog in place of the box, the last mark is the cursor of the dialog,
so it reads as a dialog. For an overlay below the box, the last mark is the
cursor of the overlay, with no frame, so it reads as UNKNOWN, and a tool sends
no key. The same screen cut below the box reads as IDLE, so the overlay alone
makes the state UNKNOWN.

## Incident

None recorded.

## Screens

`agy/file-permission`, `agy/question`, `agy/model-picker`, `agy/command-menu`,
`agy/shortcuts`.

## Not measured

Other agy dialogs. Other agy versions.

## Source

Measured by the tg-bridge project. The text is a summary of its notes, and it
holds no host details and no session details.
