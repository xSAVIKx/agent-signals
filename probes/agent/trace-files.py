"""A file watcher for a traced session (the file check, Linux only).

Run: python3 -I trace-files.py --out FILE --ready FILE [--parent PID]
       [--top DIR]... DIR...

The watcher uses inotify through ctypes. It watches each DIR and all
folders below it. Each --top DIR is watched without its subfolders that
exist at the start. A folder that comes later gets a watch, in all cases.
The watcher writes the --ready file when it has added all first watches.

The order of the first watches: each --top DIR, then each DIR in the
order of the command line. So the caller puts the most important folder
first. Below a DIR, the folders of the kit agents (AGENT_DIRS, for
example .claude and .codex) get their watches first. Then the walk goes
breadth first: at each level, the hidden folders (a name that starts
with ".") come before the other folders, each in alphabetical order.
The first walk stops at the walk limit, one eighth below the watch
limit. The rest of the watches are kept for the folders that come later,
for example a new work folder.

In a --top DIR, the watcher records only the items of this account: an
item that another account owns gets no line and no watch. An item that is
gone before the watcher can read its owner also gets no line.

With --parent PID, the watcher checks each 0.1 s that PID is still its
parent. When the parent is gone (for example "kit trace" got KILL), the
watcher stops, deletes the --out file and the --ready file, deletes the
folder of the --out file when it is empty, and exits 0. Its lines hold
the real paths, and no build reads them after the parent is gone.

The kit marks its own work with a file ".kit-trace-mark.NAME.WHAT" that
it makes and deletes at once. Before the watcher writes the "create" line
of such a file, it writes all pending "write" lines. So the lines of the
file are in the order of the events, and trace-build.py can use the marks.

Two options are for the tests only: --watch-limit N sets the watch limit
(the default is 8192), and --uid N sets the account of the --top check
(the default is the account of the watcher).

Each event is one JSON line in the --out file:
{"t": MS, "kind": K, "path": ABS, "dir": BOOL}. MS is the time in epoch
milliseconds, the same clock as trace-proxy.py. A "move" line has also
"from": ABS. The kinds are:
  create    IN_CREATE, or a moved-in entry, or an entry found by a scan.
  write     IN_MODIFY or IN_CLOSE_WRITE. One line for each file in each
            100 ms. Its "t" is the time of the first event.
  delete    IN_DELETE, or a move out of the watched tree.
  move      IN_MOVED_FROM and IN_MOVED_TO with the same cookie.
  limit     The watcher cannot add a watch. This line has no path. It
            comes one time. The watcher keeps running and keeps the
            watches that it has.
  overflow  The queue of the kernel overflowed (IN_Q_OVERFLOW). This line
            has no path. The watcher keeps running. Events can be lost.

A new folder, or a folder that moves in, can get entries before its watch
exists. After the watch is added, the watcher reads the folder, writes
"create" for each entry that it did not see yet, and adds watches below it
with the same rule.

The watch limit is 8192 watches. A move out of the tree has no matching
IN_MOVED_TO in the same read batch, or in the next short wait, and gives
"delete". On SIGTERM the watcher sets a flag, reads the queue one more
time, writes all lines, and exits 0. When inotify is not available, it
exits 3. The standard library only.
"""

import argparse
import collections
import ctypes
import errno
import json
import os
import select
import signal
import struct
import sys
import time

IN_MODIFY = 0x00000002
IN_CLOSE_WRITE = 0x00000008
IN_MOVED_FROM = 0x00000040
IN_MOVED_TO = 0x00000080
IN_CREATE = 0x00000100
IN_DELETE = 0x00000200
IN_Q_OVERFLOW = 0x00004000
IN_IGNORED = 0x00008000
IN_ONLYDIR = 0x01000000
IN_DONT_FOLLOW = 0x02000000
IN_ISDIR = 0x40000000
IN_CLOEXEC = 0o2000000

MASK = (
    IN_MODIFY
    | IN_CLOSE_WRITE
    | IN_MOVED_FROM
    | IN_MOVED_TO
    | IN_CREATE
    | IN_DELETE
    | IN_ONLYDIR
    | IN_DONT_FOLLOW
)
WATCH_LIMIT = 8192
# The folders of the agents of the kit below a home. The first walk of a
# DIR walks these first, so that a large folder of another program cannot
# use the watches before them.
AGENT_DIRS = (
    ".claude",
    ".codex",
    ".gemini",
    ".cursor",
    ".copilot",
    ".config/opencode",
    ".local/share/opencode",
    ".local/state/opencode",
    ".cache/opencode",
    ".local/share/cursor-agent",
)
MARK_PREFIX = ".kit-trace-mark."
WRITE_WINDOW = 0.1
MOVE_WAIT = 0.05
STOP_POLL = 0.1
DRAIN_READS = 64
HEADER = struct.Struct("iIII")


