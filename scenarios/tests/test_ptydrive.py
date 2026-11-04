"""Tests for probes/agent/ptydrive.py: the pty backend of `kit session`.

ptydrive.py has its own copy of the screen format of scenarios/conpty.py,
so that the kit does not need the scenarios folder. A test here checks
that the two copies give the same text.

Run: python -m unittest discover -s scenarios/tests
Needs: pyte (the version that the workflows pin). The tests that start a
program need a Unix pty. The tmux test runs only when tmux is installed.
"""

import os
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "scenarios"))
sys.path.insert(0, os.path.join(ROOT, "probes", "agent"))
import conpty  # noqa: E402
import ptydrive  # noqa: E402
from test_conpty import SAMPLES  # noqa: E402

DRIVER = os.path.join(ROOT, "probes", "agent", "ptydrive.py")
STUB = os.path.join(ROOT, "tools", "testdata", "agent-kit", "stub-agent.sh")
COLS, ROWS = 120, 40


def pty_screen_of(text, cols=COLS, rows=ROWS):
    t = ptydrive.Terminal(cols, rows)
    t.feed(text)
    return t.text()


def conpty_screen_of(text, cols=COLS, rows=ROWS):
    t = conpty.Terminal(cols, rows)
    t.feed(text)
    return t.text()


class SameRenderAsConpty(unittest.TestCase):
    def test_samples(self):
        for name, data in SAMPLES.items():
            with self.subTest(name):
                self.assertEqual(pty_screen_of(data), conpty_screen_of(data))

    def test_private_sequences(self):
        data = "ab\x1b[?6ncd\x1b[?4mef\x1b[>4;2mgh"
        self.assertEqual(pty_screen_of(data, 20, 3), conpty_screen_of(data, 20, 3))

    def test_replies(self):
        got = []
        t = ptydrive.Terminal(reply=got.append)
        t.feed("\x1b[3;4H\x1b[6n\x1b[c\x1b[5n")
        self.assertEqual(got, ["\x1b[3;4R", "\x1b[?6c", "\x1b[0n"])


class Keys(unittest.TestCase):
    def test_tmux_names(self):
        self.assertEqual(ptydrive.key_bytes("Enter"), b"\r")
        self.assertEqual(ptydrive.key_bytes("Escape"), b"\x1b")
        self.assertEqual(ptydrive.key_bytes("Tab"), b"\t")
        self.assertEqual(ptydrive.key_bytes("C-c"), b"\x03")
        self.assertEqual(ptydrive.key_bytes("1"), b"1")
        self.assertEqual(ptydrive.key_bytes("Up"), b"\x1b[A")

    def test_unknown_key(self):
        self.assertIsNone(ptydrive.key_bytes("NoSuchKey"))
        self.assertIsNone(ptydrive.key_bytes("12"))


def driver(*args, timeout=30):
    return subprocess.run([sys.executable, DRIVER] + list(args), capture_output=True,
                          timeout=timeout, stdin=subprocess.DEVNULL)


def wait_text(get, text, seconds=15):
    end = time.monotonic() + seconds
    out = ""
    while time.monotonic() < end:
        out = get()
        if text in out:
            return out
        time.sleep(0.2)
    raise AssertionError("no %r in the screen:\n%s" % (text, out))


