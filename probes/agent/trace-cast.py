#!/usr/bin/env python3
"""trace-cast.py: record the output of a terminal as asciicast v2.

Run: python3 -I trace-cast.py --t0 FILE --out FILE --width N --height N
         [--ready FILE] [--failed FILE] [--pid-file FILE]

The program reads raw bytes on stdin. It appends asciicast v2 to --out.
"kit session start" runs it through "tmux pipe-pane" when KIT_TRACE is set
and KIT_TRACE_CHECKS is empty or has the word "terminal".

- FILE of --t0 holds the start time of the trace in epoch milliseconds.
  Each event time is the number of seconds from this start, with 3
  decimals.
- The header line is {"version": 2, "width": N, "height": N, "timestamp":
  T0_SECONDS, "env": {"TERM": "xterm-256color"}}. The program writes it
  only when --out is empty or does not exist. A second start (resume)
  then continues the same file.
- Each event is [SECONDS_FROM_T0, "o", TEXT]. The program decodes UTF-8
  with an incremental decoder and errors="replace". A character that is
  split over two reads stays whole.
- With --ready FILE, the program makes this file after it opened --out and
  wrote the header, when the header was needed. The caller waits for the
  file, so that it does not start the agent before the recording works.
  When the program cannot open --out, it exits with an error and does not
  make the file.
- With --failed FILE, the program makes this file when a write to --out
  fails after it opened --out. This includes the header and the last
  flush at the end of the input. The program then writes one line to
  stderr and exits 1. "kit session stop" reads the file, because the
  agent continues to run when the recorder ends.
- With --pid-file FILE, the program writes its own pid and a newline to
  this file right after it starts, before it opens --out. "kit session
  stop" waits for this pid to end before it reads the --failed file,
  because the recorder is not in RUN/pids/.
- The program writes and flushes each event when it reads the bytes. It
  stops at the end of the input. An incomplete character at the end
  becomes U+FFFD in a last event.

It uses the standard library only.
"""
import argparse
import codecs
import json
import os
import sys
import time


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--t0", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--width", type=int, required=True)
    ap.add_argument("--height", type=int, required=True)
    ap.add_argument("--ready")
    ap.add_argument("--failed")
    ap.add_argument("--pid-file")
    args = ap.parse_args()

    if args.pid_file:
        with open(args.pid_file, "w", encoding="ascii") as f:
            f.write("%d\n" % os.getpid())

    with open(args.t0, encoding="ascii") as f:
        t0_ms = int(f.read().strip())

    dec = codecs.getincrementaldecoder("utf-8")(errors="replace")
    out = open(args.out, "a", encoding="utf-8")
    try:
        record(out, args, t0_ms, dec)
        put(out, None, close=True)
    except CastWriteError as e:
        if args.failed:
            try:
                open(args.failed, "w").close()
            except OSError:
                pass
        sys.stderr.write("trace-cast.py: a write to the cast failed: %s\n" % e)
        try:
            out.close()
        except OSError:
            pass
        return 1
    return 0


class CastWriteError(Exception):
    """A write to the open cast failed."""


def put(out, line, close=False):
    """Write and flush LINE (or close OUT), and raise CastWriteError on an OSError."""
    try:
        if close:
            out.close()
        else:
            out.write(line)
            out.flush()
    except OSError as e:
        raise CastWriteError(str(e)) from e


def record(out, args, t0_ms, dec):
    if out.tell() == 0:
        header = {
            "version": 2,
            "width": args.width,
            "height": args.height,
            "timestamp": t0_ms // 1000,
            "env": {"TERM": "xterm-256color"},
        }
        put(out, json.dumps(header) + "\n")
    if args.ready:
        open(args.ready, "w").close()
    while True:
        try:
            data = os.read(0, 65536)
        except InterruptedError:
            continue
        if not data:
            # An incomplete character at the end becomes U+FFFD.
            tail = dec.decode(b"", final=True)
            if tail:
                secs = time.time() - t0_ms / 1000.0
                put(out, json.dumps([round(secs, 3), "o", tail], ensure_ascii=False) + "\n")
            break
        text = dec.decode(data)
        if not text:
            continue
        secs = time.time() - t0_ms / 1000.0
        put(out, json.dumps([round(secs, 3), "o", text], ensure_ascii=False) + "\n")


if __name__ == "__main__":
    sys.exit(main())
