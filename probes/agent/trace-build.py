"""trace-build.py: build trace.json from the raw folder of a trace.

Run: python3 -I trace-build.py --raw DIR --meta FILE --out DIR

DIR of --raw is RUN/.trace, which the recorders wrote. FILE of --meta is a
JSON object with the keys of "meta" that the kit knows. The program writes
DIR/trace.json in the format of schema/trace.schema.json. When the cast is
usable, it copies terminal.cast to DIR. The run folder is the parent of
the raw folder. The program exits 1 when t0 is missing or not a number.

Raw files (a missing file means that its check did not run):
  t0            the start in epoch milliseconds.
  states.tsv    MS<tab>STATE.
  sessions.tsv  NAME<tab>HOME<tab>WORK<tab>AGENT_PID<tab>SOCKDIR.
  terminal.cast asciicast v2 (trace-cast.py).
  proxy.jsonl   one connection in each line (trace-proxy.py).
  files.jsonl   one file event in each line (trace-files.py).
  model-NAME.log  MS<space>LINE (fake-model.py --log-times).
  skipped.tsv   CHECK<tab>REASON.
  checks        the selected checks, as a comma list. No file or an empty
                file means all checks.

Rules:
- Each time is MS - t0, as an integer, never below 0. Events are sorted
  by time.
- A path is normalized. The longest known prefix wins: a session home
  becomes ~, a work folder becomes WORK, the temp folder (TMPDIR, else
  /tmp) becomes TMP. A file event under the run folder, but not under a
  home or a work folder, is dropped. A file event under a SOCKDIR is
  dropped. The kit writes there.
- In each path, the account name and the host name become dev and host.
  In each name, a UUID becomes <uuid>, a run of 16 or more hex digits
  becomes <hex>, and a run of 5 or more digits becomes <n>.
- With a real home, a path under ~ whose first folder is not hidden
  becomes ~/<private>. The folders of a person are private.
- A model event holds the method, the route (with no query), and the
  model kind. It holds no text of the request. The program reads the model
  logs only when the network check is selected and ran.
- Only a fixture home, and not the login mode, keeps the terminal record.
  With any other home, "terminal" is null and the cast is deleted. A terminal line in skipped.tsv also gives null.

It uses the standard library only.
"""
import argparse
import json
import os
import re
import socket
import sys

STATES = (
    "start",
    "idle",
    "prompt",
    "busy",
    "dialog",
    "answer",
    "idle-after",
    "stop",
)
CHECKS = ("terminal", "network", "files", "ebpf")
FILE_KINDS = ("create", "write", "delete", "move")
METHODS = ("GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS")
WINDOW_MS = 2000
NEAR_LIMIT = 20

UUID_RE = re.compile(
    "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-"
    "[0-9A-Fa-f]{12}"
)
HEX_RE = re.compile("[0-9A-Fa-f]{16,}")
DIGITS_RE = re.compile("[0-9]{5,}")


def read_lines(path):
    """Return the lines of a file, or None when it is missing."""
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read().splitlines()
    except OSError:
        return None


def read_json_lines(path):
    """Return the JSON objects of a file. A bad line is skipped."""
    lines = read_lines(path)
    if lines is None:
        return None
    out = []
    for line in lines:
        try:
            obj = json.loads(line)
        except ValueError:
            continue
        if isinstance(obj, dict):
            out.append(obj)
    return out


def to_int(value, default=0):
    try:
        return int(value)
    except (TypeError, ValueError, OverflowError):
        return default


def clean_name(text):
    """Replace a UUID, a hex run and a digit run in a name."""
    text = UUID_RE.sub("<uuid>", text)
    text = HEX_RE.sub("<hex>", text)
    return DIGITS_RE.sub("<n>", text)