@unittest.skipUnless(hasattr(os, "fork"), "needs a Unix pty")
class Serve(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        # A long folder name: the socket must work past the limit of a
        # Unix socket path.
        self.state = os.path.join(self.dir, "s" * 120)
        os.mkdir(self.state)
        self.sock = os.path.join(self.state, "pty.sock")

    def tearDown(self):
        driver(self.sock, "stop")
        shutil.rmtree(self.dir)

    def start(self, *cmd):
        # stdout is a pipe: the call must return when the driver is ready,
        # also when the daemon keeps running.
        r = driver("serve", self.sock, str(COLS), str(ROWS), "--", *cmd)
        self.assertEqual(r.returncode, 0, r.stderr)

    def screen(self):
        r = driver(self.sock, "screen")
        self.assertEqual(r.returncode, 0, r.stderr)
        return r.stdout.decode("utf-8")

    def pids(self):
        r = driver(self.sock, "pids")
        self.assertEqual(r.returncode, 0, r.stderr)
        return dict(line.split(" ", 1) for line in r.stdout.decode().splitlines())

    def test_drive_the_stub_and_stop(self):
        work = os.path.join(self.dir, "work")
        os.mkdir(work)
        self.start("sh", "-c", 'cd "$0" && exec sh "$1"', work, STUB)
        out = wait_text(self.screen, "stub idle")
        self.assertEqual(len(out.split("\n")), ROWS + 1)
        p = self.pids()
        self.assertEqual(p["alive"], "yes")
        self.assertEqual(driver(self.sock, "send", "write").returncode, 0)
        self.assertEqual(driver(self.sock, "key", "Enter").returncode, 0)
        wait_text(self.screen, "1. Yes")
        self.assertEqual(driver(self.sock, "key", "1").returncode, 0)
        wait_text(self.screen, "created agent-signals-test.txt")
        with open(os.path.join(work, "agent-signals-test.txt")) as f:
            self.assertEqual(f.read(), "hello\n")
        self.assertEqual(driver(self.sock, "key", "NoSuchKey").returncode, 2)
        # The screen stays after the program ends.
        driver(self.sock, "key", "C-c")
        end = time.monotonic() + 10
        while self.pids()["alive"] == "yes" and time.monotonic() < end:
            time.sleep(0.2)
        self.assertEqual(self.pids()["alive"], "no")
        self.assertIn("stub idle", self.screen())
        self.assertEqual(driver(self.sock, "stop").returncode, 0)
        self.assertFalse(os.path.exists(self.sock))
        for pid in (int(p["driver"]), int(p["agent"])):
            with self.assertRaises(OSError):
                os.kill(pid, 0)

    def test_stop_ends_a_running_program(self):
        self.start("sh", STUB)
        wait_text(self.screen, "stub idle")
        p = self.pids()
        self.assertEqual(driver(self.sock, "stop").returncode, 0)
        time.sleep(0.5)
        for pid in (int(p["driver"]), int(p["agent"])):
            with self.assertRaises(OSError):
                os.kill(pid, 0)

    def test_no_session(self):
        self.assertEqual(driver(self.sock, "screen").returncode, 1)

    def test_bad_command(self):
        r = driver("serve", self.sock, str(COLS), str(ROWS), "--", "/no/such/program")
        self.assertEqual(r.returncode, 0, r.stderr)
        end = time.monotonic() + 10
        while self.pids()["alive"] == "yes" and time.monotonic() < end:
            time.sleep(0.2)
        self.assertEqual(self.pids()["alive"], "no")


def tmux_joined(sock, env, target="t"):
    """The screen of `kit session screen` on tmux: capture-pane -p -J
    with no trailing spaces."""
    out = subprocess.run(["tmux", "-L", sock, "capture-pane", "-p", "-J", "-t", target],
                         check=True, capture_output=True, env=env).stdout.decode("utf-8")
    return "".join(line.rstrip(" ") + "\n" for line in out.split("\n")[:-1])


# More inputs for the joined format: wrapped rows, a scroll of wrapped
# rows, and an erase that clears the marks.
JOINED = dict(SAMPLES)
JOINED.update({
    "wrap-twice": "a" * 250 + "\r\nend",
    "wrap-then-overwrite": "y" * 130 + "\x1b[1;1Hover",
    "wrap-and-scroll": "".join("%d %s\r\n" % (i, "w" * 125) for i in range(30)),
    "wrap-then-clear": "z" * 130 + "\x1b[2J\x1b[Hfresh",
    "wrap-with-spaces": "p" * 118 + "    q",
})


@unittest.skipUnless(shutil.which("tmux"), "tmux is not installed")
class JoinedAsTmux(unittest.TestCase):
    """The joined pyte screen equals tmux capture-pane -p -J, with no
    trailing spaces, for the same output."""

    def test_samples(self):
        # One tmux server with one session for each sample, and one wait.
        d = tempfile.mkdtemp()
        sock = "ptydrive-join-%d" % os.getpid()
        env = {"PATH": os.environ.get("PATH", ""), "LANG": "C.UTF-8", "TERM": "xterm-256color"}
        names = sorted(JOINED)
        try:
            for i, name in enumerate(names):
                f = os.path.join(d, "in%d" % i)
                with open(f, "w", encoding="utf-8", newline="") as fh:
                    fh.write(JOINED[name])
                subprocess.run(["tmux", "-L", sock, "-f", "/dev/null", "new-session", "-d",
                                "-s", "t%d" % i, "-x", str(COLS), "-y", str(ROWS),
                                "stty raw -echo; cat %s; sleep 60" % shlex.quote(f)],
                               check=True, env=env)
            time.sleep(1.5)
            for i, name in enumerate(names):
                with self.subTest(name):
                    t = ptydrive.Terminal(COLS, ROWS)
                    t.feed(JOINED[name])
                    self.assertEqual(t.joined(), tmux_joined(sock, env, "t%d" % i))
        finally:
            subprocess.run(["tmux", "-L", sock, "kill-server"], capture_output=True, env=env)
            shutil.rmtree(d)


@unittest.skipUnless(shutil.which("tmux") and hasattr(os, "fork"), "tmux is not installed")
class ScreenMatchesTmux(unittest.TestCase):
    """The pty screen of the stub equals the tmux capture of the same stub
    at the same size."""

    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.sock = os.path.join(self.dir, "pty.sock")
        self.tmux = "ptydrive-test-%d" % os.getpid()
        env = {"PATH": os.environ.get("PATH", ""), "LANG": "C.UTF-8", "TERM": "xterm-256color",
               "HOME": self.dir}
        self.env = env
        subprocess.run(["tmux", "-L", self.tmux, "-f", "/dev/null", "new-session", "-d", "-s", "t",
                        "-x", str(COLS), "-y", str(ROWS), "-c", self.dir, "sh %s" % shlex.quote(STUB)],
                       check=True, env=env)
        r = driver("serve", self.sock, str(COLS), str(ROWS), "--", "sh", STUB)
        self.assertEqual(r.returncode, 0, r.stderr)

    def tearDown(self):
        subprocess.run(["tmux", "-L", self.tmux, "kill-server"], capture_output=True, env=self.env)
        driver(self.sock, "stop")
        shutil.rmtree(self.dir)

    def tmux_screen(self):
        return tmux_joined(self.tmux, self.env)

    def pty_screen(self):
        return driver(self.sock, "screen").stdout.decode("utf-8")

    def both(self, text):
        return wait_text(self.tmux_screen, text), wait_text(self.pty_screen, text)

    def test_screen_matches_tmux(self):
        a, b = self.both("stub idle")
        self.assertEqual(b, a)
        subprocess.run(["tmux", "-L", self.tmux, "send-keys", "-t", "t", "-l", "write"], check=True, env=self.env)
        subprocess.run(["tmux", "-L", self.tmux, "send-keys", "-t", "t", "Enter"], check=True, env=self.env)
        driver(self.sock, "send", "write")
        driver(self.sock, "key", "Enter")
        a, b = self.both("2. No")
        self.assertEqual(b, a)


if __name__ == "__main__":
    unittest.main()
