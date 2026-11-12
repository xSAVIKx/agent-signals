"""trace-cast-scrub.py: scrub the text of an asciicast v2 file.

Run: python3 -I trace-cast-scrub.py --scrub FILE [--cut-name NAME]...
         [--cut-end NAME]... IN OUT

FILE is tools/scrub.sh. The scrub reads lines of text, not JSON. On the
JSON line of an event, a path rule can take the "\\" of an escape such as
\\" or \\u001b, and the line is then not JSON. So this program gives the
scrub the decoded text of each event, and encodes the result again:

1. The header line (the first line) stays as it is. The kit writes it,
   and it holds only numbers.
1a. A cut path. An agent can draw a long folder as "/\u2026/TAIL", for
   example the cwd in a welcome box. The scrub knows only full paths, so
   TAIL can keep a part of the run folder or of the work root. Each
   "/\u2026/TAIL" whose TAIL holds a --cut-name, or whose last folder is a
   --cut-end, becomes "/work/example/LAST", with LAST the last folder of
   TAIL. The program reads the text of the "o" events as one stream, so
   a cut path that is split over two or more events is found too. The
   new text goes to the event where the cut path starts, and the rest of
   the cut path leaves the next events. A color sequence (ESC [ ... m)
   inside TAIL does not end it. It goes after the new text. A space ends
   TAIL, so a cut path with a space in it is not found.
2. The text of each event is split at each line feed. Each part is one
   line of a temp file. A control character other than a tab or a
   carriage return becomes the mark "(@Cxx@)" (xx is its hex code). The
   scrub ends a path at "(", so a path rule does not take the escape
   sequence after a path.
3. "sh FILE TEMP" runs. The scrub keeps the number of lines.
4. Each line goes back to its event, each mark becomes its character
   again, and each event is written as one JSON line.

The environment goes to the scrub as it is (SCRUB_EXTRA and the others).
A line that is not an event of three items stays as it is. The program
exits 1 when the scrub fails, when the scrub changes the number of lines,
or when an output line is not valid JSON. The standard library only.
"""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile

CUT_RE = re.compile("/\u2026/(?:[^\\s\x1b\"'\u2502]|\x1b\\[[0-9;]*m)*")
SGR_RE = re.compile("\x1b\\[[0-9;]*m")
CTRL_RE = re.compile("[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")
MARK_RE = re.compile(r"\(@C([0-9a-f]{2})@\)")


def hide(text):
    return CTRL_RE.sub(lambda m: "(@C%02x@)" % ord(m.group(0)), text)


def show(text):
    return MARK_RE.sub(lambda m: chr(int(m.group(1), 16)), text)


def cut_fix(events, names, ends):
    """Rewrite the cut paths in the texts of EVENTS (lists of 3 items) in
    place. The texts are read as one stream (read the header)."""
    names = [n for n in names if n]
    ends = [e for e in ends if e]
    if not events or not (names or ends):
        return
    texts = [ev[2] for ev in events]
    joined = "".join(texts)
    if "\u2026" not in joined:
        return
    bounds = []
    pos = 0
    for t in texts:
        bounds.append((pos, pos + len(t)))
        pos += len(t)
    edits = [[] for _ in texts]
    k = 0
    for m in CUT_RE.finditer(joined):
        tail = m.group(0)[3:]
        plain = SGR_RE.sub("", tail)
        last = plain.rstrip("/").rsplit("/", 1)[-1]
        if not (any(n in plain for n in names) or last in ends):
            continue
        new = "/work/example/" + last + "".join(SGR_RE.findall(tail))
        s, e = m.span()
        while bounds[k][1] <= s:
            k += 1
        first = True
        j = k
        while j < len(bounds) and bounds[j][0] < e:
            a, b = bounds[j]
            if b > a:
                lo, hi = max(s, a) - a, min(e, b) - a
                edits[j].append((lo, hi, new if first else ""))
                first = False
            j += 1
    for ev, ed in zip(events, edits):
        if not ed:
            continue
        t = ev[2]
        for lo, hi, new in reversed(ed):
            t = t[:lo] + new + t[hi:]
        ev[2] = t


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scrub", required=True)
    ap.add_argument("--cut-name", action="append", default=[])
    ap.add_argument("--cut-end", action="append", default=[])
    ap.add_argument("src")
    ap.add_argument("dst")
    args = ap.parse_args()
    with open(args.src, encoding="utf-8") as f:
        lines = f.read().split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    evs = []
    for i, line in enumerate(lines):
        ev = None
        if i > 0:
            try:
                ev = json.loads(line)
            except ValueError:
                ev = None
        ok = isinstance(ev, list) and len(ev) == 3 and isinstance(ev[2], str)
        evs.append(ev if ok else None)
    cut_fix([ev for ev in evs if ev is not None and ev[1] == "o"], args.cut_name, args.cut_end)
    # parts: for each line, None (keep it) or the event and its part count.
    plan = []
    text = []
    for ev in evs:
        if ev is not None:
            parts = ev[2].split("\n")
            plan.append((ev, len(parts)))
            text.extend(hide(p) for p in parts)
        else:
            plan.append((None, 0))
    # The temp file goes next to OUT, not in a shared temp folder.
    fd, tmp = tempfile.mkstemp(
        prefix=".cast-scrub.", dir=os.path.dirname(os.path.abspath(args.dst))
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as f:
            f.write("".join(p + "\n" for p in text))
        res = subprocess.run(
            ["sh", args.scrub, tmp],
            stdout=subprocess.PIPE,
            stderr=sys.stderr,
            check=False,
        )
    finally:
        os.unlink(tmp)
    if res.returncode != 0:
        print("trace-cast-scrub: the scrub failed", file=sys.stderr)
        return 1
    got = res.stdout.decode("utf-8", errors="replace").split("\n")
    if got and got[-1] == "":
        got.pop()
    if len(got) != len(text):
        print(
            "trace-cast-scrub: the scrub changed the line count: %d, want %d"
            % (len(got), len(text)),
            file=sys.stderr,
        )
        return 1
    out = []
    pos = 0
    for line, (ev, n) in zip(lines, plan):
        if ev is None:
            out.append(line)
            continue
        ev[2] = "\n".join(show(p) for p in got[pos : pos + n])
        pos += n
        out.append(json.dumps(ev, ensure_ascii=False))
    for i, line in enumerate(out):
        try:
            json.loads(line)
        except ValueError:
            print("trace-cast-scrub: line %d is not JSON" % (i + 1), file=sys.stderr)
            return 1
    with open(args.dst, "w", encoding="utf-8") as f:
        f.write("".join(line + "\n" for line in out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
