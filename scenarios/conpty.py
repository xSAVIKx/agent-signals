r"""A terminal driver for Windows: one program in a pseudo console (ConPTY).

The driver starts a command in a pseudo console of a fixed size, reads its
output into a pyte screen, and gives the visible screen as plain text, in
the format of `tmux capture-pane -p`. It answers the cursor position and
device attribute queries of the program, as tmux does. It can send keys.

It also gives the helpers of the Windows scenarios: the process tree, the
open files, the file list of a folder, and a throwaway environment.

The serve mode keeps one program in a pseudo console for `kit session`
(probes/agent/session.ps1). Other processes send it commands through a
named pipe, as probes/agent/ptydrive.py does with a socket:

    python conpty.py serve PIPE COLS ROWS [--cwd DIR] [--ready FILE] [--key FILE] -- CMD...
    python conpty.py detach PIPE COLS ROWS --ready FILE [--cwd DIR] [--key FILE] -- CMD...
    python conpty.py [--key FILE] PIPE send TEXT | key KEY | screen | stop

detach starts serve as a detached process: no console, no handle of the
caller, a new process group, and out of the job object of the caller when
the job lets it. It waits for the ready file, prints "pid N", "breakaway
yes|no", "server N" and "agent N", and exits. The key FILE holds the key
of the pipe: the server and the client must give the same key.

PIPE is a pipe name such as \\.\pipe\kit-NAME. The serve mode writes
FILE when the pipe is open: one JSON object with the pids "server" and
"agent", or "error".

Needs, on Windows: pywinpty, pyte and psutil, at the versions that the
scenarios workflow pins. The screen functions need only pyte, so the tests
in scenarios/tests/ run on Linux too.
"""

import json
import ntpath
import os
import sys
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

    # pyte 0.8.2 gives "private=True" for a CSI with "?" or ">" (for
    # example CSI ? 6 n and CSI > 4 ; 2 m), but these two methods do not take
    # it. The TypeError then drops the rest of the output chunk. The screen
    # ignores these private forms and sends no answer.
    def report_device_status(self, mode, **kwargs):
        if not kwargs.get("private"):
            super().report_device_status(mode)

    def select_graphic_rendition(self, *attrs, **kwargs):
        if not kwargs.get("private"):
            super().select_graphic_rendition(*attrs)


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


def key_text(name):
    """Return the text for a tmux key name. One character stays itself."""
    if name in KEYS:
        return KEYS[name]
    if len(name) == 1:
        return name
    raise ValueError("unknown key: %s" % name)


def parse_serve(argv):
    """Parse the arguments of the serve mode: PIPE COLS ROWS [--cwd DIR]
    [--ready FILE] [--key FILE] -- CMD... Returns a dict."""
    if "--" not in argv:
        raise ValueError("no -- before the command")
    i = argv.index("--")
    head, cmd = argv[:i], argv[i + 1:]
    if len(head) < 3 or not cmd:
        raise ValueError("usage: serve PIPE COLS ROWS [--cwd DIR] [--ready FILE] [--key FILE] -- CMD...")
    out = {"pipe": head[0], "cols": int(head[1]), "rows": int(head[2]),
           "cwd": None, "ready": None, "key": None, "argv": cmd}
    rest = head[3:]
    while rest:
        if rest[0] in ("--cwd", "--ready", "--key") and len(rest) > 1:
            out[rest[0][2:]] = rest[1]
            rest = rest[2:]
        else:
            raise ValueError("unknown option: %s" % rest[0])
    return out


def read_key(path):
    """Return the key of the pipe from a key file, or None with no file."""
    if not path:
        return None
    with open(path, encoding="ascii") as f:
        return f.read().strip().encode("ascii")


def _write_json(path, obj):
    if not path:
        return
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(obj, f)
    os.replace(tmp, path)


def _kill_tree(proc):
    """Stop proc (a psutil.Process) and each process below it. psutil
    checks the start time, so a pid that Windows gave again to a new
    process is not stopped."""
    import psutil

    try:
        if not proc.is_running():
            return
        kids = proc.children(recursive=True)
    except psutil.Error:
        return
    for k in kids + [proc]:
        try:
            if k.is_running():
                k.kill()
        except psutil.Error:
            pass


def serve(argv, max_seconds=4 * 3600):
    """Run the serve mode. It ends on "stop", or after max_seconds."""
    from multiprocessing.connection import Listener

    o = parse_serve(argv)
    import psutil

    try:
        listener = Listener(address=o["pipe"], family="AF_PIPE", authkey=read_key(o["key"]))
        con = ConPTY(o["argv"], cwd=o["cwd"], cols=o["cols"], rows=o["rows"])
        agent = psutil.Process(con.pid)
    except Exception as e:
        _write_json(o["ready"], {"error": "%s: %s" % (type(e).__name__, e)})
        return 1
    _write_json(o["ready"], {"server": os.getpid(), "agent": con.pid})

    def end():
        _kill_tree(agent)
        con.close()

    def limit():
        time.sleep(max_seconds)
        end()
        os._exit(0)

    threading.Thread(target=limit, daemon=True).start()
    while True:
        try:
            # With a key, accept() also checks the key of the client.
            conn = listener.accept()
        except Exception:
            time.sleep(0.05)
            continue
        op = None
        try:
            # A client that sends nothing must not stop the server.
            if not conn.poll(5):
                conn.close()
                continue
            req = json.loads(conn.recv_bytes(1 << 20).decode("utf-8"))
            op = req.get("op")
            if op == "send":
                con.write(req["text"])
                resp = {"ok": True}
            elif op == "key":
                con.write(key_text(req["key"]))
                resp = {"ok": True}
            elif op == "screen":
                resp = {"ok": True, "screen": con.screen()}
            elif op == "stop":
                end()
                resp = {"ok": True}
            else:
                resp = {"ok": False, "error": "unknown command: %s" % op}
        except Exception as e:
            resp = {"ok": False, "error": "%s: %s" % (type(e).__name__, e)}
        try:
            conn.send_bytes(json.dumps(resp).encode("utf-8"))
            conn.close()
        except Exception:
            pass
        if op == "stop":
            listener.close()
            return 0


