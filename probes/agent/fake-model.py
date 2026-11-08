#!/usr/bin/env python3
"""A local fake model for the "fixture" home mode of the kit.

It lets the real Codex CLI, Claude Code, agy and the Cursor CLI run a test
session with no login, no network and no cost. It serves the API of one agent on 127.0.0.1
with fixed answers. No model decides anything, so a fixture run measures the
agent and its screens, not the behaviour of a model.

Usage:
  fake-model.py --agent codex|claude|agy|cursor-agent --home HOME --env-file FILE
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
  cursor-agent
          The Connect RPC API of the Cursor CLI, from CURSOR_API_ENDPOINT. It
          is not a public API: the field numbers come from the client of
          2026.11.05-86047df, and a new client can change them.
          HOME/.cursor/cli-config.json selects HTTP/1.1 for the agent
          stream. The log names each RPC.

The old form --codex-home DIR writes DIR/config.toml and no FILE.

The answer depends on the last user message of a request with tools:
  "Create a file"  a shell command that needs an approval, then a text reply
                   after the tool result
  "Write a file"   one call of the file-write tool of the agent for the file
                   agent-signals-write.txt in the work folder, then a text
                   reply after the tool result. Claude Code: Write. Codex:
                   apply_patch. agy: write_file. Claude Code and agy need an
                   absolute path: the server reads the work folder from the
                   system prompt. cursor-agent: a text reply.
  "Write outside"  the same call for the absolute path that follows this text,
                   for example "Write outside /work/x.txt". With no absolute
                   path: a text reply that says so.
  "Count from"     no reply: the turn stays busy until the client ends it
  "Let me choose"  Claude Code: an AskUserQuestion call with the options "Red"
                   and "Blue", then a text reply after the answer. The other
                   agents: the reply of the next line.
  "End your reply with a question"
                   a text reply that ends with a question
  other text       a text reply
The Go package github.com/xSAVIKx/agent-signals/go/fakemodel gives the same
answers.
A request with no tools (a title or a summary) gets a text reply.

The standard library only: this file runs on each OS of the kit.
"""
import argparse
import base64
import gzip
import http.server
import json
import os
import re
import queue
import select
import struct
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
QUESTION = "The fixture has one question. Do you want to go on?"
WRITE_FILE = "agent-signals-write.txt"
WRITE_TEXT = "The fixture wrote this file.\n"
NO_PATH = 'The fixture found no absolute path after "Write outside".'
ABS_PATH = re.compile(r"""(?:[A-Za-z]:\\|/)[^\s"'<>]+""")
CLAUDE_CHOICE = {
    "questions": [{
        "question": "Which color do you like?",
        "header": "Color",
        "options": [
            {"label": "Red", "description": "The color red."},
            {"label": "Blue", "description": "The color blue."},
        ],
        "multiSelect": False,
    }],
}

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
    """Return "tool", "hold", "choice", "question" or "text" for the last
    user text."""
    if not has_tools:
        return "text"
    if "Count from" in text:
        return "hold"
    if "Create a file" in text:
        return "tool"
    if "Write a file" in text or "Write outside" in text:
        return "write"
    if "Let me choose" in text:
        return "choice"
    if "End your reply with a question" in text:
        return "question"
    return "text"


def write_path(text, cwd):
    """Return the path of a write call for the user TEXT, or "" when "Write
    outside" has no absolute path after it. CWD is the work folder, or "" for
    a relative path."""
    i = text.find("Write outside")
    if i >= 0:
        m = ABS_PATH.search(text, i + len("Write outside"))
        return m.group(0).rstrip(".,;:)") if m else ""
    if not cwd:
        return WRITE_FILE
    if "\\" in cwd and "/" not in cwd:
        return cwd.rstrip("\\") + "\\" + WRITE_FILE
    return cwd.rstrip("/") + "/" + WRITE_FILE