class Scrub:
    """The account and host names that a path must not hold."""

    def __init__(self):
        # An empty variable is the same as no variable.
        user = os.environ.get("SCRUB_USER")
        if not user:
            try:
                import pwd

                user = pwd.getpwuid(os.getuid()).pw_name
            except Exception:
                user = ""
        host = os.environ.get("SCRUB_HOST")
        names = []
        if host:
            names.append(host)
        else:
            for get in (socket.gethostname, socket.getfqdn):
                try:
                    names.append(get())
                except OSError:
                    pass
        full = sorted({n for n in names if n}, key=len, reverse=True)
        shorts = {n.split(".")[0] for n in full}
        self.full = [re.compile(re.escape(n), re.I) for n in full if "." in n]
        self.short = [
            re.compile(
                r"(?<![A-Za-z0-9])" + re.escape(s) + r"(\.[A-Za-z0-9-]+)*",
                re.I,
            )
            for s in sorted(shorts, key=len, reverse=True)
            if s
        ]
        self.user = None
        if user:
            self.user = re.compile(
                r"(?<![A-Za-z0-9])" + re.escape(user) + r"(?![A-Za-z0-9])",
                re.I,
            )

    def text(self, text):
        for rx in self.full:
            text = rx.sub("host", text)
        for rx in self.short:
            text = rx.sub("host", text)
        if self.user:
            text = self.user.sub("dev", text)
        return text


class Paths:
    """Map an absolute path to a normalized path, or drop it."""

    def __init__(self, sessions, run_dir, real_home):
        self.real_home = real_home
        self.scrub = Scrub()
        tmp = os.environ.get("TMPDIR") or "/tmp"
        # Each entry is (prefix, replacement). None means drop.
        self.rules = []
        self.rules.append((tmp.rstrip("/") or "/", "TMP"))
        self.rules.append((run_dir.rstrip("/"), None))
        for row in sessions:
            home, work, sock = row[1], row[2], row[4]
            if home:
                self.rules.append((home.rstrip("/"), "~"))
            if work:
                self.rules.append((work.rstrip("/"), "WORK"))
            if sock:
                self.rules.append((sock.rstrip("/"), None))
        # The longest prefix wins. At the same length a drop wins.
        self.rules.sort(key=lambda r: (-len(r[0]), r[1] is not None))

    def normalize(self, path):
        """Return the normalized path, or None to drop the event."""
        for prefix, repl in self.rules:
            if path == prefix or path.startswith(prefix + "/"):
                if repl is None:
                    return None
                # The scrub sees the rest only, so that it never changes
                # the placeholder.
                return self.clean_path(repl, path[len(prefix) :])
        return self.clean_path("", path)

    def clean_path(self, head, rest):
        parts = [clean_name(self.scrub.text(p)) for p in rest.split("/")]
        rest = "/".join(parts)
        if head == "~" and self.real_home:
            if len(parts) > 1 and not parts[1].startswith("."):
                return "~/<private>"
        return head + rest


def area(path):
    if path == "~" or path.startswith("~/"):
        return "home"
    if path == "WORK" or path.startswith("WORK/"):
        return "work"
    if path == "TMP" or path.startswith("TMP/"):
        return "tmp"
    return "other"


def read_sessions(raw):
    rows = []
    for line in read_lines(os.path.join(raw, "sessions.tsv")) or []:
        if not line.strip():
            continue
        cols = line.split("\t")
        cols += [""] * (5 - len(cols))
        rows.append(cols)
    return rows


def read_skipped(raw):
    out = []
    seen = set()
    for line in read_lines(os.path.join(raw, "skipped.tsv")) or []:
        cols = line.split("\t", 1)
        check = cols[0].strip()
        if check not in CHECKS:
            continue
        reason = cols[1].strip() if len(cols) > 1 else ""
        key = (check, reason)
        if key in seen:
            continue
        seen.add(key)
        out.append({"check": check, "reason": reason or "unknown"})
    return out


def read_selected(raw):
    lines = read_lines(os.path.join(raw, "checks"))
    words = set()
    for line in lines or []:
        words.update(w for w in re.split(r"[\s,]+", line) if w)
    return words


def read_states(raw, t0):
    out = []
    for line in read_lines(os.path.join(raw, "states.tsv")) or []:
        cols = line.split("\t")
        if len(cols) < 2 or cols[1].strip() not in STATES:
            continue
        try:
            ms = int(cols[0])
        except ValueError:
            continue
        out.append({"t": max(ms - t0, 0), "state": cols[1].strip()})
    out.sort(key=lambda s: s["t"])
    return out


