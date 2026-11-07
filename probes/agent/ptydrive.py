"""The pty backend of `kit session`: one program in a plain pseudo terminal.

There is no multiplexer, so the program sees no TMUX variables. The
driver reads the output of the program into a pyte screen and gives the
visible screen in the format of `tmux capture-pane -p -J`, with no
trailing spaces. It answers the cursor position and device attribute
queries of the program, as tmux does. It is the Unix twin of
scenarios/conpty.py.

Commands:

  ptydrive.py serve SOCKET COLS ROWS -- CMD...
      Start CMD in a new pty and serve commands on the Unix socket
      SOCKET. The driver runs as a daemon in a new session. Its errors go
      to SOCKET.log. The call returns when the socket is ready: exit 0, or
      exit 1 with the reason on stderr.
  ptydrive.py SOCKET screen          Print the visible screen.
  ptydrive.py SOCKET send TEXT       Type TEXT.
  ptydrive.py SOCKET key KEY...      Send keys with tmux names: Enter,
                                     Escape, Tab, BSpace, Space, Up, Down,
                                     Left, Right, C-a to C-z, one letter or
                                     digit.
  ptydrive.py SOCKET pids            Print "driver PID", "agent PID" and
                                     "alive yes|no".
  ptydrive.py SOCKET stop            Stop the program and the driver.

Exit codes: 0 ok, 1 no driver on SOCKET or a failure, 2 bad use, 3 no
pyte (only "serve" needs pyte).

A Unix socket path has a limit of about 104 bytes on macOS. The kit puts
the socket in a short folder below /tmp. The driver and the client also
go into the folder of the socket and use its short name.
"""

import codecs
import copy
import fcntl
import json
import os
import pty
import select
import signal
import socket
import struct
import sys
import termios
import time

# All modules load at the start. The daemon can outlive the temporary
# environment of `uv run --with`, so it must not import a module later.
try:
    import pyte
    from wcwidth import wcwidth
except ImportError:  # The client commands do not need pyte.
    pyte = None

COLS = 120
ROWS = 40
# A send waits when the program has this much input that it has not read.
MAX_PENDING = 1 << 20


def _max_fd():
    try:
        n = os.sysconf("SC_OPEN_MAX")
    except (ValueError, OSError):
        n = 1024
    return min(max(n, 256), 65536)

# Keys with tmux names, for a program that reads VT input.
KEYS = {
    "Enter": b"\r", "Escape": b"\x1b", "Tab": b"\t", "BSpace": b"\x7f", "Space": b" ",
    "Up": b"\x1b[A", "Down": b"\x1b[B", "Right": b"\x1b[C", "Left": b"\x1b[D",
}


def key_bytes(name):
    """Return the bytes of a tmux key name, or None for an unknown name."""
    if name in KEYS:
        return KEYS[name]
    if len(name) == 3 and name.startswith("C-") and "a" <= name[2] <= "z":
        return bytes([ord(name[2]) & 0x1F])
    if len(name) == 1 and name.isascii() and name.isalnum():
        return name.encode()
    return None


# The screen format. render_line and render are a copy of the functions of
# scenarios/conpty.py, so that the kit does not need the scenarios folder.
# scenarios/tests/test_ptydrive.py checks that both copies give the same
# text. Each cell of a pyte line holds one character. A wide character
# uses two cells: the second cell holds an empty stub.


def render_line(line, columns, strip=True):
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
    text = "".join(out)
    return text.rstrip() if strip else text


def render(screen):
    """Return the visible screen in the format of `tmux capture-pane -p`:
    one line for each row, with no trailing spaces, each with a newline."""
    return "".join(render_line(screen.buffer[y], screen.columns) + "\n" for y in range(screen.lines))


def render_joined(screen):
    """Return the visible screen in the format of `tmux capture-pane -p -J`
    with no trailing spaces. A row that the program wrapped joins the next
    row, so that a long path stays on one line.

    screen.wrapped is the set of the rows that continue on the next row
    (see _Screen).
    """
    wrapped = getattr(screen, "wrapped", None) or ()
    out = []
    cur = ""
    for y in range(screen.lines):
        if y in wrapped and y < screen.lines - 1:
            cur += render_line(screen.buffer[y], screen.columns, strip=False)
            continue
        out.append((cur + render_line(screen.buffer[y], screen.columns)).rstrip() + "\n")
        cur = ""
    return "".join(out)


