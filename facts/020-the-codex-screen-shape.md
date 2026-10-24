# 020. The screen shape of Codex CLI

## Measured

2026-10-24, Codex CLI 0.163.0, `codex --no-daemon` in a private tmux server,
120 columns by 40 lines. The TUI uses the alternate screen, so the pane has
no scrollback.

## What was measured

Codex draws no frame around its input box. Seven details matter to a reader.

1. The mark is `›` (U+203A), not `❯` or `>`. A message of the history also
   starts with `› `. The live box is the last line that starts with the mark.
2. No rule of `─` is above or below the box. The frame test of fact 1 cannot
   prove an idle box.
3. Under an empty box, the last line starts with `? for shortcuts`. The line
   above it gives the model and the folder. The footer line is absent while
   the box holds text, and absent under a dialog.
4. A busy turn draws `• Working (1s • esc to interrupt)` directly above the
   box. The box, its placeholder and the footer stay drawn. A background
   command adds `· 1 background terminal running · /ps to view · /stop to
   close` to the same line.
5. The empty box shows a placeholder, for example `› Ask Codex to do
   anything`. In a plain capture it looks like typed text. With `-e`, the
   placeholder is dim and typed text is not.
6. The approval dialog draws in place of the box: "Would you like to run the
   following command?", `Environment: local`, `Reason: ...`, `$ <command>`,
   then numbered options under the mark, and the footer "Press enter to
   confirm or esc to cancel". The selected option is reverse video.
7. The folder-trust dialog comes before the first box in a folder that Codex
   has not seen: "Trust this folder? ...", `› 1. Trust and continue`,
   `2. Quit`, and the footer "enter continue · esc quit". The hooks review
   dialog ("Hooks need review") can come first in a project with untrusted
   hooks.

An update banner in a box of `╭─╮` draws at the top of each start. It is not
the input box.

## Mechanism

A reader for Codex proves an idle box with all of these: the last mark line
is not a numbered option, no line of the screen holds "esc to interrupt", and
the last nonblank line starts with `? for shortcuts`. It tests the busy line
before the idle footer, because the footer stays drawn during a turn. It
gives UNKNOWN for each other screen, for example a box with typed text. This
proof is weaker than a frame: a later dialog can draw the same footer.

## Incident

None recorded.

## Screens

`codex/idle`, `codex/typed`, `codex/busy`, `codex/busy-background`,
`codex/after-turn`, `codex/approval`, `codex/approval-full`,
`codex/after-cancel`, `codex/trust`, `codex/hooks-review`.

## Not measured

The keys of the approval dialog other than Esc. The file-change approval
dialog. A narrow pane where the busy line wraps. Styled captures of each
screen. Other Codex versions, and a TUI that runs through the shared
app-server daemon.

## Source

Measured by the tg-bridge project and published in its report "Codex CLI and
Cursor CLI as harnesses: measurements, 2026-10-24", with one more capture by
the ai-world project. The text is a summary, and it holds no host details and
no session details.
