#!/usr/bin/env python3
"""Keep one GitHub issue for each traced agent version.

collect RUN --only LIST --out FILE
    Write a JSON list with one item for each RUN/traces/NAME/trace.json
    whose NAME is a line of LIST (the --passed file of check-traces.sh).
    An item holds only the keys of KEEP. A missing LIST gives [].

plan --summaries DIR --issues FILE --run-url URL --out FILE
    Read the collect files in DIR and the issue list in FILE (the output
    of `gh issue list --label trace --state all --json
    number,title,body,state`). Write a JSON list of actions: open an
    issue for a new key, or update an issue that does not have each item
    of the run.

The script reads only the summary and the meta keys of KEEP. It writes no
content of a trace. Python standard library only. Run with `python3 -I`.
"""

import argparse
import base64
import json
import os
import re
import sys
import zlib

KEEP = ("agent", "agent_version", "mode", "runner_image", "step", "checks", "skipped")
# The kinds of items, in the order of the body.
KINDS = ("programs", "files", "opened", "hosts", "direct", "dns", "processes_left")
# The order in which DATA drops a kind when it is too long.
DROP_ORDER = ("opened", "files", "hosts", "dns", "direct", "programs", "processes_left")
DATA_MAX = 40000
INFLATE_MAX = 16 * 1024 * 1024
BODY_MAX = 24000
ITEM_MAX = 200
TABLE_ROWS = 100
NO_IMAGE = "no-image"
DATA_RE = re.compile(r"^<!-- trace-data: ([A-Za-z0-9+/=]+) -->$", re.M)
TITLE_RE = re.compile(r"^trace: (\S+) (\S+) \((\S+)\)$")
CONTROL_RE = re.compile(r"[\x00-\x1f\x7f-\x9f]")


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def dump(obj, path):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(obj, f, indent=2, sort_keys=True)
        f.write("\n")


# ---------------------------------------------------------------- collect

def collect(run, only, out):
    names = []
    if os.path.isfile(only):
        with open(only, encoding="utf-8") as f:
            for line in f:
                name = line.strip()
                # A name is one folder of RUN/traces, never a path.
                if not name or name in (".", "..") or "/" in name or "\\" in name:
                    continue
                if name not in names:
                    names.append(name)
    items = []
    for name in sorted(names):
        path = os.path.join(run, "traces", name, "trace.json")
        if not os.path.isfile(path):
            continue
        trace = load(path)
        meta = trace.get("meta") or {}
        item = {key: meta.get(key) for key in KEEP}
        item["summary"] = trace.get("summary") or {}
        items.append(item)
    dump(items, out)


# ------------------------------------------------------------------ items

def clean(text):
    """Rule 6: no backtick, no control character, 200 characters at most."""
    text = CONTROL_RE.sub("", str(text)).replace("`", "'")
    if len(text) > ITEM_MAX:
        text = text[: ITEM_MAX - 3] + "..."
    return text


def folder(path):
    """The folder of a path, cut after the area and two more parts."""
    if path.startswith("/"):
        parts = [p for p in path[1:].split("/")[:-1] if p][:2]
        return "/" + "/".join(parts)
    parts = path.split("/")
    if parts[0] in ("~", "WORK", "TMP"):
        return "/".join([parts[0]] + [p for p in parts[1:-1] if p][:2])
    parts = [p for p in parts[:-1] if p][:2]
    return "/".join(parts) or "."


def area_paths(obj):
    if not isinstance(obj, dict):
        return []
    out = []
    for key in ("home", "work", "tmp", "other"):
        out.extend(p for p in (obj.get(key) or []) if isinstance(p, str))
    return out


def host_port(entry):
    return "%s:%s" % (entry.get("host"), entry.get("port"))


