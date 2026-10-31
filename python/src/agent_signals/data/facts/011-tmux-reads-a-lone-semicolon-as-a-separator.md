# 011. tmux reads a lone ";" argument as a command separator

## Measured

tmux 3.5a, the version that the tg-bridge deployment uses. The fact records no
date.

## What was measured

A tool that runs tmux with an argv list uses no shell. The tmux parser still
reads an argument that is a single `;` as a separator between two tmux
commands. tmux also reads an argument that ends with `;` as the end of a
command.

## Mechanism

An argv list keeps shell metacharacters as data, but it does not protect
against the parser of tmux. A tool refuses an argument that is a lone `;`, and
a name that ends with `;`. A caller must not depend on that refusal alone when
it builds argv from a value that it did not validate.

## Incident

None recorded.

## Screens

None.

## Not measured

Other tmux versions.

## Source

Measured by the tg-bridge project. The text is a summary of its notes, and it
holds no host details and no session details.
