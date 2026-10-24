# The safe answer protocol

These rules are for a tool that sends keys into the tmux pane of an agent: an
answer to a dialog, or a message for the input box. Each rule names the facts
in `facts/` that it comes from. The tg-bridge project measured these facts.

A wrong key in a live pane can end a session, confirm an option that nobody
chose, or lose a message. When a rule cannot be met, send no key, and report
the screen to the operator.

## The rules

1. **Run tmux with an argv list. Never build a shell string.** No shell then
   parses an argument, so a message that holds metacharacters stays data.
   Facts: 11.
2. **Refuse an argument that is a lone `;`, and a name that ends with `;`.**
   tmux reads such an argument as a command separator, also in argv. Do not
   depend on this refusal alone for a value that you did not validate.
   Facts: 11.
3. **Assert a result, not an exit status.** tmux prints an access refusal and
   exits 0. Facts: 12.
4. **Read the state of the pane again immediately before each key.** The
   screen changes between two reads: a wizard shows its next question, a
   suggestion appears, or another actor uses the pane. Facts: 3, 5, 16.
5. **Send no key to a screen that gives UNKNOWN.** A reader gives IDLE only
   when it proves a framed input box. A modal, an overlay, a setup screen and
   a screen with no known shape give UNKNOWN. Facts: 1, 16, 17, 18.
6. **Send no message to a dialog above a live box.** The dialog takes the
   Enter, and the text stays in the box. A known false positive (a quoted
   dialog) also gives this state, and the refusal is safe. Facts: 2.
7. **Bind each decision to the dialog that it answers.** A decision carries
   the option number and a fingerprint of the dialog: a short hash of the
   question and the numbered options that the operator saw. Before the key,
   read the dialog again and make the fingerprint again. When the two differ,
   send no key, because the same number can mean another option in another
   dialog. Facts: 3, 4.
8. **Answer a numbered dialog with its digit.** A digit activates its option at
   once, with no Enter, and it does not depend on where the mark is. After the
   key, read the screen again: the next question of a wizard fires no hook.
   For a dialog above a live box, no measurement proves that a digit
   activates an option, so treat that answer as not proved. Facts: 2, 3, 4.
9. **Prove which option of the folder-trust menu is selected before you send
   Enter.** Send Enter on the accept option only. Move the mark with Down, with
   a limit on the number of moves, and prove each move on a new screen. The
   start option differs between agents and between versions. Facts: 10.
10. **Type a message in this order:**
    1. Wait until a framed input box is visible. Keys sent before it are lost.
    2. Send `C-u` to clear the box. Prove that the box is empty. Read the box
       with `capture-pane -e`, and remove faint text, because a suggestion
       stays after `C-u`. Refuse a box that does not clear.
    3. Wait a clear gap before the text, for the first message of a new
       process.
    4. Type the text with `send-keys -l`.
    5. Poll until the text is visible in the box. A long text can show as a
       paste marker. Accept the marker only when the box held no marker
       after the clear.
    6. Send Enter.
    7. Prove that the framed box no longer holds the text. Give the agent a
       budget that grows with the length of the text.

    Facts: 2, 5, 7, 8, 9, 13, 14.
11. **Run each send with a deadline, and give each read its own budget.** A
    pane redraws after a key, not with it, so each read polls until the screen
    agrees. One read must not use the whole deadline. When the deadline ends,
    clear the box only when it holds your own text and nothing more. Then
    report that nothing was sent. Facts: 7, 8.
12. **Do not read a reply from the pane.** `capture-pane` gives the visible
    screen only. Take the reply from a hook or a session file. Facts: 6.
