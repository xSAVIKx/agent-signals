"""Tests for the parts of scenarios/conpty.py that run on Linux too: the
pyte screen, the screen format, and the helpers. pywinpty runs only on
Windows, so the ConPTY class has no test here.

Run: python -m unittest discover -s scenarios/tests
Needs: pyte (the version that the workflows pin). The tmux test runs only
when tmux is installed.
"""

import os
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import conpty  # noqa: E402


def screen_of(text, cols=conpty.COLS, rows=conpty.ROWS):
    t = conpty.Terminal(cols, rows)
    t.feed(text)
    return t.text()


def top(text, cols=conpty.COLS, rows=conpty.ROWS):
    """The screen with the empty lines at the bottom removed."""
    out = screen_of(text, cols, rows)
    lines = out.split("\n")
    assert len(lines) == rows + 1 and lines[-1] == "", "not one line for each row"
    return "\n".join(lines[:-1]).rstrip("\n") + "\n"


# Inputs for the comparison with tmux. Each one is plain VT output, as a
# TUI writes it.
SAMPLES = {
    "plain": "hello\r\nworld   \r\n",
    "clear-and-move": "junk\x1b[2J\x1b[H\x1b[5;10Hx\x1b[1;1Htop",
    "styles": "\x1b[1;31mred\x1b[0m \x1b[38;5;99mviolet\x1b[0m\x1b[7m inv \x1b[m",
    "box": "\u256d" + "\u2500" * 20 + "\u256e\r\n\u2502 > Try \"fix lint\"   \u2502\r\n\u2570" + "\u2500" * 20 + "\u256f\r\n",
    "wide": "\u65e5\u672c\u8a9e | \u2713 ok\r\n\u276f Trust and continue\r\n",
    "wrap": "x" * 130 + "\r\nnext",
    "erase-line": "abcdef\x1b[3G\x1b[K\r\n12345\x1b[2D\x1b[1K",
    "title-and-modes": "\x1b]0;agent title\x07\x1b[?25l\x1b[?2004hready\x1b[?25h",
    "scroll": "".join("line %d\r\n" % i for i in range(60)),
}


class ScreenFormat(unittest.TestCase):
    def test_plain_lines(self):
        self.assertEqual(top("hello\r\nworld   "), "hello\nworld\n")

    def test_one_line_for_each_row(self):
        self.assertEqual(screen_of(""), "\n" * conpty.ROWS)
        self.assertEqual(screen_of("x", 10, 3), "x\n\n\n")

    def test_bottom_blank_lines_go_inner_ones_stay(self):
        self.assertEqual(top("a\r\n\r\n\r\nb\r\n\r\n"), "a\n\n\nb\n")

    def test_inner_spaces_stay(self):
        self.assertEqual(top("a    b   "), "a    b\n")

    def test_cursor_move_and_clear(self):
        self.assertEqual(top("junk\x1b[2J\x1b[3;5Hx"), "\n\n    x\n")

    def test_styles_go(self):
        self.assertEqual(top("\x1b[1;31mred\x1b[0m ok"), "red ok\n")

    def test_wide_characters_take_two_cells(self):
        out = top("\u65e5\u672c|x")
        self.assertEqual(out, "\u65e5\u672c|x\n")
        t = conpty.Terminal()
        t.feed("\u65e5\u672c|")
        self.assertEqual(t.screen.cursor.x, 5)

    def test_wrap_at_120_columns(self):
        self.assertEqual(top("x" * 125), "x" * 120 + "\n" + "xxxxx\n")

    def test_size_is_120_by_40(self):
        lines = screen_of("".join("%d\r\n" % i for i in range(100))).split("\n")
        self.assertEqual(len(lines), conpty.ROWS + 1)
        self.assertEqual(lines[0], "61")
        self.assertEqual(lines[-3], "99")

    def test_broken_sequence_does_not_raise(self):
        t = conpty.Terminal()
        t.feed("\x1b[9999999999999999999;99999999999999999H\x1b[?1049h\x1b[Hok")
        self.assertTrue(t.text().startswith("ok\n"))


class Replies(unittest.TestCase):
    def test_cursor_position_and_attributes(self):
        got = []
        t = conpty.Terminal(reply=got.append)
        t.feed("\x1b[3;4H\x1b[6n\x1b[c\x1b[5n")
        self.assertEqual(got, ["\x1b[3;4R", "\x1b[?6c", "\x1b[0n"])

    def test_no_reply_callback(self):
        t = conpty.Terminal()
        t.feed("\x1b[6n")
        self.assertEqual(t.text(), "\n" * conpty.ROWS)