def file_events(rows, t0, paths):
    """Return (events, limit_seen). Raw paths come in; events go out."""
    events = []
    live = set()
    limit = False
    rows = sorted(rows, key=lambda r: to_int(r.get("t"), 0))
    for row in rows:
        kind = row.get("kind")
        if kind == "limit":
            limit = True
            continue
        if kind not in FILE_KINDS:
            continue
        raw_path = row.get("path")
        if not isinstance(raw_path, str) or not raw_path:
            continue
        path = paths.normalize(raw_path)
        if path is None:
            # A move into a dropped folder is a delete of the source.
            src_raw = row.get("from")
            if kind == "move" and isinstance(src_raw, str) and src_raw:
                src = paths.normalize(src_raw)
                if src is not None:
                    live.discard(src_raw)
                    events.append(
                        {
                            "t": max(to_int(row.get("t")) - t0, 0),
                            "kind": "delete",
                            "pid": None,
                            "ppid": None,
                            "path": src,
                        }
                    )
            continue
        ev = {
            "t": max(to_int(row.get("t")) - t0, 0),
            "kind": kind,
            "pid": None,
            "ppid": None,
        }
        if kind == "create":
            # A scan can write a second create for a known entry.
            if raw_path in live:
                continue
            live.add(raw_path)
        elif kind == "delete":
            live.discard(raw_path)
        elif kind == "move":
            src_raw = row.get("from")
            if not isinstance(src_raw, str) or not src_raw:
                continue
            src = paths.normalize(src_raw)
            live.discard(src_raw)
            live.add(raw_path)
            # A source that the program drops has no usable name.
            ev["from"] = src if src is not None else "?"
        ev["path"] = path
        events.append(ev)
    return events, limit


def proxy_events(rows, t0, scrub):
    out = []
    for row in rows:
        host = row.get("host")
        if not isinstance(host, str) or not host:
            continue
        host = scrub.text(host)
        start = to_int(row.get("start"))
        end = row.get("end")
        status = row.get("status")
        out.append(
            {
                "t": max(start - t0, 0),
                "kind": "proxy",
                "pid": None,
                "ppid": None,
                "host": host,
                "port": min(max(to_int(row.get("port")), 0), 65535),
                "up": max(to_int(row.get("up")), 0),
                "down": max(to_int(row.get("down")), 0),
                "end": max(to_int(end, start) - t0, 0),
                "status": status
                if status in ("ok", "refused", "open", "error")
                else "error",
            }
        )
    return out


def model_events(raw, t0, paths):
    out = []
    names = sorted(
        n
        for n in os.listdir(raw)
        if n.startswith("model-") and n.endswith(".log")
    )
    for name in names:
        for line in read_lines(os.path.join(raw, name)) or []:
            words = line.split()
            if len(words) < 3 or words[1] not in METHODS:
                continue
            try:
                ms = int(words[0])
            except ValueError:
                continue
            route = clean_route(words[2])
            route = clean_name(paths.scrub.text(route))
            # Most fake model lines are "MS METHOD PATH RID KIND". The
            # Cursor lines have no RID: "MS POST RPC KIND".
            if len(words) > 4:
                kind = words[4]
            elif len(words) == 4:
                kind = words[3]
            else:
                kind = "-"
            if not re.fullmatch(r"[A-Za-z0-9_.-]+", kind):
                kind = "-"
            out.append(
                {
                    "t": max(ms - t0, 0),
                    "kind": "model",
                    "pid": None,
                    "ppid": None,
                    "method": words[1],
                    "route": route,
                    "model_kind": kind,
                }
            )
    return out


def clean_route(route):
    """Remove userinfo, query, fragment and parameters from a route."""
    m = re.match(r"([A-Za-z][A-Za-z0-9+.-]*://)(.*)$", route)
    if m:
        rest = m.group(2)
        cut = rest.find("/")
        auth = rest if cut < 0 else rest[:cut]
        tail = "" if cut < 0 else rest[cut:]
        route = m.group(1) + auth.rsplit("@", 1)[-1] + tail
    route = re.split(r"[?#;]", route, maxsplit=1)[0]
    return route or "/"


def event_text(ev):
    kind = ev["kind"]
    if kind == "proxy":
        return "proxy %s:%d" % (ev["host"], ev["port"])
    if kind == "model":
        return "model %s %s" % (ev["method"], ev["route"])
    if kind == "move":
        return "move %s -> %s" % (ev["from"], ev["path"])
    if "path" in ev:
        return "%s %s" % (kind, ev["path"])
    return kind


def summarize_files(events):
    sets = {"home": set(), "work": set(), "tmp": set(), "other": set()}
    for ev in events:
        for key in ("path", "from"):
            if ev.get(key) and ev[key] != "?" and ev["kind"] in FILE_KINDS:
                sets[area(ev[key])].add(ev[key])
    return {k: sorted(v) for k, v in sets.items()}


