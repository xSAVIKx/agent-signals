# 014. agy reads a long text slowly, and the Enter waits behind it

## Measured

2026-10-24, agy 1.4.5.

## What was measured

The Enter was sent when the first 60 characters were visible. The box was
empty after 0.56 s at most for 301 characters, 2.94 s for 901, 6.88 s for
1501, and 16.53 s for 3001. Each length had 5 samples, and every turn ran.
With an Enter after the whole text was visible, the box was empty after 0.11
to 0.14 s.

## Mechanism

The proof that the box emptied needs a budget that grows with the length of
the text. tg-bridge uses 1 s plus 8 ms for each character, up to 25 s.

## Incident

A proof with a budget of 1 s reported that it could not prove the submission
for 3 of 3 long texts that ran.

## Screens

None.

## Not measured

Other machines and other loads.

## Source

Measured by the tg-bridge project. The text is a summary of its notes, and it
holds no host details and no session details.
