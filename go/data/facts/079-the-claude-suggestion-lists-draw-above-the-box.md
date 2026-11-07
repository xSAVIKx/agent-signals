# 079. The Claude Code suggestion lists draw above the box

## Measured

2026-11-07 (UTC), Claude Code 2.1.318, on Linux (Debian 13, x64), in a
private tmux server at 120 x 40, with a throwaway `HOME` and no login. The
fake model of the kit (`probes/agent/fake-model.py --agent claude`)
answered on 127.0.0.1 (fact 77). The work folder held two files,
`notes.md` and `main.go`. One run of each capture. Measured on: real
machine.

## What was measured

1. `/` typed in an empty box opens the command list. The list rows are
   above the box, between the welcome header and the top rule of the box.
   No list row is below the box, and no extra rule line shows: the line
   after the last list row is the top rule of the box.
2. In the `/` list, the first row is selected. It starts with `❯ ` at
   column 2 (0-based), in SGR `38;5;153`. The other rows start with four
   spaces, in SGR `38;5;246`. So the command text starts at column 4 on all
   rows.
3. Enter with the `/` list open runs the selected command at once.
   `/add-dir` opened its dialog `Add directory to workspace`. The fake
   model got no request.
4. `@` typed in an empty box opens the file list, above the box in the same
   place. The rows were `+ notes.md`, `+ main.go`, then agent rows such as
   `* Explore (agent) – ...`. When the list opens, no row is selected: all
   rows start with four spaces, in SGR `38;5;246`.
5. Enter with the `@` list open and no row selected submits the box text
   `@` as a prompt. The fake model got one request.
6. After Down, the first row of the `@` list is selected
   (`  ❯ + notes.md`, SGR `38;5;153`). Enter then puts `@notes.md` in the
   box. Nothing is submitted, and the fake model got no request.

## Mechanism

Not known. The lists draw in the rows above the box, as a dialog does on
Claude Code (fact 2).

## Screens

No corpus screen pins this fact.

## Use

A driver must not read a box with a list open as a plain idle box. When a
list row is directly above the top rule of the box, and the box text starts
with `/` or holds `@`, an Enter can run a command or submit the text. Close
the list with Esc first.

## Not measured

- Claude Code 2.1.316 and 2.1.317, macOS and Windows.
- A list with more rows than the screen, and Tab.
- A real login. The fake model has no effect on the lists, but this was
  not checked.