def _in_job(proc):
    """Return True when the process (a subprocess.Popen) is in a job object.
    When Windows cannot tell, return True."""
    try:
        import ctypes

        result = ctypes.c_int(0)
        ok = ctypes.windll.kernel32.IsProcessInJob(ctypes.c_void_p(int(proc._handle)), None, ctypes.byref(result))
        return (not ok) or bool(result.value)
    except Exception:
        return True


def detach(argv, wait_seconds=30):
    """Start the serve mode as a detached process. Wait for its ready file,
    then print "pid N" (the started process), "server N", "agent N" and
    "breakaway yes|no". At the time limit, stop the started process tree
    and exit 1."""
    import subprocess

    o = parse_serve(argv)
    if not o["ready"]:
        raise ValueError("detach needs --ready FILE")
    import psutil

    cmd = [sys.executable, "-I", os.path.abspath(__file__), "serve"] + list(argv)
    base = 0x00000008 | 0x00000200  # DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP
    breakaway = 0x01000000  # CREATE_BREAKAWAY_FROM_JOB
    kw = dict(stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
              stderr=subprocess.DEVNULL, close_fds=True)
    try:
        p = subprocess.Popen(cmd, creationflags=base | breakaway, **kw)
        away = "yes"
    except OSError:
        # The job of the caller does not let a child break away.
        p = subprocess.Popen(cmd, creationflags=base, **kw)
        away = "no"
    # The Python launcher of a virtual environment puts Python in a job of
    # its own that lets a child break away. So a breakaway can leave only
    # that job. "yes" means that the new process is in no job at all.
    if away == "yes" and _in_job(p):
        away = "no"
    try:
        started = psutil.Process(p.pid)
    except psutil.Error:
        started = None
    sys.stdout.write("pid %d\nbreakaway %s\n" % (p.pid, away))
    end = time.monotonic() + wait_seconds
    while not os.path.exists(o["ready"]):
        if time.monotonic() > end:
            if started is not None:
                _kill_tree(started)
            sys.stderr.write("conpty: the server did not start in %d s\n" % wait_seconds)
            return 1
        time.sleep(0.05)
    with open(o["ready"], encoding="utf-8") as f:
        r = json.load(f)
    if r.get("error"):
        sys.stderr.write("conpty: %s\n" % r["error"])
        return 1
    sys.stdout.write("server %d\nagent %d\n" % (r["server"], r["agent"]))
    return 0


def client(argv):
    """Send one command to a serve process: [--key FILE] PIPE send TEXT |
    key KEY | screen | stop. Prints the screen for "screen"."""
    from multiprocessing.connection import Client

    key = None
    if argv[:1] == ["--key"]:
        if len(argv) < 2:
            raise ValueError("--key needs a FILE")
        key = read_key(argv[1])
        argv = argv[2:]
    if len(argv) < 2:
        raise ValueError("usage: [--key FILE] PIPE send TEXT | key KEY | screen | stop")
    pipe, op = argv[0], argv[1]
    req = {"op": op}
    if op == "send":
        req["text"] = argv[2]
    elif op == "key":
        key_text(argv[2])
        req["key"] = argv[2]
    elif op not in ("screen", "stop"):
        raise ValueError("unknown command: %s" % op)
    c = Client(pipe, family="AF_PIPE", authkey=key)
    c.send_bytes(json.dumps(req).encode("utf-8"))
    if not c.poll(10):
        c.close()
        sys.stderr.write("conpty: no answer in 10 s\n")
        return 1
    resp = json.loads(c.recv_bytes().decode("utf-8"))
    c.close()
    if not resp.get("ok"):
        sys.stderr.write("conpty: %s\n" % resp.get("error"))
        return 1
    if op == "screen":
        sys.stdout.buffer.write(resp["screen"].encode("utf-8"))
        sys.stdout.flush()
    return 0


def main(argv):
    try:
        if argv and argv[0] == "serve":
            return serve(argv[1:])
        if argv and argv[0] == "detach":
            return detach(argv[1:])
        return client(argv)
    except (ValueError, IndexError) as e:
        sys.stderr.write("conpty: %s\n" % e)
        return 2
    except OSError as e:
        sys.stderr.write("conpty: %s\n" % e)
        return 1


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


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
