#!/usr/bin/env python3
"""trace-cast.py: record the output of a terminal as asciicast v2.

Run: python3 -I trace-cast.py --t0 FILE --out FILE --width N --height N

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
    args = ap.parse_args()

    with open(args.t0, encoding="ascii") as f:
        t0_ms = int(f.read().strip())

    dec = codecs.getincrementaldecoder("utf-8")(errors="replace")
    with open(args.out, "a", encoding="utf-8") as out:
        if out.tell() == 0:
            header = {
                "version": 2,
                "width": args.width,
                "height": args.height,
                "timestamp": t0_ms // 1000,
                "env": {"TERM": "xterm-256color"},
            }
            out.write(json.dumps(header) + "\n")
            out.flush()
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
                    out.write(json.dumps([round(secs, 3), "o", tail], ensure_ascii=False) + "\n")
                    out.flush()
                break
            text = dec.decode(data)
            if not text:
                continue
            secs = time.time() - t0_ms / 1000.0
            out.write(json.dumps([round(secs, 3), "o", text], ensure_ascii=False) + "\n")
            out.flush()


if __name__ == "__main__":
    sys.exit(main())
