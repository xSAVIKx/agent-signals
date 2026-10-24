# 009. A clear followed fast by text leaves an invisible character

## Measured

2026-10-19, Claude Code 2.1.302. Then 2026-10-24, Claude Code 2.1.309 and agy
1.4.5, with a load average of 15 to 47.

## What was measured

In the first seconds after the box draws, a `C-u` that text follows 20 ms
later stays in the box as an invisible character. The Enter then shows
"Removed 1 invisible character · review and press Enter to send", and it
submits nothing. An empty box shows the clear at once. With a wait of 3 s
after the box, the same keys submitted.

On 2026-10-24, with no gap after the clear, the first message of a new Claude
Code process showed the invisible character in 28 of 125 sends, up to 15.9 s
after the box first drew. A later message showed it in no send. agy showed it
in no send.

## Mechanism

A visible clear is not a finished clear. A tool waits a clear gap between the
`C-u` and the text until it has proved one submission in that process and some
time has passed since that proof. A new process needs the gap again.

## Incident

A message in the first seconds after a new session, a restart or a resume
failed in this way.

## Screens

None.

## Not measured

The shortest safe gap. The cause inside Claude Code.

## Source

Measured by the tg-bridge project. The text is a summary of its notes, and it
holds no host details and no session details.
