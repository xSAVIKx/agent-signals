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
path only, and the proxy adds no header. A host that refuses or fails gives
"502" to the client. On SIGTERM the proxy writes each open connection with
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
        host, _, tail = text[1:].partition("]")
        port = tail[1:] if tail.startswith(":") else ""
    elif text.count(":") == 1:
        host, _, port = text.partition(":")
    else:
        host, port = text, ""
    if not host:
        raise ValueError("no host")
    return host, int(port) if port else default_port


def pump(src, dst, counter, rec):
    """Copy bytes from src to dst until src ends. Count them in rec."""
    try:
        while True:
            chunk = src.recv(BUF)
            if not chunk:
                break
            dst.sendall(chunk)
            with _lock:
                rec[counter] += len(chunk)
    except OSError:
        return False
    try:
        dst.shutdown(socket.SHUT_WR)
    except OSError:
        pass
    return True


def relay(client, upstream, rec):
    """Copy both ways until both sides end. Return True when no error."""
    result = []
    t = threading.Thread(
        target=lambda: result.append(pump(upstream, client, "down", rec)),
        daemon=True,
    )
    t.start()
    ok = pump(client, upstream, "up", rec)
    if not ok:
        # Wake the other direction.
        for s in (client, upstream):
            try:
                s.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
    t.join()
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
            client.sendall(b"HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n")
            finish(rec_id, rec, "refused")
            return
        except (OSError, ValueError, OverflowError):
            client.sendall(b"HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n")
            finish(rec_id, rec, "error")
            return
        if plain:
            line = ("%s %s %s" % (method, origin, version)).encode("latin-1")
            first_out = line + (b"\r\n" + other if other else b"") + b"\r\n\r\n" + rest
            upstream.sendall(first_out)
            rec["up"] += len(first_out)
        else:
            client.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
            if rest:
                upstream.sendall(rest)
                rec["up"] += len(rest)
        ok = relay(client, upstream, rec)
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
    end = now_ms()
    with _lock:
        for rec in list(_open.values()):
            write_line(rec, "open", end)
        _open.clear()
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