def summary_items(summary):
    """The items of one summary, as {kind: set of texts}."""
    s = summary or {}
    raw = {
        "programs": [p.get("path") for p in s.get("programs") or [] if isinstance(p, dict)],
        "files": [folder(p) for p in area_paths(s.get("files"))],
        "opened": [folder(p) for p in area_paths(s.get("opened"))],
        "hosts": [host_port(h) for h in s.get("hosts") or [] if isinstance(h, dict)],
        "direct": [host_port(h) for h in s.get("direct") or [] if isinstance(h, dict)],
        "dns": [n for n in s.get("dns") or [] if isinstance(n, str)],
        "processes_left": [p.get("program") for p in s.get("processes_left") or [] if isinstance(p, dict)],
    }
    return {kind: {clean(t) for t in texts if t} for kind, texts in raw.items()}


def version_key(version):
    """Sort by the runs of digits as integers, then by the text."""
    return (tuple(int(d) for d in re.findall(r"\d+", version)), version)


def word(text):
    """A word of the title: no control character and no white space."""
    return re.sub(r"\s+", "_", CONTROL_RE.sub("", str(text))) or "unknown"


def title_of(key):
    return "trace: %s %s (%s)" % key


# ------------------------------------------------------------------- DATA

def empty_data():
    return {"images": [], "items": {kind: {} for kind in KINDS}, "dropped": []}


def encode(data):
    text = json.dumps(data, sort_keys=True, separators=(",", ":"))
    return base64.b64encode(zlib.compress(text.encode("utf-8"), 9)).decode("ascii")


def decode(body):
    """The DATA of an issue body, or None."""
    found = DATA_RE.findall(body or "")
    if not found:
        return None
    try:
        # A limit on the output: a body can come from anyone who can edit it.
        inflate = zlib.decompressobj()
        raw = inflate.decompress(base64.b64decode(found[-1]), INFLATE_MAX)
        if inflate.unconsumed_tail:
            return None
        data = json.loads(raw)
    except (ValueError, zlib.error):
        return None
    if not isinstance(data, dict) or not isinstance(data.get("items"), dict):
        return None
    images = data.get("images") or []
    dropped = data.get("dropped") or []
    if not isinstance(images, list) or not isinstance(dropped, list):
        return None
    out = empty_data()
    out["images"] = sorted({str(i) for i in images})
    out["dropped"] = [k for k in KINDS if k in dropped]
    for kind in KINDS:
        if kind in out["dropped"]:
            out["items"].pop(kind, None)
            continue
        items = data["items"].get(kind) or {}
        if not isinstance(items, dict):
            return None
        for name, seen in items.items():
            if not isinstance(seen, list):
                return None
            out["items"][kind][str(name)] = sorted({str(i) for i in seen})
    return out


def fit(data):
    """Rule 3: drop kinds until DATA has DATA_MAX characters at most."""
    data = {"images": data["images"], "items": dict(data["items"]), "dropped": list(data["dropped"])}
    text = encode(data)
    for kind in DROP_ORDER:
        if len(text) <= DATA_MAX:
            break
        data["items"].pop(kind, None)
        if kind not in data["dropped"]:
            data["dropped"].append(kind)
        text = encode(data)
    return data, text


# ------------------------------------------------------------------- body

def span(item):
    return "`%s`" % item


def cell(item):
    # A pipe in a table cell must have a backslash, also in a code span.
    return span(item).replace("|", "\\|")


def table(kind, items, images, limit):
    lines = ["### %s" % kind, ""]
    if not items:
        lines.append("none")
        return lines
    lines.append("| %s | %s |" % (kind, " | ".join(i.replace("|", "\\|") for i in images)))
    lines.append("|%s" % ("---|" * (len(images) + 1)))
    names = sorted(items)
    for name in names[:limit]:
        marks = ["yes" if image in items[name] else "-" for image in images]
        lines.append("| %s | %s |" % (cell(name), " | ".join(marks)))
    if len(names) > limit:
        lines.append("")
        lines.append("%d more in the artifact" % (len(names) - limit))
    return lines


def new_rows(data, before):
    rows = []
    for kind in KINDS:
        if kind not in data["items"] or kind not in before["items"]:
            continue
        for name in sorted(data["items"][kind]):
            if name not in before["items"][kind]:
                rows.append("- %s: %s" % (kind, span(name)))
    return rows


