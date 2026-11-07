#!/usr/bin/env python3
"""A local fake model for the "fixture" home mode of the kit.

It lets the real Codex CLI run a test session with no login, no network and
no cost. It serves the Responses API on 127.0.0.1 with fixed answers. No model
decides anything, so a fixture run measures the agent and its screens, not the
behaviour of a model.

Usage: fake-model.py --codex-home DIR --log FILE

It binds a free port, writes DIR/config.toml with that port, and serves until
the kit stops it, or for 30 minutes at most. The file LOG gets one line for
each request, with no request text.

The answer depends on the last user message:
  "Create a file"  a shell command that needs an approval, then a text reply
                   after the tool result
  "Count from"     no reply: the turn stays busy until the client ends it
  other text       a text reply

The standard library only: this file runs on each OS of the kit.
"""
import argparse
import http.server
import json
import os
import select
import threading
import time

LIFETIME_S = 1800
HOLD_S = 120
KEY_VARIABLE = "AGENT_SIGNALS_FAKE_KEY"

# No "model" line: a name that this Codex version does not know makes it swap
# the model at start, and the swap loses a prompt.
CONFIG = """model_provider = "fixture"
approval_policy = "on-request"
sandbox_mode = "workspace-write"
check_for_update_on_startup = false

[analytics]
enabled = false

[feedback]
enabled = false

[features]
apps = false
plugins = false
remote_models = false
enable_request_compression = false

[model_providers.fixture]
name = "Kit fixture"
base_url = "http://127.0.0.1:{port}/v1"
env_key = "{key}"
wire_api = "responses"
supports_websockets = false
requires_openai_auth = false
request_max_retries = 0
stream_max_retries = 0
"""


def frame(event):
    return ("event: %s\ndata: %s\n\n" % (event["type"], json.dumps(event))).encode()


def created(rid):
    return frame({"type": "response.created", "response": {"id": rid}})


def done(rid, items):
    out = b"".join(frame({"type": "response.output_item.done", "item": i}) for i in items)
    usage = {
        "input_tokens": 0,
        "output_tokens": 0,
        "total_tokens": 0,
        "input_tokens_details": None,
        "output_tokens_details": None,
    }
    return out + frame({"type": "response.completed", "response": {"id": rid, "usage": usage}})


def text_item(text):
    return {
        "type": "message",
        "role": "assistant",
        "id": "fixture-message",
        "content": [{"type": "output_text", "text": text}],
    }


def tool_item():
    args = {
        "cmd": "touch agent-signals-test.txt",
        "sandbox_permissions": "require_escalated",
        "justification": "The kit fixture asks for this write.",
    }
    return {
        "type": "function_call",
        "call_id": "fixture-call",
        "name": "exec_command",
        "arguments": json.dumps(args),
    }


def last_user_text(items):
    for item in reversed(items):
        if item.get("role") == "user":
            content = item.get("content")
            if isinstance(content, str):
                return content
            return " ".join(c.get("text", "") for c in content or [] if isinstance(c, dict))
    return ""


def answer(body):
    """Return "hold", or the output items for a request body."""
    items = body.get("input") or []
    if any(i.get("type") == "function_call_output" for i in items):
        return [text_item("The fixture finished the tool call.")]
    text = last_user_text(items)
    if "Count from" in text:
        return "hold"
    if "Create a file" in text:
        return [tool_item()]
    return [text_item("The fixture has no more to say.")]


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    count = 0
    log_file = None

    def log_message(self, *args):
        pass

    def note(self, text):
        Handler.log_file.write(text + "\n")
        Handler.log_file.flush()

    def do_GET(self):
        self.note("GET %s" % self.path)
        data = b'{"data":[],"models":[]}'
        self.send_response(200 if "models" in self.path else 404)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        size = int(self.headers.get("Content-Length") or 0)
        try:
            body = json.loads(self.rfile.read(size))
        except ValueError:
            body = {}
        Handler.count += 1
        rid = "fixture-%d" % Handler.count
        reply = answer(body)
        self.note("POST %s %s %s" % (self.path, rid, "hold" if reply == "hold" else "reply"))
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Connection", "close")
        self.end_headers()
        self.close_connection = True
        self.wfile.write(created(rid))
        self.wfile.flush()
        if reply == "hold":
            self.hold()
            return
        self.wfile.write(done(rid, reply))
        self.wfile.flush()

    def hold(self):
        # The turn stays busy until the client closes the connection.
        end = time.time() + HOLD_S
        while time.time() < end:
            if select.select([self.connection], [], [], 0.5)[0]:
                try:
                    if not self.connection.recv(1024):
                        break
                except OSError:
                    break
        self.note("hold ended")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--codex-home", required=True)
    parser.add_argument("--log", required=True)
    args = parser.parse_args()
    Handler.log_file = open(args.log, "a", encoding="utf-8")
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    server.daemon_threads = True
    timer = threading.Timer(LIFETIME_S, os._exit, [0])
    timer.daemon = True
    timer.start()
    os.makedirs(args.codex_home, exist_ok=True)
    path = os.path.join(args.codex_home, "config.toml")
    with open(path + ".new", "w", encoding="utf-8", newline="\n") as f:
        f.write(CONFIG.format(port=server.server_address[1], key=KEY_VARIABLE))
    os.replace(path + ".new", path)
    server.serve_forever()


if __name__ == "__main__":
    main()