if pyte is not None:

    class _Screen(pyte.Screen):
        """A pyte screen that sends its answers to a callback, and that
        keeps the rows that the program wrapped."""

        reply = None
        # Row y continues on row y + 1. As in tmux, a row keeps the mark
        # until a scroll moves it or an erase of the display clears it.
        wrapped = frozenset()
        _drawing = False

        def draw(self, data):
            self._drawing = True
            try:
                super().draw(data)
            finally:
                self._drawing = False

        def linefeed(self):
            # A line feed in draw is an automatic wrap. tmux 3.5a keeps the
            # mark at any other line feed (measured in the tests).
            if self._drawing:
                self.wrapped = self.wrapped | {self.cursor.y}
            super().linefeed()

        def erase_in_line(self, how=0, private=False):
            # An erase of the whole row, or of the row from its start, ends
            # the row and the join from the row before.
            if how == 2 or (how == 0 and self.cursor.x == 0):
                y = self.cursor.y
                self.wrapped = self.wrapped - {y, y - 1}
            super().erase_in_line(how, private)

        # The marks move with the rows, as in tmux. An insert also ends the
        # row before the cursor and the row before the moved rows. A delete
        # also ends the row before the cursor (measured with tmux 3.5a in
        # the tests).
        def insert_lines(self, count=None):
            top, bottom = self._margins()
            y, n = self.cursor.y, count or 1
            if top <= y <= bottom:
                self.wrapped = frozenset(
                    r + n if y <= r <= bottom else r for r in self.wrapped
                    if not (y <= r <= bottom and r + n > bottom) and r not in (y - 1, y + n - 1))
            super().insert_lines(count)

        def delete_lines(self, count=None):
            top, bottom = self._margins()
            y, n = self.cursor.y, count or 1
            if top <= y <= bottom:
                self.wrapped = frozenset(
                    r - n if y + n <= r <= bottom else r for r in self.wrapped
                    if not (y <= r < y + n) and r != y - 1)
            super().delete_lines(count)

        def _margins(self):
            m = self.margins
            return (m.top, m.bottom) if m else (0, self.lines - 1)

        def index(self):
            top, bottom = self._margins()
            if self.wrapped and self.cursor.y == bottom:
                self.wrapped = frozenset(y - 1 if top < y <= bottom else y
                                         for y in self.wrapped if y != top)
            super().index()

        def reverse_index(self):
            top, bottom = self._margins()
            if self.wrapped and self.cursor.y == top:
                self.wrapped = frozenset(y + 1 if top <= y < bottom else y
                                         for y in self.wrapped if y != bottom)
            super().reverse_index()

        def erase_in_display(self, how=0, *args, **kwargs):
            y = self.cursor.y
            if how == 0:
                self.wrapped = frozenset(r for r in self.wrapped if r < y)
            elif how == 1:
                self.wrapped = frozenset(r for r in self.wrapped if r > y)
            elif how in (2, 3):
                self.wrapped = frozenset()
            super().erase_in_display(how, *args, **kwargs)

        def reset(self):
            # A full reset (RIS) also leaves the alternate screen.
            self.wrapped = frozenset()
            self._saved_main = None
            super().reset()

        # The alternate screen (private modes 47, 1047 and 1049), as in
        # tmux: the program draws on an empty screen, and at the exit the
        # main screen comes back. pyte 0.8.2 has no alternate screen, so the
        # rows of the alternate screen stayed on the main screen. agy 1.5.1
        # shows its trust question on the alternate screen (fact 77).
        _saved_main = None

        def set_mode(self, *modes, **kwargs):
            super().set_mode(*modes, **kwargs)
            if kwargs.get("private") and self._saved_main is None and \
                    any(m in (47, 1047, 1049) for m in modes):
                self._saved_main = (copy.deepcopy(self.buffer), copy.copy(self.cursor), self.wrapped)
                self.wrapped = frozenset()
                self.buffer.clear()
                self.dirty.update(range(self.lines))

        def reset_mode(self, *modes, **kwargs):
            super().reset_mode(*modes, **kwargs)
            if kwargs.get("private") and self._saved_main is not None and \
                    any(m in (47, 1047, 1049) for m in modes):
                buf, cursor, wrapped = self._saved_main
                self._saved_main = None
                self.buffer.clear()
                self.buffer.update(buf)
                if 1049 in modes:
                    self.cursor = cursor
                self.wrapped = wrapped
                self.dirty.update(range(self.lines))

        def write_process_input(self, data):
            if self.reply is not None:
                self.reply(data)

        # pyte 0.8.2 gives "private=True" for a CSI with "?" or ">", but
        # these two methods do not take it (see scenarios/conpty.py).
        def report_device_status(self, mode, **kwargs):
            if not kwargs.get("private"):
                super().report_device_status(mode)

        def select_graphic_rendition(self, *attrs, **kwargs):
            if not kwargs.get("private"):
                super().select_graphic_rendition(*attrs)


