#!/usr/bin/env python3
"""A local fake model for the "fixture" home mode of the kit.

It lets the real Codex CLI, Claude Code and agy run a test session with no
login, no network and no cost. It serves the API of one agent on 127.0.0.1
with fixed answers. No model decides anything, so a fixture run measures the
agent and its screens, not the behaviour of a model.

Usage:
  fake-model.py --agent codex|claude|agy --home HOME --env-file FILE
                --log FILE [--pid-file FILE]
  fake-model.py --codex-home DIR --log FILE [--pid-file FILE]

It binds a free port and writes the settings files of the agent in HOME, the
throwaway home of the session. Then it writes FILE: one KEY=VALUE line for
each environment variable that the agent needs. The kit waits for FILE. It
serves until the kit stops it, or for 30 minutes at most. The file LOG gets
one line for each request, with no request text.

  codex   The Responses API. HOME/.codex/config.toml names the fake provider.
  claude  The Messages API, from ANTHROPIC_BASE_URL. HOME/.claude/.claude.json
          marks the first-start screens as done and approves the fake key.
          HOME/.claude/settings.json sets the "default" permission mode.
  agy     The Chat Completions API, from AGY_LLM_GATEWAY_URL. agy shows a
          gateway terms page on a new home. HOME/.gemini/antigravity-cli/
          cache/onboarding.json marks it as done. That page applies to a real
          gateway; this fake gateway has no account and no terms.

The old form --codex-home DIR writes DIR/config.toml and no FILE.

The answer depends on the last user message of a request with tools:
  "Create a file"  a shell command that needs an approval, then a text reply
                   after the tool result
  "Count from"     no reply: the turn stays busy until the client ends it
  other text       a text reply
A request with no tools (a title or a summary) gets a text reply.

The standard library only: this file runs on each OS of the kit.
"""
import argparse
import http.server
import json
import os
import select
import socketserver
import threading
import time

LIFETIME_S = 1800
HOLD_S = 120
KEY_VARIABLE = "AGENT_SIGNALS_FAKE_KEY"
# Claude Code shows the last 20 characters of a key in its approval list.
CLAUDE_KEY = "sk-ant-api03-agent-signals-fixture-key-0000"
AGY_MODEL = "fixture-model"
COMMAND = "touch agent-signals-test.txt"
TEXT = "The fixture has no more to say."
TOOL_DONE = "The fixture finished the tool call."

