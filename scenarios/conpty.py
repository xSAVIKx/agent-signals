"""A terminal driver for Windows: one program in a pseudo console (ConPTY).

The driver starts a command in a pseudo console of a fixed size, reads its
output into a pyte screen, and gives the visible screen as plain text, in
the format of `tmux capture-pane -p`. It answers the cursor position and
device attribute queries of the program, as tmux does. It can send keys.

It also gives the helpers of the Windows scenarios: the process tree, the
open files, the file list of a folder, and a throwaway environment.

Needs, on Windows: pywinpty, pyte and psutil, at the versions that the
scenarios workflow pins. The screen functions need only pyte, so the tests
in scenarios/tests/ run on Linux too.
"""

import ntpath
import os
import threading
import time

import pyte
from wcwidth import wcwidth

COLS = 120
ROWS = 40

# The variables that the agent gets from the environment of the driver.
# All other variables stay out, as `env -i` does for tmux_start on Linux.
PASS_VARS = (
    "PATH", "PATHEXT", "SystemRoot", "SystemDrive", "windir", "ComSpec",
    "OS", "NUMBER_OF_PROCESSORS", "PROCESSOR_ARCHITECTURE",
    "PROCESSOR_IDENTIFIER", "PROCESSOR_LEVEL", "PROCESSOR_REVISION",
    "ProgramFiles", "ProgramFiles(x86)", "ProgramW6432", "ProgramData",
    "CommonProgramFiles", "CommonProgramFiles(x86)", "CommonProgramW6432",
    "ALLUSERSPROFILE", "PUBLIC", "PSModulePath", "DriverData",
)

# Each cell of a pyte line holds one character. A wide character uses two
# cells: the second cell holds an empty stub.


def render_line(line, columns):
    """Return one screen line as text, with no trailing spaces."""
    out = []
    skip = False
    for x in range(columns):
        if skip:
            skip = False
            continue
        data = line[x].data
        out.append(data)
        skip = bool(data) and wcwidth(data[0]) == 2
    return "".join(out).rstrip()


def render(screen):
    """Return the visible screen in the format of `tmux capture-pane -p`.

    It has one line for each row, also for an empty row. Each line has no
    trailing spaces and ends with a newline. The test against tmux in
    scenarios/tests/ checks this.
    """
    return "".join(render_line(screen.buffer[y], screen.columns) + "\n" for y in range(screen.lines))


class _Screen(pyte.Screen):
    """A pyte screen that sends its answers to a callback."""

    reply = None

    def write_process_input(self, data):
        if self.reply is not None:
            self.reply(data)


class Terminal:
    """A pyte screen with a lock, so that a reader thread can feed it."""

    def __init__(self, cols=COLS, rows=ROWS, reply=None):
        self.screen = _Screen(cols, rows)
        self.screen.reply = reply
        self.stream = pyte.Stream(self.screen)
        self.lock = threading.Lock()
        self.chars = 0
        self.errors = 0
        self.first_error = ""

    def feed(self, text):
        with self.lock:
            self.chars += len(text)
            try:
                self.stream.feed(text)
            except Exception as e:  # A broken sequence must not stop the reader.
                self.errors += 1
                if not self.first_error:
                    self.first_error = "%s: %s" % (type(e).__name__, str(e)[:80])

    def text(self):
        with self.lock:
            return render(self.screen)


class ConPTY:
    """One program in a pseudo console. Windows only.

    argv[0] must be a full path to an executable. The command line is
    argv joined with the Windows quoting rules.
    """

    def __init__(self, argv, cwd=None, env=None, cols=COLS, rows=ROWS):
        import subprocess

        from winpty import PTY, Backend

        self.argv = list(argv)
        self.terminal = Terminal(cols, rows, reply=self.write)
        self.pty = PTY(cols, rows, backend=Backend.ConPTY)
        block = None
        if env is not None:
            block = "\0".join("%s=%s" % kv for kv in env.items()) + "\0"
        rest = subprocess.list2cmdline(self.argv[1:]) or None
        self.pty.spawn(self.argv[0], rest, cwd, block)
        self.pid = self.pty.pid
        self.started = time.monotonic()
        self.stopping = threading.Event()
        self.reader = threading.Thread(target=self._read, args=(self.pty,), daemon=True)
        self.reader.start()

    def _read(self, pty):
        # A read that does not block, so that the thread can stop: a
        # blocking read can hang when the interpreter stops.
        while not self.stopping.is_set():
            try:
                data = pty.read(blocking=False)
            except Exception:
                return
            if data:
                self.terminal.feed(data)
            else:
                try:
                    if pty.iseof():
                        return
                except Exception:
                    return
                time.sleep(0.02)

    def write(self, text):
        """Send text or a key sequence to the program."""
        try:
            self.pty.write(text)
        except Exception:
            pass

    def screen(self):
        return self.terminal.text()

    def alive(self):
        try:
            return bool(self.pty.isalive())
        except Exception:
            return False

    def exitstatus(self):
        try:
            return self.pty.get_exitstatus()
        except Exception:
            return None

    def close(self):
        """Stop the reader. Call it after the processes are stopped."""
        self.stopping.set()
        self.reader.join(5)
        try:
            self.pty.cancel_io()
        except Exception:
            pass