def render(key, header, data, images, timeline, before, limit, new_limit, with_timeline):
    lines = [header, ""]
    lines.append("## items")
    lines.append("")
    for kind in KINDS:
        if kind in data["items"]:
            lines.extend(table(kind, data["items"][kind], images, limit))
        else:
            lines.extend(["### %s" % kind, "", "%s: not compared (too large)" % kind])
        lines.append("")
    if with_timeline and timeline:
        lines.append("## timeline of the permission step")
        lines.append("")
        for image in sorted(timeline):
            lines.append("### %s" % image)
            lines.append("")
            for state in timeline[image]:
                near = state.get("near") or []
                texts = ", ".join("%s %s" % (clean(n.get("kind")), span(clean(n.get("text")))) for n in near)
                lines.append("- %s at %s ms: %s" % (clean(state.get("state")), clean(state.get("t")), texts or "-"))
            lines.append("")
    if before is None:
        lines.append("## first traced version")
        lines.append("")
    else:
        version, old = before
        lines.append("## new since %s" % version)
        lines.append("")
        not_compared = [k for k in KINDS if k not in data["items"] or k not in old["items"]]
        rows = new_rows(data, old)
        lines.extend(rows[:new_limit] or ["none"])
        if len(rows) > new_limit:
            lines.append("")
            lines.append("%d more in the artifact" % (len(rows) - new_limit))
        for kind in not_compared:
            lines.append("")
            lines.append("%s: not compared (too large)" % kind)
        lines.append("")
    return "\n".join(lines)


def make_body(key, run_url, artifacts, data, timeline, before):
    data, text = fit(data)
    header = "%s · run: %s · artifacts: %s" % (title_of(key), run_url, ", ".join(artifacts) or "-")
    images = data["images"]
    body = ""
    for limit, new_limit, with_timeline in ((TABLE_ROWS, TABLE_ROWS, True), (TABLE_ROWS, TABLE_ROWS, False),
                                             (20, 20, False), (5, 5, False)):
        body = render(key, header, data, images, timeline, before, limit, new_limit, with_timeline)
        if len(body) <= BODY_MAX:
            break
    if len(body) > BODY_MAX:
        cut = body.rfind("\n", 0, BODY_MAX)
        body = body[: cut if cut > 0 else BODY_MAX] + "\n\ncut: see the artifact\n"
    return "%s\n<!-- trace-data: %s -->\n" % (body.rstrip("\n") + "\n", text), data


# ------------------------------------------------------------------- plan

def read_summaries(folder_path):
    """{key: {"data": DATA, "artifacts": [...], "timeline": {image: [...]}}}"""
    runs = {}
    for name in sorted(os.listdir(folder_path)):
        if not name.endswith(".json"):
            continue
        items = load(os.path.join(folder_path, name))
        if not isinstance(items, list):
            continue
        artifact = "trace-" + name[: -len(".json")]
        for item in items:
            if not isinstance(item, dict):
                continue
            key = (word(item.get("agent")), word(item.get("agent_version")), word(item.get("mode")))
            image = clean(item.get("runner_image") or NO_IMAGE)
            run = runs.setdefault(key, {"data": empty_data(), "artifacts": [], "timeline": {}})
            if artifact not in run["artifacts"]:
                run["artifacts"].append(artifact)
            if image not in run["data"]["images"]:
                run["data"]["images"] = sorted(run["data"]["images"] + [image])
            for kind, names in summary_items(item.get("summary")).items():
                bucket = run["data"]["items"][kind]
                for n in names:
                    bucket[n] = sorted(set(bucket.get(n, [])) | {image})
            if item.get("step") == "permission":
                timeline = (item.get("summary") or {}).get("timeline") or []
                run["timeline"][image] = [t for t in timeline if isinstance(t, dict)]
    return runs