# No "model" line: a name that this Codex version does not know makes it swap
# the model at start, and the swap loses a prompt.
CODEX_CONFIG = """model_provider = "fixture"
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


def sse(event, data):
    head = "event: %s\n" % event if event else ""
    return ("%sdata: %s\n\n" % (head, json.dumps(data))).encode()


def classify(text, has_tools):
    """Return "tool", "hold" or "text" for the last user text."""
    if not has_tools:
        return "text"
    if "Count from" in text:
        return "hold"
    if "Create a file" in text:
        return "tool"
    return "text"


def text_of(content):
    if isinstance(content, str):
        return content
    out = []
    for c in content or []:
        if isinstance(c, dict) and isinstance(c.get("text"), str):
            out.append(c["text"])
    return " ".join(out)


# ---------------------------------------------------------------- codex


def codex_answer(body):
    items = body.get("input") or []
    if any(i.get("type") == "function_call_output" for i in items):
        return [codex_text(TOOL_DONE)]
    text = ""
    for item in reversed(items):
        if item.get("role") == "user":
            text = text_of(item.get("content"))
            break
    kind = classify(text, True)
    if kind == "hold":
        return "hold"
    if kind == "tool":
        args = {
            "cmd": COMMAND,
            "sandbox_permissions": "require_escalated",
            "justification": "The kit fixture asks for this write.",
        }
        return [{
            "type": "function_call",
            "call_id": "fixture-call",
            "name": "exec_command",
            "arguments": json.dumps(args),
        }]
    return [codex_text(TEXT)]


def codex_text(text):
    return {
        "type": "message",
        "role": "assistant",
        "id": "fixture-message",
        "content": [{"type": "output_text", "text": text}],
    }


def codex_stream(rid, reply):
    yield sse("response.created", {"type": "response.created", "response": {"id": rid}})
    if reply == "hold":
        return
    for item in reply:
        yield sse("response.output_item.done", {"type": "response.output_item.done", "item": item})
    usage = {
        "input_tokens": 0,
        "output_tokens": 0,
        "total_tokens": 0,
        "input_tokens_details": None,
        "output_tokens_details": None,
    }
    yield sse("response.completed", {"type": "response.completed", "response": {"id": rid, "usage": usage}})


# --------------------------------------------------------------- claude


def claude_answer(body):
    # Claude Code 2.1.318 puts a "system" message after the user message.
    last = next((m for m in reversed(body.get("messages") or [])
                 if isinstance(m, dict) and m.get("role") == "user"), {})
    content = last.get("content")
    if isinstance(content, list) and any(
            isinstance(c, dict) and c.get("type") == "tool_result" for c in content):
        return "text", TOOL_DONE
    kind = classify(text_of(content), bool(body.get("tools")))
    return kind, TEXT


def claude_blocks(kind, text):
    if kind == "tool":
        return [{
            "type": "tool_use",
            "id": "toolu_fixture",
            "name": "Bash",
            "input": {"command": COMMAND, "description": "Create the test file"},
        }], "tool_use"
    return [{"type": "text", "text": text}], "end_turn"


def claude_message(rid, model, blocks, stop):
    return {
        "id": rid,
        "type": "message",
        "role": "assistant",
        "model": model,
        "content": blocks,
        "stop_reason": stop,
        "stop_sequence": None,
        "usage": {"input_tokens": 1, "output_tokens": 1},
    }


def claude_stream(rid, model, kind, text):
    start = claude_message(rid, model, [], None)
    yield sse("message_start", {"type": "message_start", "message": start})
    if kind == "hold":
        return
    blocks, stop = claude_blocks(kind, text)
    for i, b in enumerate(blocks):
        if b["type"] == "text":
            first = {"type": "text", "text": ""}
            delta = {"type": "text_delta", "text": b["text"]}
        else:
            first = dict(b, input={})
            delta = {"type": "input_json_delta", "partial_json": json.dumps(b["input"])}
        yield sse("content_block_start", {"type": "content_block_start", "index": i, "content_block": first})
        yield sse("content_block_delta", {"type": "content_block_delta", "index": i, "delta": delta})
        yield sse("content_block_stop", {"type": "content_block_stop", "index": i})
    yield sse("message_delta", {
        "type": "message_delta",
        "delta": {"stop_reason": stop, "stop_sequence": None},
        "usage": {"output_tokens": 1},
    })
    yield sse("message_stop", {"type": "message_stop"})


# ------------------------------------------------------------------ agy


def agy_answer(body):
    last = next((m for m in reversed(body.get("messages") or [])
                 if isinstance(m, dict) and m.get("role") in ("user", "tool")), {})
    if last.get("role") == "tool":
        return "text", TOOL_DONE
    kind = classify(text_of(last.get("content")), bool(body.get("tools")))
    return kind, TEXT


def agy_delta(kind, text):
    if kind == "tool":
        args = {
            "CommandLine": COMMAND,
            "toolSummary": "Test file creation",
            "WaitMsBeforeAsync": 5000,
        }
        call = {
            "index": 0,
            "id": "call_fixture",
            "type": "function",
            "function": {"name": "run_command", "arguments": json.dumps(args)},
        }
        return {"role": "assistant", "tool_calls": [call]}, "tool_calls"
    return {"role": "assistant", "content": text}, "stop"


def agy_chunk(rid, model, delta, finish):
    return {
        "id": rid,
        "object": "chat.completion.chunk",
        "created": int(time.time()),
        "model": model,
        "choices": [{"index": 0, "delta": delta, "finish_reason": finish}],
    }


def agy_stream(rid, model, kind, text):
    if kind == "hold":
        return
    delta, finish = agy_delta(kind, text)
    yield sse(None, agy_chunk(rid, model, delta, None))
    end = agy_chunk(rid, model, {}, finish)
    end["usage"] = {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2}
    yield sse(None, end)
    yield b"data: [DONE]\n\n"


def agy_message(rid, model, kind, text):
    delta, finish = agy_delta(kind, text)
    return {
        "id": rid,
        "object": "chat.completion",
        "created": int(time.time()),
        "model": model,
        "choices": [{"index": 0, "message": delta, "finish_reason": finish}],
        "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2},
    }


# --------------------------------------------------------------- server


class Server(http.server.ThreadingHTTPServer):
    def server_bind(self):
        # HTTPServer.server_bind calls socket.getfqdn(). That lookup took
        # more than 5 s on the macOS images of CI.
        socketserver.TCPServer.server_bind(self)
        self.server_name, self.server_port = self.server_address[:2]


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    count = 0
    agent = "codex"
    log_file = None
    lock = threading.Lock()

    def log_message(self, *args):
        pass

    def note(self, text):
        with Handler.lock:
            Handler.log_file.write(text + "\n")
            Handler.log_file.flush()

    def send_json(self, code, data):
        raw = json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_HEAD(self):
        self.note("HEAD %s" % self.path)
        self.send_response(200)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self):
        self.note("GET %s" % self.path)
        if "models" not in self.path:
            self.send_json(404, {})
        elif Handler.agent == "agy":
            model = {"id": AGY_MODEL, "object": "model", "created": 0, "owned_by": "kit"}
            self.send_json(200, {"object": "list", "data": [model]})
        else:
            self.send_json(200, {"data": [], "models": []})

    def do_POST(self):
        size = int(self.headers.get("Content-Length") or 0)
        try:
            body = json.loads(self.rfile.read(size))
        except ValueError:
            body = {}
        if not isinstance(body, dict):
            body = {}
        with Handler.lock:
            Handler.count += 1
            rid = "fixture-%d" % Handler.count
        path = self.path.split("?")[0]
        if path.endswith("/count_tokens"):
            self.note("POST %s %s reply" % (path, rid))
            self.send_json(200, {"input_tokens": 1})
            return
        model = body.get("model") or AGY_MODEL
        stream = True
        if path.endswith("/responses"):
            reply = codex_answer(body)
            kind = "hold" if reply == "hold" else "reply"
            chunks = codex_stream(rid, reply)
        elif path.endswith("/messages"):
            kind, text = claude_answer(body)
            stream = bool(body.get("stream"))
            chunks = claude_stream(rid, model, kind, text)
            whole = lambda: claude_message(rid, model, *claude_blocks(kind, text))
        elif path.endswith("/chat/completions"):
            kind, text = agy_answer(body)
            stream = bool(body.get("stream"))
            chunks = agy_stream(rid, model, kind, text)
            whole = lambda: agy_message(rid, model, kind, text)
        else:
            self.note("POST %s %s unknown" % (path, rid))
            self.send_json(404, {})
            return
        self.note("POST %s %s %s" % (path, rid, kind))
        if not stream and kind != "hold":
            self.send_json(200, whole())
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()
        self.close_connection = True
        for c in chunks:
            self.wfile.write(c)
            self.wfile.flush()
        if kind == "hold":
            self.hold()

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


def write_file(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path + ".new", "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    os.replace(path + ".new", path)


def json_text(data):
    return json.dumps(data, indent=2) + "\n"


def prepare(agent, home, port):
    """Write the settings files of AGENT in HOME. Return the variables."""
    base = "http://127.0.0.1:%d" % port
    if agent == "codex":
        write_file(os.path.join(home, ".codex", "config.toml"),
                   CODEX_CONFIG.format(port=port, key=KEY_VARIABLE))
        return [(KEY_VARIABLE, "dummy"), ("CODEX_HOME", os.path.join(home, ".codex"))]
    if agent == "claude":
        conf = os.path.join(home, ".claude")
        write_file(os.path.join(conf, ".claude.json"), json_text({
            "hasCompletedOnboarding": True,
            "theme": "dark",
            "hasSeenAutoDefaultNotice": True,
            "hasSeenAutoDefaultNudge": True,
            "customApiKeyResponses": {"approved": [CLAUDE_KEY[-20:]], "rejected": []},
        }))
        write_file(os.path.join(conf, "settings.json"),
                   json_text({"permissions": {"defaultMode": "default"}}))
        return [
            ("CLAUDE_CONFIG_DIR", conf),
            ("ANTHROPIC_BASE_URL", base),
            ("ANTHROPIC_API_KEY", CLAUDE_KEY),
            ("CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC", "1"),
            ("DISABLE_AUTOUPDATER", "1"),
        ]
    write_file(os.path.join(home, ".gemini", "antigravity-cli", "cache", "onboarding.json"),
               json_text({
                   "consumerOnboardingComplete": False,
                   "enterpriseOnboardingComplete": True,
                   "onboardingComplete": False,
               }))
    return [
        ("AGY_LLM_GATEWAY_URL", base + "/v1"),
        ("AGY_LLM_GATEWAY_API_KEY", "dummy"),
        ("AGY_LLM_GATEWAY_WIRE_PROTOCOL", "openai"),
        ("AGY_CLI_DISABLE_AUTO_UPDATE", "1"),
    ]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--agent", choices=["codex", "claude", "agy"])
    parser.add_argument("--home")
    parser.add_argument("--env-file")
    parser.add_argument("--codex-home")
    parser.add_argument("--log", required=True)
    parser.add_argument("--pid-file")
    args = parser.parse_args()
    if args.codex_home:
        args.agent = "codex"
    elif not (args.agent and args.home and args.env_file):
        parser.error("give --agent, --home and --env-file, or --codex-home")
    Handler.agent = args.agent
    Handler.log_file = open(args.log, "a", encoding="utf-8")
    server = Server(("127.0.0.1", 0), Handler)
    server.daemon_threads = True
    timer = threading.Timer(LIFETIME_S, os._exit, [0])
    timer.daemon = True
    timer.start()
    if args.pid_file:
        # A Python of a venv on Windows is a launcher with this process as a
        # child. The kit must record this pid too.
        with open(args.pid_file, "w", encoding="utf-8") as f:
            f.write(str(os.getpid()))
    port = server.server_address[1]
    if args.codex_home:
        write_file(os.path.join(args.codex_home, "config.toml"),
                   CODEX_CONFIG.format(port=port, key=KEY_VARIABLE))
    else:
        env = prepare(args.agent, args.home, port)
        write_file(args.env_file, "".join("%s=%s\n" % kv for kv in env))
    server.serve_forever()


if __name__ == "__main__":
    main()