def summarize_hosts(events):
    table = {}
    for ev in events:
        if ev["kind"] != "proxy":
            continue
        row = table.setdefault(
            (ev["host"], ev["port"]),
            {
                "host": ev["host"],
                "port": ev["port"],
                "connections": 0,
                "up": 0,
                "down": 0,
            },
        )
        row["connections"] += 1
        row["up"] += ev["up"]
        row["down"] += ev["down"]
    return [table[k] for k in sorted(table)]


def timeline(states, events):
    out = []
    for st in states:
        near = [e for e in events if abs(e["t"] - st["t"]) <= WINDOW_MS]
        if len(near) > NEAR_LIMIT:
            near.sort(key=lambda e: abs(e["t"] - st["t"]))
            near = sorted(near[:NEAR_LIMIT], key=lambda e: e["t"])
        out.append(
            {
                "state": st["state"],
                "t": st["t"],
                "near": [
                    {"t": e["t"], "kind": e["kind"], "text": event_text(e)}
                    for e in near
                ],
            }
        )
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", required=True)
    ap.add_argument("--meta", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    raw = os.path.abspath(args.raw)

    t0_lines = read_lines(os.path.join(raw, "t0"))
    try:
        t0 = int(t0_lines[0].strip())
    except (TypeError, IndexError, ValueError):
        print("trace-build: no t0 in %s" % raw, file=sys.stderr)
        return 1
    try:
        with open(args.meta, encoding="utf-8") as f:
            meta = json.load(f)
        if not isinstance(meta, dict):
            raise ValueError("not an object")
    except (OSError, ValueError) as e:
        print("trace-build: bad --meta: %s" % e, file=sys.stderr)
        return 1

    run_dir = os.path.dirname(raw)
    real_home = meta.get("home") not in ("fixture", "throwaway")
    paths = Paths(read_sessions(raw), run_dir, real_home)
    skipped = read_skipped(raw)
    skipped_checks = {s["check"] for s in skipped}
    selected = read_selected(raw)

    def chosen(check):
        return (not selected or check in selected) and (
            check not in skipped_checks
        )

    checks = []
    events = []
    states = read_states(raw, t0)
    summary_files = None
    summary_hosts = None
    model_requests = None
    files_limit = False

    # The terminal record. The cast of a real home or of a login can hold
    # text of a person, so the program deletes it.
    cast = os.path.join(raw, "terminal.cast")
    terminal = None
    # Only a fixture home has fixed prompts. Any other home can hold text
    # of a person, so the cast is not kept.
    private_run = not (
        meta.get("home") == "fixture" and meta.get("mode") != "login"
    )
    if os.path.isfile(cast):
        if private_run:
            os.remove(cast)
        elif "terminal" not in skipped_checks:
            checks.append("terminal")
            terminal = "terminal.cast"

    rows = read_json_lines(os.path.join(raw, "files.jsonl"))
    if rows is not None and "files" not in skipped_checks:
        checks.append("files")
        fev, files_limit = file_events(rows, t0, paths)
        events += fev
        summary_files = summarize_files(fev)

    rows = read_json_lines(os.path.join(raw, "proxy.jsonl"))
    if rows is not None and "network" not in skipped_checks:
        checks.append("network")
        pev = proxy_events(rows, t0, paths.scrub)
        events += pev
        summary_hosts = summarize_hosts(pev)
        if chosen("network"):
            mev = model_events(raw, t0, paths)
            events += mev
            model_requests = len(mev)

    events.sort(key=lambda e: e["t"])
    order = {c: i for i, c in enumerate(CHECKS)}
    checks.sort(key=lambda c: order[c])

    meta["checks"] = checks
    meta["skipped"] = skipped
    meta["files_limit"] = files_limit
    result = {
        "provenance": "measured",
        "meta": meta,
        "states": states,
        "events": events,
        "terminal": terminal,
        "summary": {
            "files": summary_files,
            "hosts": summary_hosts,
            "model_requests": model_requests,
            "programs": None,
            "processes_left": None,
            "timeline": timeline(states, events),
        },
    }
    os.makedirs(args.out, exist_ok=True)
    with open(os.path.join(args.out, "trace.json"), "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)
        f.write("\n")
    if terminal:
        with open(cast, "rb") as src:
            data = src.read()
        with open(os.path.join(args.out, terminal), "wb") as dst:
            dst.write(data)
    return 0


if __name__ == "__main__":
    sys.exit(main())
