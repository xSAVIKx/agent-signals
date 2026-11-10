"""trace-cast-scrub.py: scrub the text of an asciicast v2 file.

Run: python3 -I trace-cast-scrub.py --scrub FILE IN OUT

FILE is tools/scrub.sh. The scrub reads lines of text, not JSON. On the
JSON line of an event, a path rule can take the "\\" of an escape such as
\\" or \\u001b, and the line is then not JSON. So this program gives the
scrub the decoded text of each event, and encodes the result again:

1. The header line (the first line) stays as it is. The kit writes it,
   and it holds only numbers.
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

CTRL_RE = re.compile("[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")
MARK_RE = re.compile(r"\(@C([0-9a-f]{2})@\)")


def hide(text):
    return CTRL_RE.sub(lambda m: "(@C%02x@)" % ord(m.group(0)), text)


def show(text):
    return MARK_RE.sub(lambda m: chr(int(m.group(1), 16)), text)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scrub", required=True)
    ap.add_argument("src")
    ap.add_argument("dst")
    args = ap.parse_args()
    with open(args.src, encoding="utf-8") as f:
        lines = f.read().split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    # parts: for each line, None (keep it) or the event and its part count.
    plan = []
    text = []
    for i, line in enumerate(lines):
        ev = None
        if i > 0:
            try:
                ev = json.loads(line)
            except ValueError:
                ev = None
        if isinstance(ev, list) and len(ev) == 3 and isinstance(ev[2], str):
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
