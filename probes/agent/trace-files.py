"""A file watcher for a traced session (the file check, Linux only).

Run: python3 -I trace-files.py --out FILE --ready FILE [--top DIR]... DIR...

The watcher uses inotify through ctypes. It watches each DIR and all
folders below it. Each --top DIR is watched without its subfolders that
exist at the start. A folder that comes later gets a watch, in all cases.
The watcher writes the --ready file when it has added all first watches.

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

The limit is 8192 watches. A move out of the tree has no matching
IN_MOVED_TO in the same read batch, or in the next short wait, and gives
"delete". On SIGTERM the watcher writes its lines and exits 0. When
inotify is not available, it exits 3. The standard library only.
"""

import argparse
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
WRITE_WINDOW = 0.1
MOVE_WAIT = 0.05
HEADER = struct.Struct("iIII")


def now_ms():
    return time.time_ns() // 1000000


class Term(Exception):
    """Raised by the SIGTERM handler."""


def on_term(signum, frame):
    raise Term()


class Watcher:
    def __init__(self, libc, fd, out_fd):
        self.libc = libc
        self.fd = fd
        self.out_fd = out_fd
        self.wd2path = {}
        self.path2wd = {}
        self.seen = set()
        self.lines = []
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
        if self.lines:
            data = ("\n".join(self.lines) + "\n").encode("ascii")
            self.lines = []
            while data:
                n = os.write(self.out_fd, data)
                data = data[n:]

    # Watches.

    def send_limit(self):
        if not self.limit_sent:
            self.limit_sent = True
            self.emit("limit")

    def add_watch(self, path):
        """Add a watch. Return the wd, or None when there is no watch."""
        if path in self.path2wd:
            return self.path2wd[path]
        if len(self.wd2path) >= WATCH_LIMIT:
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

    def walk_first(self, top, recursive):
        """Add the first watches. No event is written."""
        stack = [top]
        while stack:
            p = stack.pop()
            if self.add_watch(p) is None:
                if self.limit_sent:
                    return
                continue
            if not recursive:
                continue
            try:
                with os.scandir(p) as it:
                    for e in it:
                        if e.is_dir(follow_symlinks=False):
                            stack.append(e.path)
            except OSError:
                pass

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
        if mask & IN_CREATE:
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
            src = self.pend_from.pop(cookie, None)
            if src is not None:
                self.emit("move", path, is_dir, src=src[0])
                if is_dir:
                    self.rename_watches(src[0], path)
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
        while True:
            ready, _, _ = select.select([self.fd], [], [], self.timeout())
            if ready:
                self.read_events()
                self.expire_moves(False)
            else:
                self.expire_moves(True)
            self.flush_writes()
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
    w = Watcher(libc, fd, out_fd)
    signal.signal(signal.SIGTERM, on_term)
    try:
        for d in args.top:
            w.walk_first(os.path.abspath(d), False)
        for d in args.dirs:
            w.walk_first(os.path.abspath(d), True)
        w.flush()
        tmp = args.ready + ".tmp"
        with open(tmp, "w", encoding="ascii") as f:
            f.write("ready\n")
        os.replace(tmp, args.ready)
        w.run()
    except Term:
        pass
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    try:
        w.flush_writes(force=True)
        w.expire_moves(True)
        w.flush()
    except OSError:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