class Terminal:
    """A pyte screen and its stream."""

    def __init__(self, cols=COLS, rows=ROWS, reply=None):
        self.screen = _Screen(cols, rows)
        self.screen.reply = reply
        self.stream = pyte.Stream(self.screen)
        self.errors = 0

    def feed(self, text):
        try:
            self.stream.feed(text)
        except Exception:  # A broken sequence must not stop the driver.
            self.errors += 1

    def text(self):
        """The screen in the format of `tmux capture-pane -p`."""
        return render(self.screen)

    def joined(self):
        """The screen in the format of `tmux capture-pane -p -J`, with no
        trailing spaces."""
        return render_joined(self.screen)


# The client.


def _split(path):
    path = os.path.abspath(path)
    return os.path.dirname(path), os.path.basename(path)


def request(sock_path, op, args=(), timeout=15):
    """Send one command to the driver and return its answer (a dict).
    Raise OSError when no driver answers."""
    folder, name = _split(sock_path)
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(timeout)
    cwd = os.getcwd()
    try:
        os.chdir(folder)
        try:
            s.connect(name)
        finally:
            os.chdir(cwd)
        s.sendall(json.dumps({"op": op, "args": list(args)}).encode() + b"\n")
        data = b""
        while not data.endswith(b"\n"):
            chunk = s.recv(65536)
            if not chunk:
                break
            data += chunk
    finally:
        s.close()
    if not data:
        raise OSError("no answer")
    return json.loads(data.decode("utf-8"))


# The server.


