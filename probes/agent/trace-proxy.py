"""A recording proxy for a traced session (the network check).

Run: python3 -I trace-proxy.py --log FILE --port-file FILE

The proxy listens on 127.0.0.1 and a free port. It writes the port to the
port file when it is ready to take connections. It takes "CONNECT host:port"
and a plain HTTP request with an absolute URI. It forwards the bytes to the
host and does not read the encrypted content.

For each connection the proxy appends one JSON line to the log:
{"start": MS, "end": MS, "host": H, "port": P, "up": N, "down": N,
"status": S, "method": M}. MS is the time in epoch milliseconds. "up" is the
number of bytes sent to the host. "down" is the number of bytes sent to the
client. "status" is "ok", "refused", "error" or "open". "method" is
"CONNECT" or the method of the plain request. The log has no path, no
query, no header and no body.

A plain request goes to the host in origin-form: the request line holds the
path only. The proxy drops the Connection, Keep-Alive, Proxy-Connection
and Proxy-Authorization headers of the client and adds "Connection: close".
Each plain connection carries one request. The proxy sends the head and the
body to the host (the length is the Content-Length). Then it sends no more
client bytes. When the host ends its response, the proxy closes both sides,
so a client that keeps its connection must open a new one for the next
request. Limit: with "Transfer-Encoding: chunked", or with no length on
POST, PUT or PATCH, the proxy cannot find the end of the body, and it sends
client bytes until the host ends. A host that ignores "Connection: close"
keeps the connection open until the client or the host ends it. A plain
request with a bad head gets "400" and no log line. A bad head has a
folded header line, white space before a colon, a Content-Length that is
not all digits, or two Content-Length headers with different values. A
host that refuses or fails gives "502" to the client. On SIGTERM the proxy writes each open connection with
the status "open" and "end" set to the time of the signal, and exits 0.
Each connection has its own thread. The standard library only.
"""

import argparse
import json
import os
import signal
import socket
import sys
import threading
import time
from urllib.parse import urlsplit

HEAD_LIMIT = 65536
CONNECT_TIMEOUT = 10
BUF = 65536
DROP_HEADERS = (
    b"connection:",
    b"keep-alive:",
    b"proxy-connection:",
    b"proxy-authorization:",
)
BODY_METHODS = ("POST", "PUT", "PATCH")

_lock = threading.RLock()
_open = {}
_next_id = [0]
_log_fd = [-1]


def now_ms():
    return time.time_ns() // 1000000


def write_line(rec, status, end):
    """Write one log line with one write, under the lock."""
    line = (
        '{"start": %d, "end": %d, "host": %s, "port": %d, "up": %d, '
        '"down": %d, "status": "%s", "method": %s}\n'
        % (
            rec["start"],
            end,
            json_str(rec["host"]),
            rec["port"],
            rec["up"],
            rec["down"],
            status,
            json_str(rec["method"]),
        )
    )
    data = line.encode("ascii")
    with _lock:
        os.write(_log_fd[0], data)


def json_str(text):
    return json.dumps(text)


def finish(cid, rec, status):
    """Remove the connection from the open list and log it, once."""
    with _lock:
        if _open.pop(cid, None) is None:
            return
        write_line(rec, status, now_ms())


def send_502(client):
    """Send 502 to the client. A failed send changes nothing else."""
    try:
        client.sendall(b"HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n")
    except OSError:
        pass


def read_head(sock):
    """Read up to the end of the request head. Return (head, rest)."""
    data = b""
    while b"\r\n\r\n" not in data:
        if len(data) > HEAD_LIMIT:
            return None, b""
        chunk = sock.recv(BUF)
        if not chunk:
            return None, b""
        data += chunk
    head, _, rest = data.partition(b"\r\n\r\n")
    return head, rest


def split_hostport(text, default_port):
    """Return (host, port) from "host:port", "host" or "[v6]:port"."""
    if text.startswith("["):
        host, sep, tail = text[1:].partition("]")
        if not sep or (tail and not tail.startswith(":")):
            raise ValueError("bad bracket form")
        port = tail[1:]
    elif text.count(":") <= 1:
        host, _, port = text.partition(":")
        if ":" in text and not port:
            raise ValueError("empty port")
    else:
        raise ValueError("colons with no brackets")
    if not host or any(c in host for c in "@/?#\\ \t"):
        raise ValueError("bad host")
    if port and not (port.isascii() and port.isdigit() and 0 < int(port) < 65536):
        raise ValueError("bad port")
    return host, int(port) if port else default_port


def parse_headers(block):
    """Return (kept, length, chunked) for the header lines of a plain
    request. Raise ValueError for a bad head. kept has no connection
    header."""
    kept = []
    length = None
    chunked = False
    for h in block.split(b"\r\n"):
        if not h:
            continue
        if h[:1] in (b" ", b"\t"):
            raise ValueError("folded header line")
        name, sep, value = h.partition(b":")
        if not sep or not name or name != name.strip():
            raise ValueError("bad header name")
        low = name.lower()
        if (low + b":") in DROP_HEADERS:
            continue
        if low == b"content-length":
            v = value.strip()
            if not (v.isascii() and v.isdigit()):
                raise ValueError("bad Content-Length")
            if length is not None and length != int(v):
                raise ValueError("two Content-Length values")
            length = int(v)
        elif low == b"transfer-encoding" and b"chunked" in value.lower():
            chunked = True
        kept.append(h)
    return kept, length, chunked