def read_issues(path):
    """{key: issue}; an open issue wins over a closed one, then the highest number."""
    found = {}
    for issue in load(path) or []:
        m = TITLE_RE.match(str(issue.get("title", "")))
        if not m:
            continue
        key = m.groups()
        rank = (str(issue.get("state", "")).upper() == "OPEN", int(issue.get("number") or 0))
        if key not in found or rank > found[key][0]:
            found[key] = (rank, issue)
    return {key: issue for key, (_, issue) in found.items()}


def union(old, run):
    out = empty_data()
    out["images"] = sorted(set(old["images"]) | set(run["images"]))
    # A kind that the old DATA dropped stays dropped: its history is not known.
    out["dropped"] = [k for k in KINDS if k in old["dropped"]]
    for kind in KINDS:
        if kind in out["dropped"]:
            out["items"].pop(kind, None)
            continue
        merged = {}
        for src in (old, run):
            for name, images in (src["items"].get(kind) or {}).items():
                merged[name] = sorted(set(merged.get(name, [])) | set(images))
        out["items"][kind] = merged
    return out


def news(old, run):
    """The new items and images of the run that DATA of the issue does not have."""
    rows = []
    for image in run["images"]:
        if image not in old["images"]:
            rows.append("- image: %s" % span(image))
    for kind in KINDS:
        if kind not in old["items"]:
            continue
        for name in sorted(run["items"][kind]):
            images = old["items"][kind].get(name)
            if images is None:
                rows.append("- %s: %s" % (kind, span(name)))
            else:
                extra = [i for i in run["items"][kind][name] if i not in images]
                if extra:
                    rows.append("- %s: %s on %s" % (kind, span(name), ", ".join(span(i) for i in extra)))
    return rows


def plan(summaries, issues_path, run_url, out):
    runs = read_summaries(summaries)
    issues = read_issues(issues_path)
    known = {}
    for key, issue in issues.items():
        known[key] = decode(issue.get("body")) or empty_data()
    for key, run in runs.items():
        known[key] = union(known.get(key, empty_data()), run["data"]) if key in known else run["data"]

    actions = []
    for key in sorted(runs, key=lambda k: (k[0], k[2], version_key(k[1]))):
        run = runs[key]
        agent, version, mode = key
        lower = [k for k in known if k[0] == agent and k[2] == mode and version_key(k[1]) < version_key(version)]
        before = None
        if lower:
            prev = max(lower, key=lambda k: version_key(k[1]))
            before = (prev[1], fit(known[prev])[0])
        issue = issues.get(key)
        if issue is None:
            body, _ = make_body(key, run_url, run["artifacts"], run["data"], run["timeline"], before)
            actions.append({"action": "open", "title": title_of(key), "labels": ["trace", mode], "body": body})
            continue
        old = decode(issue.get("body")) or empty_data()
        rows = news(old, run["data"])
        if not rows:
            continue
        body, _ = make_body(key, run_url, run["artifacts"], union(old, run["data"]), run["timeline"], before)
        shown = rows[:TABLE_ROWS]
        if len(rows) > TABLE_ROWS:
            shown += ["", "%d more in the artifact" % (len(rows) - TABLE_ROWS)]
        comment = "New in the run %s:\n\n%s\n" % (run_url, "\n".join(shown))
        actions.append({"action": "update", "number": int(issue["number"]), "comment": comment, "body": body})
    dump(actions, out)


def main(argv):
    parser = argparse.ArgumentParser(prog="trace-issues.py")
    sub = parser.add_subparsers(dest="command", required=True)
    c = sub.add_parser("collect")
    c.add_argument("run")
    c.add_argument("--only", required=True)
    c.add_argument("--out", required=True)
    p = sub.add_parser("plan")
    p.add_argument("--summaries", required=True)
    p.add_argument("--issues", required=True)
    p.add_argument("--run-url", required=True)
    p.add_argument("--out", required=True)
    args = parser.parse_args(argv)
    if args.command == "collect":
        collect(args.run, args.only, args.out)
    else:
        plan(args.summaries, args.issues, args.run_url, args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
