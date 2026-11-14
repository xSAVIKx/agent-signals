#!/usr/bin/env -S python3 -I
"""Make the committed eBPF fixture from the raw/ folder of one trace.

Run: python3 -I tools/make-ebpf-fixture.py RAW OUT

RAW is the raw/ folder of a trace that traces.yml made with raw=true (the
scrubbed copy of KIT_TRACE_KEEP_RAW). OUT is a new folder. The script:

1. copies each file of RAW to OUT;
2. in ebpf.txt, changes each IPv6 address of a connect6 line that is not
   ::1 to 2001:db8::N (HI b80d0120, LO the last 8 bytes with N in network
   order, read as a little-endian number), with the same N for the same
   address;
3. when ebpf.txt is larger than 1 MB, keeps each fork, exec and exit line,
   each line of a pid in the agent tree at that time (the tree of the
   agent pid of sessions.tsv, through the fork lines), the lines that are
   not events, and the first 500 other lines;
4. checks OUT: an IPv4 address other than 127.0.0.1 and 0.0.0.0, or a line
   with "runner", "/home/", "cloudapp" or "internal" (case ignored), is an
   error. The script then prints the lines and exits 1.

Exit codes: 0 done, 1 a check failed, 2 bad use.
"""
import os
import re
import shutil
import sys

MAX_BYTES = 1 << 20
OTHER_LINES = 500
LOOPBACK6 = ("0", "100000000000000")
IPV4 = re.compile(r"(?<![0-9.])([0-9]{1,3}\.){3}[0-9]{1,3}(?![0-9.])")
WORDS = re.compile(r"runner|/home/|cloudapp|internal", re.I)


def agent_pids(raw):
    pids = set()
    with open(os.path.join(raw, "sessions.tsv"), encoding="utf-8") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 4 and parts[3].isdigit():
                pids.add(parts[3])
    return pids


def rewrite_v6(lines):
    seen = {}
    out = []
    for line in lines:
        f = line.split("\t")
        if len(f) == 6 and f[1] == "connect6" and (f[4], f[5]) != LOOPBACK6:
            n = seen.setdefault((f[4], f[5]), len(seen) + 1)
            # LO is the last 8 bytes of the address, read as a
            # little-endian number: N as 8 bytes in network order.
            lo = int.from_bytes(n.to_bytes(8, "big"), "little")
            f[4], f[5] = "b80d0120", "%x" % lo
            line = "\t".join(f)
        out.append(line)
    return out


def trim(lines, roots):
    member = set(roots)
    others = 0
    out = []
    for line in lines:
        f = line.split("\t")
        if len(f) < 3 or not f[0].isdigit():
            # Not an event: an empty line or the counters line.
            out.append(line)
            continue
        word, pid = f[1], f[2]
        if word == "fork" and len(f) >= 4:
            if pid in member or f[3] in roots:
                member.add(f[3])
            else:
                # A pid that the kernel gives again is not in the tree.
                member.discard(f[3])
            out.append(line)
        elif word in ("exec", "exit"):
            out.append(line)
            if word == "exit" and pid not in roots:
                member.discard(pid)
        elif pid in member:
            out.append(line)
        elif others < OTHER_LINES:
            others += 1
            out.append(line)
    return out


def check(folder):
    bad = []
    for name in sorted(os.listdir(folder)):
        with open(os.path.join(folder, name), encoding="utf-8", errors="replace") as f:
            for n, line in enumerate(f, 1):
                for m in IPV4.finditer(line):
                    if m.group(0) not in ("127.0.0.1", "0.0.0.0"):
                        bad.append("%s:%d: an IPv4 address: %s" % (name, n, m.group(0)))
                if WORDS.search(line):
                    bad.append("%s:%d: a host word: %s" % (name, n, line.rstrip()[:160]))
    return bad


def main(argv):
    if len(argv) != 3 or not os.path.isdir(argv[1]) or os.path.exists(argv[2]):
        print("usage: make-ebpf-fixture.py RAW OUT (OUT must not exist)", file=sys.stderr)
        return 2
    raw, out = argv[1], argv[2]
    shutil.copytree(raw, out)
    path = os.path.join(out, "ebpf.txt")
    with open(path, encoding="utf-8", newline="\n") as f:
        lines = f.read().split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    lines = rewrite_v6(lines)
    if os.path.getsize(path) > MAX_BYTES:
        lines = trim(lines, agent_pids(raw))
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    bad = check(out)
    for b in bad:
        print(b)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
