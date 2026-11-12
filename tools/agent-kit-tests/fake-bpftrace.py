#!/usr/bin/env -S python3 -I
"""fake-bpftrace.py -B line SCRIPT ROOT STOP: a fake bpftrace for the
tests of the ebpf check of "kit trace" (test-trace-ebpf.sh).

It does not read SCRIPT. It polls /proc every 20 ms and writes the lines
of probes/agent/trace-ebpf.bt to stdout, one flush for each line. The
time is the boot clock in ns, as "nsecs" of bpftrace.

- A process of this account that the first poll did not see is new. It
  gives "fork PPID PID COMM" (PPID from /proc/PID/stat) and
  "exec PID COMM PATH".
- A change of /proc/PID/cmdline of a known pid gives one more "exec".
- PATH is the link /proc/PID/exe. When that program is a shell (sh, dash
  or bash) and the second word of the cmdline is a file, PATH is that
  word. This is the form of the kernel for a "#!" script.
- A pid that is gone gives "exit PID".

A poll cannot see the double fork of the tmux server, so the fake does
not follow the tree of ROOT: it writes the lines of each new process.
The build keeps only the agent trees. The fake exits when ROOT or STOP
ends (a zombie counts as ended).

FAKE_BPFTRACE=fail: write "ERROR: test" to stderr and exit 1 at once.
FAKE_BPFTRACE=silent: write nothing until the end.
"""

import os
import sys
import time

SHELLS = ("sh", "dash", "bash")


def now():
    return time.clock_gettime_ns(time.CLOCK_BOOTTIME)


def ended(pid):
    """True when pid does not run or is a zombie."""
    try:
        with open("/proc/%d/stat" % pid, encoding="utf-8", errors="replace") as f:
            stat = f.read()
    except OSError:
        return True
    return stat[stat.rfind(")") + 2:][:1] in ("Z", "X", "")


def ours(uid):
    """The pids of the account uid, except this process."""
    me = os.getpid()
    got = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        pid = int(name)
        if pid == me:
            continue
        try:
            if os.stat("/proc/" + name).st_uid != uid:
                continue
        except OSError:
            continue
        got.append(pid)
    return got


def read(path):
    try:
        with open(path, "rb") as f:
            return f.read()
    except OSError:
        return None


def facts(pid):
    """(ppid, comm, path) of pid, or None when it is gone."""
    stat = read("/proc/%d/stat" % pid)
    if stat is None:
        return None
    stat = stat.decode("utf-8", "replace")
    rest = stat[stat.rfind(")") + 2:].split()
    try:
        ppid = int(rest[1])
    except (IndexError, ValueError):
        return None
    comm = (read("/proc/%d/comm" % pid) or b"").decode("utf-8", "replace").strip()
    try:
        path = os.readlink("/proc/%d/exe" % pid)
    except OSError:
        path = ""
    words = (read("/proc/%d/cmdline" % pid) or b"").split(b"\0")
    if os.path.basename(path) in SHELLS and len(words) > 1 and words[1]:
        second = words[1].decode("utf-8", "replace")
        if os.path.isfile(second):
            path = second
    return ppid, comm, path


def out(line):
    sys.stdout.write("%d\t%s\n" % (now(), line))
    sys.stdout.flush()


def main():
    args = sys.argv[1:]
    if args[:2] == ["-B", "line"]:
        args = args[2:]
    if len(args) != 3:
        sys.stderr.write("usage: fake-bpftrace.py -B line SCRIPT ROOT STOP\n")
        return 2
    root, stop = int(args[1]), int(args[2])
    mode = os.environ.get("FAKE_BPFTRACE", "")
    if mode == "fail":
        sys.stderr.write("ERROR: test\n")
        return 1
    uid = os.getuid()
    seen = {pid: read("/proc/%d/cmdline" % pid) for pid in ours(uid)}
    first = set(seen)
    while not ended(root) and not ended(stop):
        time.sleep(0.02)
        if mode == "silent":
            continue
        pids = ours(uid)
        for pid in pids:
            cmd = read("/proc/%d/cmdline" % pid)
            if pid not in seen:
                got = facts(pid)
                if got is None:
                    continue
                seen[pid] = cmd
                ppid, comm, path = got
                out("fork\t%d\t%d\t%s" % (ppid, pid, comm))
                out("exec\t%d\t%s\t%s" % (pid, comm, path))
            elif cmd and cmd != seen[pid]:
                seen[pid] = cmd
                got = facts(pid)
                if got is not None:
                    out("exec\t%d\t%s\t%s" % (pid, got[1], got[2]))
        live = set(pids)
        for pid in list(seen):
            if pid not in live:
                del seen[pid]
                if pid not in first:
                    out("exit\t%d" % pid)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (BrokenPipeError, KeyboardInterrupt):
        sys.exit(0)