# Keys for ConPTY.write. ConPTY reads VT input.
KEYS = {
    "Enter": "\r", "Escape": "\x1b", "Tab": "\t", "BSpace": "\x7f",
    "Up": "\x1b[A", "Down": "\x1b[B", "Right": "\x1b[C", "Left": "\x1b[D",
    "C-c": "\x03", "C-d": "\x04",
}


# The helpers below need psutil (Windows) or only the standard library.


def replace_dir(text, folder, name="<sandbox>"):
    """Replace each form of a folder path in text with name.

    A Windows path can show with backslashes or slashes, and in any case.
    """
    if not folder or not text:
        return text
    import re

    parts = [re.escape(p) for p in re.split(r"[\\/]+", folder.rstrip("\\/")) if p]
    pattern = r"[\\/]+".join(parts)
    if folder.startswith(("/", "\\")):
        pattern = r"[\\/]+" + pattern
    return re.sub("(?i)" + pattern, name, text)


def list_files(top, sandbox):
    """List each file below top: size, modification time, path.

    The path starts at the sandbox and uses slashes, so that the lines
    have the format of snapshot_files in scenarios/lib.sh.
    """
    rows = []
    for d, _dirs, files in os.walk(top):
        for f in files:
            p = os.path.join(d, f)
            try:
                st = os.stat(p)
            except OSError:
                continue
            rel = os.path.relpath(p, sandbox).replace("\\", "/")
            rows.append((rel, st.st_size, int(st.st_mtime)))
    rows.sort()
    return ["%d %d <sandbox>/%s" % (s, m, r) for r, s, m in rows]


def tree_entries(roots, depth=2, skip=()):
    """Return {path: (is_dir, size, mtime)} for each entry below each root,
    to depth levels. A folder name in skip is listed but not entered."""
    seen = {}

    def walk(d, level):
        try:
            it = list(os.scandir(d))
        except OSError:
            return
        for e in it:
            try:
                st = e.stat(follow_symlinks=False)
                is_dir = e.is_dir(follow_symlinks=False)
            except OSError:
                continue
            seen[e.path] = (is_dir, 0 if is_dir else st.st_size, int(st.st_mtime))
            if is_dir and level < depth and e.name.lower() not in skip:
                walk(e.path, level + 1)

    for r in roots:
        if r and os.path.isdir(r):
            walk(r, 1)
    return seen


def diff_entries(before, after):
    """Return the lines "new PATH", "changed PATH" and "gone PATH"."""
    out = []
    for p in sorted(set(before) | set(after)):
        if p not in before:
            out.append("new " + p)
        elif p not in after:
            out.append("gone " + p)
        elif before[p] != after[p]:
            out.append("changed " + p)
    return out


def sandbox_env(base, home, work_user="dev"):
    """Return the environment of the agent.

    It keeps only PASS_VARS from base. USERPROFILE and HOME point to the
    throwaway home, APPDATA and LOCALAPPDATA to folders in it, as on a
    real Windows profile. TEMP and TMP point to a folder in it too.
    """
    env = {}
    lower = {k.lower(): k for k in base}
    for v in PASS_VARS:
        k = lower.get(v.lower())
        if k is not None:
            env[v] = base[k]
    drive, rest = ntpath.splitdrive(home)
    join = ntpath.join
    env.update({
        "USERPROFILE": home,
        "HOME": home,
        "HOMEDRIVE": drive,
        "HOMEPATH": rest or "\\",
        "APPDATA": join(home, "AppData", "Roaming"),
        "LOCALAPPDATA": join(home, "AppData", "Local"),
        "TEMP": join(home, "AppData", "Local", "Temp"),
        "TMP": join(home, "AppData", "Local", "Temp"),
        "USERNAME": work_user,
    })
    return env


def descendants(table, root):
    """Return the pids below root in table {pid: (ppid, create_time)}.

    A child must start after its parent, because Windows reuses pids and
    keeps the parent pid of a process after the parent stops.
    """
    kids = {}
    for pid, (ppid, _ct) in table.items():
        kids.setdefault(ppid, []).append(pid)
    out = []

    def walk(p):
        pct = table.get(p, (0, 0))[1]
        for c in sorted(kids.get(p, [])):
            if c == p or c in out or table[c][1] + 1 < pct:
                continue
            out.append(c)
            walk(c)

    walk(root)
    return out
