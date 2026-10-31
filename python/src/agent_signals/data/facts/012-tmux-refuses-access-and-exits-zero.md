# 012. tmux prints an access refusal and exits 0

## Measured

The first deployment of tg-bridge, in August 2026, with tmux 3.5a. The fact
records no exact date.

## What was measured

A tmux server accepts its own user only. Each other user gets `access not
allowed`, whatever the mode and the group of the socket permit. `tmux
server-access -a -w <user>` gives a user access, and only the owner of the
server can change that list. tmux prints the refusal and then exits 0.

## Mechanism

The exit status of tmux does not show an access refusal. A tool must assert a
result, for example the output of a query, and never the exit status alone.

## Incident

None recorded.

## Screens

None.

## Not measured

Other tmux versions.

## Source

Measured by the tg-bridge project. The text is a summary of its notes, and it
holds no host details and no session details.