class Helpers(unittest.TestCase):
    def test_replace_dir_any_form(self):
        d = r"D:\a\_temp\run.abc"
        text = r"x D:\a\_temp\run.abc\home\.claude d:/a/_temp/RUN.abc/work y"
        self.assertEqual(conpty.replace_dir(text, d), "x <sandbox>\\home\\.claude <sandbox>/work y")

    def test_sandbox_env(self):
        base = {"Path": r"C:\bin", "SYSTEMROOT": r"C:\Windows", "SECRET_TOKEN": "x",
                "USERPROFILE": r"C:\Users\real", "GITHUB_TOKEN": "y"}
        env = conpty.sandbox_env(base, r"D:\t\run.1\home")
        self.assertEqual(env["PATH"], r"C:\bin")
        self.assertEqual(env["SystemRoot"], r"C:\Windows")
        self.assertNotIn("SECRET_TOKEN", env)
        self.assertNotIn("GITHUB_TOKEN", env)
        self.assertEqual(env["USERPROFILE"], r"D:\t\run.1\home")
        self.assertEqual(env["HOME"], r"D:\t\run.1\home")
        self.assertEqual(env["HOMEDRIVE"], "D:")
        self.assertEqual(env["HOMEPATH"], r"\t\run.1\home")
        self.assertEqual(env["APPDATA"], r"D:\t\run.1\home\AppData\Roaming")
        self.assertEqual(env["LOCALAPPDATA"], r"D:\t\run.1\home\AppData\Local")
        self.assertEqual(env["TEMP"], env["TMP"])
        self.assertEqual(env["USERNAME"], "dev")

    def test_descendants_skip_reused_pids(self):
        table = {
            1: (0, 100.0),
            2: (1, 101.0),   # child of 1
            3: (2, 102.0),   # grandchild
            4: (1, 50.0),    # older than 1: its parent pid was reused
            5: (3, 103.0),
        }
        self.assertEqual(conpty.descendants(table, 1), [2, 3, 5])

    def test_diff_entries(self):
        before = {"a": (True, 0, 1), "b": (False, 3, 1), "c": (False, 1, 1)}
        after = {"a": (True, 0, 1), "b": (False, 4, 2), "d": (False, 1, 1)}
        self.assertEqual(conpty.diff_entries(before, after), ["changed b", "gone c", "new d"])

    def test_list_files_and_tree_entries(self):
        d = tempfile.mkdtemp()
        try:
            os.makedirs(os.path.join(d, "home", ".x", "y"))
            with open(os.path.join(d, "home", ".x", "y", "f.json"), "w") as f:
                f.write("{}")
            rows = conpty.list_files(os.path.join(d, "home"), d)
            self.assertEqual(len(rows), 1)
            size, mtime, path = rows[0].split(" ", 2)
            self.assertEqual((size, path), ("2", "<sandbox>/home/.x/y/f.json"))
            self.assertTrue(mtime.isdigit())
            e = conpty.tree_entries([os.path.join(d, "home")], depth=2)
            self.assertEqual(sorted(os.path.relpath(p, d) for p in e),
                             [os.path.join("home", ".x"), os.path.join("home", ".x", "y")])
        finally:
            shutil.rmtree(d)


@unittest.skipUnless(shutil.which("tmux"), "tmux is not installed")
class SameAsTmux(unittest.TestCase):
    """pyte must give the same text as tmux capture-pane -p for the same
    output."""

    def tmux_screen(self, data):
        d = tempfile.mkdtemp()
        sock = "conpty-test-%d" % os.getpid()
        try:
            f = os.path.join(d, "in")
            with open(f, "w", encoding="utf-8", newline="") as fh:
                fh.write(data)
            env = {"PATH": os.environ.get("PATH", ""), "LANG": "C.UTF-8", "TERM": "xterm-256color"}
            subprocess.run(["tmux", "-L", sock, "-f", "/dev/null", "new-session", "-d", "-s", "t",
                            "-x", str(conpty.COLS), "-y", str(conpty.ROWS),
                            "stty raw -echo; cat %s; sleep 30" % shlex.quote(f)],
                           check=True, env=env)
            time.sleep(1.0)
            out = subprocess.run(["tmux", "-L", sock, "capture-pane", "-p", "-t", "t"],
                                 check=True, capture_output=True, env=env).stdout
            return out.decode("utf-8")
        finally:
            subprocess.run(["tmux", "-L", sock, "kill-server"], capture_output=True)
            shutil.rmtree(d)

    def test_samples(self):
        for name, data in SAMPLES.items():
            with self.subTest(name):
                self.assertEqual(screen_of(data), self.tmux_screen(data))


if __name__ == "__main__":
    unittest.main()