def label_value(text, label):
    """Return the rest of the line after LABEL in TEXT, or ""."""
    i = text.find(label)
    if i < 0:
        return ""
    return text[i + len(label):].split("\n", 1)[0].strip()


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
    items = [i for i in body.get("input") or [] if isinstance(i, dict)]
    # Only the items after the last user message count: a tool result of an
    # earlier turn must not end a new turn.
    last = max([n for n, i in enumerate(items) if i.get("role") == "user"] or [-1])
    if any(i.get("type") in ("function_call_output", "custom_tool_call_output")
           for i in items[last + 1:]):
        return [codex_text(TOOL_DONE)]
    text = text_of(items[last].get("content")) if last >= 0 else ""
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
    if kind == "write":
        path = write_path(text, "")
        if not path:
            return [codex_text(NO_PATH)]
        patch = "*** Begin Patch\n*** Add File: %s\n+%s\n*** End Patch\n" % (path, WRITE_TEXT.rstrip("\n"))
        return [{
            "type": "custom_tool_call",
            "call_id": "fixture-write",
            "name": "apply_patch",
            "input": patch,
        }]
    if kind in ("choice", "question"):
        return [codex_text(QUESTION)]
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
    # For "write" the text is the path.
    # Claude Code 2.1.318 puts a "system" message after the user message.
    last = next((m for m in reversed(body.get("messages") or [])
                 if isinstance(m, dict) and m.get("role") == "user"), {})
    content = last.get("content")
    if isinstance(content, list) and any(
            isinstance(c, dict) and c.get("type") == "tool_result" for c in content):
        return "text", TOOL_DONE
    text = text_of(content)
    kind = classify(text, bool(body.get("tools")))
    if kind == "write":
        path = write_path(text, label_value(text_of(body.get("system")), "Primary working directory: "))
        return ("write", path) if path else ("text", NO_PATH)
    names = [t.get("name") for t in body.get("tools") or [] if isinstance(t, dict)]
    if kind == "choice" and "AskUserQuestion" not in names:
        return "question", QUESTION
    if kind == "question":
        return kind, QUESTION
    return kind, TEXT