def now_ms():
    return time.time_ns() // 1000000


_stop = [False]


def on_term(signum, frame):
    """Only set a flag. The loop sees it and stops."""
    _stop[0] = True


class Watcher:
    def __init__(self, libc, fd, out_fd, limit=WATCH_LIMIT, tops=(), uid=None, parent=None):
        self.libc = libc
        self.fd = fd
        self.out_fd = out_fd
        self.limit = limit
        # The first walk keeps one eighth of the watches for later folders.
        self.walk_limit = limit - max(1, limit // 8)
        self.tops = set(tops)
        self.uid = os.getuid() if uid is None else uid
        self.owner = {}
        self.parent = parent
        self.orphan = False
        self.unknown_from = set()
        self.wd2path = {}
        self.path2wd = {}
        self.seen = set()
        self.lines = []
        self.buf = b""
        self.limit_sent = False
        self.pend_write = {}
        self.pend_from = {}
        self.batch = 0

    # Output.

    def emit(self, kind, path=None, is_dir=False, src=None, t=None):
        rec = {"t": now_ms() if t is None else t, "kind": kind}
        if path is not None:
            rec["path"] = path
            rec["dir"] = bool(is_dir)
        if src is not None:
            rec["from"] = src
        self.lines.append(json.dumps(rec))

    def flush(self):
        """Write the lines. Clear the buffer only after a write succeeds."""
        if self.lines:
            self.buf += ("\n".join(self.lines) + "\n").encode("ascii")
            self.lines = []
        while self.buf:
            n = os.write(self.out_fd, self.buf)
            self.buf = self.buf[n:]

    # Watches.

    def send_limit(self):
        if not self.limit_sent:
            self.limit_sent = True
            self.emit("limit")

    def add_watch(self, path, limit=None):
        """Add a watch. Return the wd, or None when there is no watch."""
        if path in self.path2wd:
            return self.path2wd[path]
        if len(self.wd2path) >= (self.limit if limit is None else limit):
            self.send_limit()
            return None
        wd = self.libc.inotify_add_watch(self.fd, os.fsencode(path), MASK)
        if wd < 0:
            if ctypes.get_errno() == errno.ENOSPC:
                self.send_limit()
            return None
        old = self.wd2path.get(wd)
        if old is not None:
            self.path2wd.pop(old, None)
        self.wd2path[wd] = path
        self.path2wd[path] = wd
        return wd

    def drop_watches(self, path, remove):
        """Forget the watches of a folder and of the folders below it.
        With remove, also remove them in the kernel."""
        prefix = path + "/"
        for p in [p for p in self.path2wd if p == path or p.startswith(prefix)]:
            wd = self.path2wd.pop(p)
            self.wd2path.pop(wd, None)
            if remove:
                self.libc.inotify_rm_watch(self.fd, wd)

    def forget(self, path, is_dir, remove):
        self.seen.discard(path)
        if is_dir:
            prefix = path + "/"
            self.seen = {p for p in self.seen if not p.startswith(prefix)}
            self.drop_watches(path, remove)

    def rename_watches(self, src, dst):
        prefix = src + "/"
        for wd, p in list(self.wd2path.items()):
            if p == src or p.startswith(prefix):
                new = dst + p[len(src):]
                del self.path2wd[p]
                self.wd2path[wd] = new
                self.path2wd[new] = wd
        self.seen = {
            (dst + p[len(src):]) if p.startswith(prefix) else p
            for p in self.seen
            if p != src
        }
        self.seen.add(dst)

    def walk_first(self, top, recursive, tops=()):
        """Add the first watches. No event is written. The walk does not
        go into a folder of "tops": it has its own watch, with no
        subfolder. A recursive walk first walks each folder of AGENT_DIRS
        below "top" that exists, in the order of the list. Then it walks
        the rest of "top" breadth first. At each level, the hidden folders
        come first, in alphabetical order, then the other folders."""
        if not self.add_watch_first(top):
            return
        if not recursive or top in tops:
            return
        done = set()
        for rel in AGENT_DIRS:
            p = os.path.join(top, rel)
            if os.path.isdir(p) and not os.path.islink(p):
                if not self.walk_tree(p, tops, done):
                    return
        self.walk_tree(top, tops, done)

    def add_watch_first(self, p):
        """Add a first watch. Return False when the walk must stop."""
        if self.add_watch(p, self.walk_limit) is None:
            return not self.limit_sent
        return True

    def walk_tree(self, root, tops, done):
        """Walk the folders below root breadth first. Return False when
        the walk limit is reached. A folder in "done" is not walked again."""
        queue = collections.deque([root])
        while queue:
            p = queue.popleft()
            if p in done:
                continue
            done.add(p)
            if not self.add_watch_first(p):
                return False
            if p not in self.path2wd or p in tops:
                continue
            try:
                with os.scandir(p) as it:
                    kids = [
                        (not e.name.startswith("."), e.name, e.path)
                        for e in it
                        if e.is_dir(follow_symlinks=False)
                    ]
            except OSError:
                continue
            kids.sort()
            queue.extend(k[2] for k in kids if k[2] not in done)
        return True

    def read_owners(self, top):
        """Keep the owner of each item at the top level of a --top folder
        that exists at the start."""
        try:
            with os.scandir(top) as it:
                for e in it:
                    try:
                        self.owner[e.path] = (
                            e.stat(follow_symlinks=False).st_uid != self.uid
                        )
                    except OSError:
                        pass
        except OSError:
            pass

    def foreign(self, base, path):
        """True when the item is at the top level of a --top folder and
        this account does not own it, or when it is gone before its owner
        is known."""
        if base not in self.tops:
            return False
        v = self.owner.get(path)
        if v is None:
            try:
                v = os.lstat(path).st_uid != self.uid
            except OSError:
                v = True
            self.owner[path] = v
        return v

    def add_tree(self, root):
        """Add a watch to a new folder, read it, write "create" for each
        entry that is not seen, and do the same below it."""
        stack = [root]
        while stack:
            p = stack.pop()
            if p != root and p in self.path2wd:
                continue
            if self.add_watch(p) is None:
                continue
            try:
                with os.scandir(p) as it:
                    entries = [(e.path, e.is_dir(follow_symlinks=False)) for e in it]
            except OSError:
                continue
            for ep, is_dir in entries:
                if ep not in self.seen:
                    self.seen.add(ep)
                    self.emit("create", ep, is_dir)
                if is_dir:
                    stack.append(ep)

    # Events.

    def flush_writes(self, path=None, force=False):
        """Write the pending "write" lines that are due (all with force).
        With a path, write only the line of that path."""
        now = time.monotonic()
        for p, (due, t) in list(self.pend_write.items()):
            if path is not None and p != path:
                continue
            if path is not None or force or due <= now:
                del self.pend_write[p]
                self.emit("write", p, False, t=t)

    def on_event(self, wd, mask, cookie, name):
        if mask & IN_Q_OVERFLOW:
            self.emit("overflow")
            return
        if mask & IN_IGNORED:
            p = self.wd2path.pop(wd, None)
            if p is not None and self.path2wd.get(p) == wd:
                del self.path2wd[p]
            return
        base = self.wd2path.get(wd)
        if base is None or not name:
            return
        path = base + "/" + name
        is_dir = bool(mask & IN_ISDIR)
        if base in self.tops:
            if mask & IN_MOVED_FROM:
                # The item has a new name now, so its owner cannot be
                # read here. An owner that is not known is decided at
                # IN_MOVED_TO, from the new name.
                v = self.owner.pop(path, None)
                if v:
                    return
                if v is None:
                    self.unknown_from.add(cookie)
            else:
                if mask & (IN_CREATE | IN_MOVED_TO):
                    # A new item: read its owner again.
                    self.owner.pop(path, None)
                if self.foreign(base, path):
                    if mask & IN_DELETE:
                        self.owner.pop(path, None)
                    elif mask & IN_MOVED_TO:
                        src = self.pend_from.pop(cookie, None)
                        if src is not None and cookie not in self.unknown_from:
                            # It left the part of the tree that is recorded.
                            self.emit("delete", src[0], src[1])
                            self.forget(src[0], src[1], True)
                        self.unknown_from.discard(cookie)
                    return
                if mask & IN_DELETE:
                    self.owner.pop(path, None)
        if mask & IN_CREATE:
            if name.startswith(MARK_PREFIX):
                # A mark of the kit: the lines before it come first.
                self.flush_writes(force=True)
            if path not in self.seen:
                self.seen.add(path)
                self.emit("create", path, is_dir)
            if is_dir:
                self.add_tree(path)
        elif mask & (IN_MODIFY | IN_CLOSE_WRITE):
            if not is_dir and path not in self.pend_write:
                self.pend_write[path] = (
                    time.monotonic() + WRITE_WINDOW,
                    now_ms(),
                )
        elif mask & IN_DELETE:
            self.flush_writes(path)
            self.emit("delete", path, is_dir)
            self.forget(path, is_dir, False)
        elif mask & IN_MOVED_FROM:
            self.flush_writes(path)
            self.pend_from[cookie] = (path, is_dir, self.batch)
        elif mask & IN_MOVED_TO:
            self.unknown_from.discard(cookie)
            src = self.pend_from.pop(cookie, None)
            if src is not None:
                self.emit("move", path, is_dir, src=src[0])
                if is_dir:
                    self.rename_watches(src[0], path)
                    if path not in self.path2wd:
                        # The folder had no watch: treat it as a new one.
                        self.add_tree(path)
                else:
                    self.seen.discard(src[0])
                    self.seen.add(path)
            else:
                self.seen.add(path)
                self.emit("create", path, is_dir)
                if is_dir:
                    self.add_tree(path)

    def expire_moves(self, everything):
        """A move out of the tree has no IN_MOVED_TO: write "delete"."""
        for cookie, (path, is_dir, batch) in list(self.pend_from.items()):
            if everything or batch < self.batch:
                del self.pend_from[cookie]
                if cookie in self.unknown_from:
                    # A --top item with no known owner left the tree.
                    self.unknown_from.discard(cookie)
                else:
                    self.emit("delete", path, is_dir)
                self.forget(path, is_dir, True)

    def timeout(self):
        t = None
        if self.pend_from:
            t = MOVE_WAIT
        if self.pend_write:
            due = min(d for d, _ in self.pend_write.values())
            w = max(0.0, due - time.monotonic())
            t = w if t is None else min(t, w)
        return t

    def read_events(self):
        data = os.read(self.fd, 65536)
        self.batch += 1
        pos = 0
        while pos + HEADER.size <= len(data):
            wd, mask, cookie, n = HEADER.unpack_from(data, pos)
            pos += HEADER.size
            raw = data[pos : pos + n].split(b"\0", 1)[0]
            pos += n
            self.on_event(wd, mask, cookie, os.fsdecode(raw))

    def run(self):
        """Run until the stop flag is set. At the end, read what is in
        the queue and write all lines, also after an error."""
        try:
            while not _stop[0]:
                if self.parent is not None and os.getppid() != self.parent:
                    self.orphan = True
                    break
                t = self.timeout()
                t = STOP_POLL if t is None else min(t, STOP_POLL)
                ready, _, _ = select.select([self.fd], [], [], t)
                if ready:
                    self.read_events()
                    self.expire_moves(False)
                elif self.pend_from:
                    self.expire_moves(True)
                self.flush_writes()
                self.flush()
        finally:
            self.finish()

    def finish(self):
        """Drain the queue without blocking, then write all.

        The drain stops after DRAIN_READS reads, so that a writer that
        keeps the queue full cannot hold the stop.
        """
        try:
            for _ in range(DRAIN_READS):
                if not select.select([self.fd], [], [], 0)[0]:
                    break
                self.read_events()
        finally:
            try:
                self.expire_moves(True)
                self.flush_writes(force=True)
            finally:
                self.flush()


def open_inotify():
    """Return (libc, fd), or None when inotify is not available."""
    try:
        libc = ctypes.CDLL(None, use_errno=True)
        init = libc.inotify_init1
        libc.inotify_add_watch
        libc.inotify_rm_watch
    except (OSError, AttributeError):
        return None
    init.argtypes = [ctypes.c_int]
    libc.inotify_add_watch.argtypes = [
        ctypes.c_int,
        ctypes.c_char_p,
        ctypes.c_uint32,
    ]
    libc.inotify_rm_watch.argtypes = [ctypes.c_int, ctypes.c_int]
    fd = init(IN_CLOEXEC)
    if fd < 0:
        return None
    return libc, fd


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--ready", required=True)
    ap.add_argument("--top", action="append", default=[])
    ap.add_argument("--parent", type=int)
    ap.add_argument("--watch-limit", type=int, default=WATCH_LIMIT)
    ap.add_argument("--uid", type=int)
    ap.add_argument("dirs", nargs="*")
    args = ap.parse_args()
    if not args.dirs and not args.top:
        ap.error("no folder to watch")
    ino = open_inotify()
    if ino is None:
        print("trace-files.py: inotify is not available", file=sys.stderr)
        return 3
    libc, fd = ino
    out_fd = os.open(args.out, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    if args.watch_limit < 2:
        ap.error("--watch-limit must be 2 or more")
    tops = {os.path.abspath(d) for d in args.top}
    w = Watcher(libc, fd, out_fd, args.watch_limit, tops, args.uid, args.parent)
    signal.signal(signal.SIGTERM, on_term)
    for d in sorted(tops):
        w.walk_first(d, False)
        w.read_owners(d)
    for d in args.dirs:
        w.walk_first(os.path.abspath(d), True, tops)
    w.flush()
    if _stop[0]:
        w.finish()
        return 0
    tmp = args.ready + ".tmp"
    with open(tmp, "w", encoding="ascii") as f:
        f.write("ready\n")
    os.replace(tmp, args.ready)
    w.run()
    if w.orphan:
        # No build reads the lines now. They hold real paths: delete them.
        for f in (args.out, args.ready):
            try:
                os.unlink(f)
            except OSError:
                pass
        try:
            os.rmdir(os.path.dirname(os.path.abspath(args.out)))
        except OSError:
            pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