def close_both(a, b):
    """Shut down both sockets, so that a pump that waits in recv wakes."""
    for s in (a, b):
        try:
            s.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass


def pump(src, dst, counter, rec, limit=None, ended=None):
    """Copy bytes from src to dst until src ends. Count them in rec.
    With a limit, copy at most that many bytes and then return True, with
    no shutdown. With "ended" (an Event), a normal end of src closes both
    sides and sets the event. On a failure, close both sides and return
    False."""
    try:
        while limit is None or limit > 0:
            chunk = src.recv(BUF if limit is None else min(BUF, limit))
            if not chunk:
                break
            dst.sendall(chunk)
            if limit is not None:
                limit -= len(chunk)
            with _lock:
                rec[counter] += len(chunk)
        else:
            return True
    except OSError:
        close_both(src, dst)
        return False
    if ended is not None:
        ended.set()
        close_both(src, dst)
        return True
    try:
        dst.shutdown(socket.SHUT_WR)
    except OSError:
        pass
    return True


def relay(client, upstream, rec, limit=None, plain=False):
    """Copy both ways until both sides end. Return True when no error.
    With plain, the client side sends at most "limit" more bytes, and the
    end of the host closes both sides."""
    result = []
    ended = threading.Event() if plain else None
    t = threading.Thread(
        target=lambda: result.append(
            pump(upstream, client, "down", rec, ended=ended)
        ),
        daemon=True,
    )
    t.start()
    ok = pump(client, upstream, "up", rec, limit if plain else None)
    t.join()
    if not ok and ended is not None and ended.is_set():
        # The client side failed because the host ended first.
        ok = True
    return ok and all(result)


def handle(client, rec_id):
    rec = {
        "start": now_ms(),
        "host": "-",
        "port": 0,
        "up": 0,
        "down": 0,
        "method": "-",
    }
    upstream = None
    registered = False
    try:
        client.settimeout(30)
        head, rest = read_head(client)
        if head is None:
            return
        client.settimeout(None)
        first, _, other = head.partition(b"\r\n")
        parts = first.decode("latin-1").split(" ")
        if len(parts) != 3:
            client.sendall(b"HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\n\r\n")
            return
        method, target, version = parts
        plain = method != "CONNECT"
        try:
            if plain:
                url = urlsplit(target)
                if url.scheme.lower() != "http" or not url.hostname:
                    raise ValueError("not an absolute http URI")
                host, port = url.hostname, url.port or 80
                origin = url.path or "/"
                if url.query:
                    origin += "?" + url.query
                kept, length, chunked = parse_headers(other)
            else:
                host, port = split_hostport(target, 443)
        except ValueError:
            client.sendall(b"HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\n\r\n")
            return
        rec["host"], rec["port"], rec["method"] = host, port, method
        with _lock:
            _open[rec_id] = rec
            registered = True
        try:
            upstream = socket.create_connection((host, port), CONNECT_TIMEOUT)
            upstream.settimeout(None)
        except ConnectionRefusedError:
            send_502(client)
            finish(rec_id, rec, "refused")
            return
        except (OSError, ValueError, OverflowError):
            send_502(client)
            finish(rec_id, rec, "error")
            return
        if plain:
            # One request on each connection: drop the connection headers
            # and say "Connection: close".
            kept.append(b"Connection: close")
            if chunked or (length is None and method in BODY_METHODS):
                limit = None
            else:
                limit = length or 0
            if limit is not None:
                rest = rest[:limit]
                limit -= len(rest)
            line = ("%s %s %s" % (method, origin, version)).encode("latin-1")
            first_out = b"\r\n".join([line] + kept) + b"\r\n\r\n" + rest
            upstream.sendall(first_out)
            with _lock:
                rec["up"] += len(first_out)
        else:
            client.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
            if rest:
                upstream.sendall(rest)
                with _lock:
                    rec["up"] += len(rest)
        ok = relay(client, upstream, rec, limit if plain else None, plain)
        finish(rec_id, rec, "ok" if ok else "error")
    except OSError:
        if registered:
            finish(rec_id, rec, "error")
    finally:
        for s in (upstream, client):
            if s is not None:
                try:
                    s.close()
                except OSError:
                    pass


def on_term(signum, frame):
    """Log the open connections with the status "open" and exit 0."""
    try:
        end = now_ms()
        with _lock:
            for rec in list(_open.values()):
                write_line(rec, "open", end)
            _open.clear()
    finally:
        os._exit(0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--log", required=True)
    ap.add_argument("--port-file", required=True)
    args = ap.parse_args()
    _log_fd[0] = os.open(args.log, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", 0))
    srv.listen(128)
    signal.signal(signal.SIGTERM, on_term)
    tmp = args.port_file + ".tmp"
    with open(tmp, "w", encoding="ascii") as f:
        f.write("%d\n" % srv.getsockname()[1])
    os.replace(tmp, args.port_file)
    while True:
        try:
            client, _ = srv.accept()
        except InterruptedError:
            continue
        _next_id[0] += 1
        threading.Thread(
            target=handle, args=(client, _next_id[0]), daemon=True
        ).start()


if __name__ == "__main__":
    sys.exit(main())