def claude_blocks(kind, text):
    if kind == "tool":
        return [{
            "type": "tool_use",
            "id": "toolu_fixture",
            "name": "Bash",
            "input": {"command": COMMAND, "description": "Create the test file"},
        }], "tool_use"
    if kind == "write":
        return [{
            "type": "tool_use",
            "id": "toolu_fixture_write",
            "name": "Write",
            "input": {"file_path": text, "content": WRITE_TEXT},
        }], "tool_use"
    if kind == "choice":
        return [{
            "type": "tool_use",
            "id": "toolu_fixture_choice",
            "name": "AskUserQuestion",
            "input": CLAUDE_CHOICE,
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
    # For "write" the text is the path.
    msgs = [m for m in body.get("messages") or [] if isinstance(m, dict)]
    last = next((m for m in reversed(msgs)
                 if isinstance(m, dict) and m.get("role") in ("user", "tool")), {})
    if last.get("role") == "tool":
        return "text", TOOL_DONE
    text = text_of(last.get("content"))
    kind = classify(text, bool(body.get("tools")))
    if kind == "write":
        cwd = next((v for v in (label_value(text_of(m.get("content")), "Command Working Directory: ")
                                for m in msgs) if v), "")
        path = write_path(text, cwd)
        return ("write", path) if path else ("text", NO_PATH)
    if kind in ("choice", "question"):
        return "question", QUESTION
    return kind, TEXT


def agy_delta(kind, text):
    if kind == "write":
        call = {
            "index": 0,
            "id": "call_fixture_write",
            "type": "function",
            "function": {"name": "write_file", "arguments": json.dumps({"Path": text, "Content": WRITE_TEXT})},
        }
        return {"role": "assistant", "tool_calls": [call]}, "tool_calls"
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



# --------------------------------------------------------------- cursor
# A small protobuf writer and reader. A message is a list of (field, value):
# an int is a varint, bytes or str is a length-delimited field.


def varint(n):
    out = b""
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out += bytes([b | 0x80])
        else:
            return out + bytes([b])


def pb(*fields):
    out = b""
    for no, v in fields:
        if isinstance(v, int):
            out += varint(no << 3) + varint(v)
        else:
            if isinstance(v, str):
                v = v.encode()
            out += varint(no << 3 | 2) + varint(len(v)) + v
    return out


def read_varint(b, i):
    n = shift = 0
    while True:
        c = b[i]
        i += 1
        n |= (c & 0x7F) << shift
        shift += 7
        if c < 0x80:
            return n, i


def pb_fields(b):
    out = []
    i = 0
    while i < len(b):
        key, i = read_varint(b, i)
        no, wire = key >> 3, key & 7
        if wire == 0:
            v, i = read_varint(b, i)
        elif wire == 2:
            n, i = read_varint(b, i)
            v = b[i:i + n]
            i += n
        elif wire == 1:
            v, i = b[i:i + 8], i + 8
        elif wire == 5:
            v, i = b[i:i + 4], i + 4
        else:
            raise ValueError("wire type %d" % wire)
        out.append((no, v))
    return out


def pb_get(b, *path):
    """The bytes at the field path, or None."""
    for no in path:
        if not isinstance(b, bytes):
            return None
        try:
            found = [v for n, v in pb_fields(b) if n == no]
        except (ValueError, IndexError):
            return None
        b = found[0] if found else None
    return b if isinstance(b, bytes) else None


def b64(data):
    return base64.urlsafe_b64encode(json.dumps(data).encode()).rstrip(b"=").decode()


def fake_jwt():
    now = int(time.time())
    return "%s.%s.c2ln" % (b64({"alg": "HS256", "typ": "JWT"}),
                           b64({"sub": "auth0|fixture", "iat": now, "exp": now + 86400}))


CURSOR_MODEL = pb((1, "fixture"), (3, "fixture"), (4, "Fixture"), (5, "Fixture"))
CURSOR_REPLY = {
    "aiserver.v1.AiService/GetUsableModels": pb((1, CURSOR_MODEL)),
    "aiserver.v1.AiService/GetDefaultModelForCli": pb((1, CURSOR_MODEL)),
}
# AgentServerMessage: 1 interaction_update {1 text_delta {1 text}, 13
# heartbeat, 14 turn_ended}, 2 exec_server_message.
CURSOR_HEARTBEAT = pb((1, pb((13, b""))))
CURSOR_TURN_ENDED = pb((1, pb((14, b""))))
# 3 conversation_checkpoint_update: the client keeps the chat only after it.
CURSOR_CHECKPOINT = pb((3, b""))


def cursor_text(text):
    return pb((1, pb((1, pb((1, text))))))


def cursor_shell(cwd):
    """An exec_server_message with the shell command: the client shows the
    "Run this command?" dialog. Field 8, the parsed command, is required."""
    arg = pb((1, "word"), (2, "agent-signals-test.txt"))
    parsed = pb((2, pb((1, "touch"), (2, arg), (3, COMMAND))))
    shell = pb((1, COMMAND), (2, cwd), (3, 30000), (4, "fixture-call"), (5, "touch"), (8, parsed))
    return pb((2, pb((1, 1), (15, "fixture-exec"), (2, shell))))


def envelope(payload, flags=0):
    return bytes([flags]) + struct.pack(">I", len(payload)) + payload


def unenvelope(b):
    out = []
    i = 0
    while i + 5 <= len(b):
        flags = b[i]
        n = struct.unpack(">I", b[i + 1:i + 5])[0]
        p = b[i + 5:i + 5 + n]
        i += 5 + n
        if flags & 1:
            p = gzip.decompress(p)
        out.append(p)
    return out


# The client messages of each agent run: BidiAppend puts them, RunSSE reads.
CURSOR_QUEUES = {}
# The newest RunSSE stream of each run. The client can open a second stream
# for a run (fact 78), and the old stream must then stop taking messages.
CURSOR_STREAMS = {}
CURSOR_LOCK = threading.Lock()


class StaleStream(Exception):
    """A newer RunSSE stream has the run."""


def cursor_queue(rid):
    with CURSOR_LOCK:
        return CURSOR_QUEUES.setdefault(rid, queue.Queue())

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

    def read_body(self):
        if self.headers.get("Transfer-Encoding") == "chunked":
            out = b""
            while True:
                n = int(self.rfile.readline().split(b";")[0].strip() or b"0", 16)
                if n == 0:
                    self.rfile.readline()
                    break
                out += self.rfile.read(n)
                self.rfile.readline()
        else:
            out = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        if self.headers.get("Content-Encoding") == "gzip":
            out = gzip.decompress(out)
        return out

    def do_POST(self):
        if Handler.agent == "cursor-agent":
            self.cursor_post()
            return
        try:
            body = json.loads(self.read_body())
        except (ValueError, OSError, EOFError):
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

    def send_raw(self, ctype, data):
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def cursor_post(self):
        rpc = self.path.split("?")[0].lstrip("/")
        body = self.read_body()
        ctype = self.headers.get("Content-Type") or "application/proto"
        if rpc == "auth/exchange_user_api_key":
            self.note("POST %s reply" % rpc)
            self.send_json(200, {"accessToken": fake_jwt(), "refreshToken": fake_jwt()})
        elif rpc == "aiserver.v1.BidiService/BidiAppend":
            rid = (pb_get(body, 2, 1) or b"").decode(errors="replace")
            # The client message is in field 4 (bytes) or in field 1 (hex).
            data = pb_get(body, 4)
            if not data:
                try:
                    data = bytes.fromhex((pb_get(body, 1) or b"").decode())
                except ValueError:
                    data = b""
            cursor_queue(rid).put(data)
            self.note("POST %s append" % rpc)
            self.send_raw("application/proto", b"")
        elif rpc == "agent.v1.AgentService/RunSSE":
            self.cursor_run(rpc, body)
        else:
            self.note("POST %s %s" % (rpc, "reply" if rpc in CURSOR_REPLY else "empty"))
            empty = b"{}" if "json" in ctype else b""
            self.send_raw(ctype, CURSOR_REPLY.get(rpc, empty))

    def cursor_run(self, rpc, body):
        msgs = unenvelope(body)
        rid = ((pb_get(msgs[0], 1) if msgs else None) or b"").decode(errors="replace")
        self.send_response(200)
        self.send_header("Content-Type", "application/connect+proto")
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()

        def send(payload, flags=0):
            e = envelope(payload, flags)
            self.wfile.write(b"%x\r\n" % len(e) + e + b"\r\n")
            self.wfile.flush()

        self.note("POST %s start" % rpc)
        q = cursor_queue(rid)
        with CURSOR_LOCK:
            stream = CURSOR_STREAMS.get(rid, 0) + 1
            CURSOR_STREAMS[rid] = stream

        def take(timeout):
            """The next client message, or None after TIMEOUT seconds."""
            try:
                data = q.get(timeout=timeout)
            except queue.Empty:
                data = None
            with CURSOR_LOCK:
                current = CURSOR_STREAMS.get(rid) == stream
            if not current:
                if data is not None:
                    q.put(data)
                raise StaleStream()
            return data

        try:
            while True:
                data = take(HOLD_S)
                if data is None:
                    break
                # AgentClientMessage: 1 run_request, 2 action, 1
                # user_message_action, 1 user_message, 1 text.
                text = pb_get(data, 1, 2, 1, 1, 1)
                if text is None:
                    continue
                kind = classify(text.decode(errors="replace"), True)
                self.note("POST %s %s" % (rpc, kind))
                if kind == "hold":
                    self.cursor_hold(take, send)
                elif kind == "tool":
                    cwd = (pb_get(data, 1, 2, 1, 2, 4, 2) or b"").decode(errors="replace")
                    send(cursor_shell(cwd))
                    self.cursor_wait(take, send)
                    send(cursor_text(TOOL_DONE))
                elif kind in ("choice", "question"):
                    send(cursor_text(QUESTION))
                else:
                    send(cursor_text(TEXT))
                send(CURSOR_CHECKPOINT)
                send(CURSOR_TURN_ENDED)
                break
            send(b"{}", 2)
            self.wfile.write(b"0\r\n\r\n")
            self.wfile.flush()
        except StaleStream:
            self.note("POST %s replaced" % rpc)
        except OSError:
            self.note("POST %s closed" % rpc)
        except Exception as e:  # A bad message must not leave the stream open.
            self.note("POST %s error %s" % (rpc, type(e).__name__))
            try:
                send(CURSOR_TURN_ENDED)
                send(b"{}", 2)
                self.wfile.write(b"0\r\n\r\n")
                self.wfile.flush()
            except OSError:
                pass
        self.close_connection = True

    def cursor_hold(self, take, send):
        # The turn stays busy: a heartbeat every 2 s, until a client message
        # with field 4 (a stop) or HOLD_S.
        end = time.time() + HOLD_S
        while time.time() < end:
            data = take(2)
            if data is None:
                send(CURSOR_HEARTBEAT)
                continue
            if pb_get(data, 4) is not None:
                break
        self.note("hold ended")

    def cursor_wait(self, take, send):
        # Wait for the result of the shell command or a stop. The
        # heartbeats keep the stream open while the dialog shows.
        end = time.time() + HOLD_S
        while time.time() < end:
            data = take(2)
            if data is None:
                send(CURSOR_HEARTBEAT)
                continue
            try:
                fields = ",".join(str(n) for n, _ in pb_fields(data))
            except (ValueError, IndexError):
                fields = "bad"
            self.note("POST agent.v1.AgentService/RunSSE client %s" % fields)
            if pb_get(data, 2) is not None or pb_get(data, 4) is not None:
                return

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
    if agent == "cursor-agent":
        # Without HTTP/1.1 the agent stream needs HTTP/2, and the client
        # shows "Reconnecting".
        write_file(os.path.join(home, ".cursor", "cli-config.json"),
                   json_text({"version": 1, "network": {"useHttp1ForAgent": True}}))
        return [("CURSOR_API_ENDPOINT", base), ("CURSOR_API_KEY", "dummy")]
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
    # "cursor" and "agent" are other names of cursor-agent.
    parser.add_argument("--agent", choices=["codex", "claude", "agy", "cursor-agent", "cursor", "agent"])
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
    if args.agent in ("cursor", "agent"):
        args.agent = "cursor-agent"
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