class Server:
    def __init__(self, listener, cols, rows, argv):
        self.listener = listener
        self.cols, self.rows = cols, rows
        self.terminal = Terminal(cols, rows, reply=self.write)
        self.decoder = None
        self.pid = None
        self.fd = None
        self.status = None
        # The input for the program that it has not read yet. The driver
        # never blocks on a write: a program that does not read must not
        # stop the driver.
        self.pending = b""
        self.group_gone = False
        self.spawn(argv)

    def spawn(self, argv):
        size = struct.pack("HHHH", self.rows, self.cols, 0, 0)
        # pty.fork makes a new session for the program, so the program and
        # its children are in one process group.
        pid, fd = pty.fork()
        if pid == 0:
            try:
                # Only the pty goes to the program.
                os.closerange(3, _max_fd())
                fcntl.ioctl(0, termios.TIOCSWINSZ, size)
                for s in (signal.SIGPIPE, signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
                    signal.signal(s, signal.SIG_DFL)
                os.execvp(argv[0], argv)
            except BaseException:
                pass
            os._exit(127)
        try:
            fcntl.ioctl(fd, termios.TIOCSWINSZ, size)
        except OSError:
            pass
        os.set_blocking(fd, False)
        self.pid, self.fd = pid, fd
        self.decoder = codecs.getincrementaldecoder("utf-8")("replace")

    def write(self, data):
        """Queue data for the program, and write what the pty takes now."""
        if self.fd is None:
            return
        if isinstance(data, str):
            data = data.encode("utf-8")
        self.pending += data
        self.flush()

    def flush(self):
        while self.pending and self.fd is not None:
            try:
                n = os.write(self.fd, self.pending[:65536])
            except BlockingIOError:
                return
            except OSError:
                self.pending = b""
                return
            self.pending = self.pending[n:]

    def alive(self):
        if self.status is None and self.pid is not None:
            try:
                p, st = os.waitpid(self.pid, os.WNOHANG)
            except ChildProcessError:
                p, st = self.pid, 0
            if p:
                self.status = st
        return self.status is None

    def read_output(self):
        try:
            data = os.read(self.fd, 65536)
        except BlockingIOError:
            return
        except OSError:
            data = b""
        if not data:
            os.close(self.fd)
            self.fd = None
            return
        self.terminal.feed(self.decoder.decode(data))

    def answer(self, conn):
        conn.settimeout(5)
        data = b""
        while not data.endswith(b"\n") and len(data) < 1 << 20:
            chunk = conn.recv(65536)
            if not chunk:
                break
            data += chunk
        stop = False
        try:
            req = json.loads(data.decode("utf-8"))
            op, args = req.get("op"), req.get("args", [])
        except ValueError:
            op, args = None, []
        if op == "screen":
            out = {"ok": True, "screen": self.terminal.joined()}
        elif op == "send":
            if len(self.pending) > MAX_PENDING:
                out = {"ok": False, "code": 1, "error": "the program does not read its input"}
            else:
                self.write("".join(args))
                out = {"ok": True}
        elif op == "key":
            keys = [key_bytes(a) for a in args]
            if None in keys or not keys:
                out = {"ok": False, "code": 2, "error": "unknown key"}
            else:
                for k in keys:
                    self.write(k)
                out = {"ok": True}
        elif op == "pids":
            out = {"ok": True, "driver": os.getpid(), "agent": self.pid,
                   "alive": self.alive()}
        elif op == "stop":
            out = {"ok": True}
            stop = True
        else:
            out = {"ok": False, "code": 2, "error": "unknown command"}
        try:
            conn.sendall(json.dumps(out).encode() + b"\n")
        except OSError:
            pass
        return stop

    def loop(self):
        while True:
            fds = [self.listener] + ([self.fd] if self.fd is not None else [])
            wfds = [self.fd] if self.fd is not None and self.pending else []
            ready, writable, _ = select.select(fds, wfds, [], 0.5)
            if self.fd is not None and self.fd in writable:
                self.flush()
            if self.fd is not None and self.fd in ready:
                self.read_output()
            if self.listener in ready:
                try:
                    conn, _ = self.listener.accept()
                except OSError:
                    continue
                try:
                    if self.answer(conn):
                        return
                except OSError:
                    pass
                finally:
                    conn.close()
            self.alive()

    def _signal_group(self, sig):
        """Send sig to the process group of the program. When the group is
        gone (ESRCH), set group_gone and send nothing more: its id can then
        belong to a new process."""
        if self.group_gone:
            return False
        self.alive()
        try:
            os.killpg(self.pid, 0)
        except ProcessLookupError:
            self.group_gone = True
            return False
        except OSError:
            return False
        if sig:
            try:
                os.killpg(self.pid, sig)
            except ProcessLookupError:
                self.group_gone = True
                return False
            except OSError:
                return False
        return True

    def stop_program(self):
        """Hang up the process group of the program, then kill it."""
        if self.pid is None:
            return
        for sig, wait in ((signal.SIGHUP, 3.0), (signal.SIGTERM, 2.0), (signal.SIGKILL, 2.0)):
            if not self._signal_group(sig):
                return
            end = time.monotonic() + wait
            while time.monotonic() < end:
                if not self._signal_group(0):
                    return
                time.sleep(0.05)


def _term(signum, frame):
    raise SystemExit(0)


def serve(sock_path, cols, rows, argv):
    if pyte is None:
        sys.stderr.write("ptydrive: needs pyte\n")
        return 3
    folder, name = _split(sock_path)
    r, w = os.pipe()
    first = os.fork()
    if first:
        # The caller: wait until the daemon is ready or fails.
        os.close(w)
        msg = b""
        while True:
            chunk = os.read(r, 4096)
            if not chunk:
                break
            msg += chunk
        os.close(r)
        try:
            os.waitpid(first, 0)
        except ChildProcessError:
            pass
        text = msg.decode("utf-8", "replace")
        if text == "ok":
            return 0
        sys.stderr.write("ptydrive: %s\n" % (text or "the driver did not start"))
        return 1
    # The daemon: a new session and a second fork. Its input, output and
    # errors go to files, so that no pipe of the caller stays open and the
    # call of the caller returns.
    os.close(r)
    try:
        os.setsid()
        if os.fork():
            os._exit(0)
        os.umask(0o077)
        null = os.open(os.devnull, os.O_RDWR)
        log = os.open(os.path.join(folder, name + ".log"), os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
        os.dup2(null, 0)
        os.dup2(null, 1)
        os.dup2(log, 2)
        os.close(null)
        os.close(log)
        # No other file of the caller stays open: an inherited pipe would
        # keep the call of the caller waiting until the agent ends.
        os.closerange(3, w)
        os.closerange(w + 1, _max_fd())
        signal.signal(signal.SIGTERM, _term)
        signal.signal(signal.SIGHUP, signal.SIG_IGN)
        signal.signal(signal.SIGPIPE, signal.SIG_IGN)
        os.chdir(folder)
        listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        if os.path.exists(name):
            os.unlink(name)
        listener.bind(name)
        listener.listen(8)
        server = Server(listener, cols, rows, argv)
    except BaseException as e:
        try:
            os.write(w, ("%s: %s" % (type(e).__name__, e)).encode())
        finally:
            os._exit(1)
    os.write(w, b"ok")
    os.close(w)
    code = 0
    try:
        server.loop()
    except SystemExit:
        pass
    except BaseException as e:
        sys.stderr.write("ptydrive: %s: %s\n" % (type(e).__name__, e))
        code = 1
    finally:
        try:
            server.stop_program()
        finally:
            listener.close()
            try:
                os.unlink(os.path.join(folder, name))
            except OSError:
                pass
    os._exit(code)


def usage():
    sys.stderr.write(__doc__.split("Commands:", 1)[1].split("Exit codes", 1)[0])
    return 2


def main(argv):
    if len(argv) >= 1 and argv[0] == "serve":
        if len(argv) < 6 or argv[4] != "--":
            return usage()
        try:
            cols, rows = int(argv[2]), int(argv[3])
        except ValueError:
            return usage()
        if not (10 <= cols <= 500 and 5 <= rows <= 200):
            return usage()
        return serve(argv[1], cols, rows, argv[5:])
    if len(argv) < 2:
        return usage()
    sock_path, op, args = argv[0], argv[1], argv[2:]
    if op not in ("screen", "send", "key", "pids", "stop"):
        return usage()
    if op == "send" and len(args) != 1:
        return usage()
    if op == "key" and not args:
        return usage()
    if op == "key" and None in [key_bytes(a) for a in args]:
        sys.stderr.write("ptydrive: unknown key\n")
        return 2
    try:
        driver = request(sock_path, "pids")["driver"] if op == "stop" else None
        out = request(sock_path, op, args)
    except OSError as e:
        sys.stderr.write("ptydrive: no driver on the socket: %s\n" % e)
        return 1
    if not out.get("ok"):
        sys.stderr.write("ptydrive: %s\n" % out.get("error", "failed"))
        return int(out.get("code", 1))
    if op == "screen":
        sys.stdout.write(out["screen"])
    elif op == "pids":
        sys.stdout.write("driver %d\nagent %d\nalive %s\n"
                         % (out["driver"], out["agent"], "yes" if out["alive"] else "no"))
    elif op == "stop":
        # Wait until the driver has ended.
        end = time.monotonic() + 15
        while time.monotonic() < end:
            try:
                os.kill(driver, 0)
            except OSError:
                break
            time.sleep(0.05)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
