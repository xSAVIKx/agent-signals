# shellcheck shell=sh
# The network check: trace-proxy.py and the proxy variables in
# "kit session start".
. "$ROOT/tools/agent-kit-tests/lib.sh"
. "$ROOT/tools/agent-kit-tests/core-lib.sh"
. "$ROOT/tools/agent-kit-tests/steps-lib.sh"

proxy=$ROOT/probes/agent/trace-proxy.py
stub=$ROOT/tools/testdata/agent-kit/stub-agent.sh
H=$T/helpers
mkdir "$H"

# wait_file FILE: wait up to 10 s for FILE.
wait_file() {
  _n=0
  while [ ! -s "$1" ] && [ "$_n" -lt 200 ]; do
    sleep 0.05
    _n=$((_n + 1))
  done
  [ -s "$1" ]
}

# The server: "echo" sends back what it gets. "http" keeps the head of
# the request in a file and answers with a short body.
cat >"$H/server.py" <<'PYEOF'
import socket, struct, sys, threading
mode, portfile, headfile = sys.argv[1], sys.argv[2], sys.argv[3]
srv = socket.socket()
srv.bind(("127.0.0.1", 0))
srv.listen(8)
open(portfile, "w").write("%d\n" % srv.getsockname()[1])

def serve(c):
    if mode == "reset":
        c.recv(4096)
        # SO_LINGER 0: close sends a reset.
        c.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("ii", 1, 0))
        c.close()
        return
    if mode == "keep":
        # An HTTP/1.1 origin: it keeps the head of each request in a file,
        # answers with Content-Length, and closes on "Connection: close".
        buf = b""
        while True:
            while b"\r\n\r\n" not in buf:
                x = c.recv(4096)
                if not x:
                    c.close()
                    return
                buf += x
            head, _, buf = buf.partition(b"\r\n\r\n")
            open(headfile, "ab").write(head + b"\r\n\r\n")
            c.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok")
            if b"connection: close" in head.lower():
                c.close()
                return
    if mode == "echo":
        while True:
            d = c.recv(4096)
            if not d:
                break
            c.sendall(d)
    else:
        d = b""
        while b"\r\n\r\n" not in d:
            x = c.recv(4096)
            if not x:
                break
            d += x
        open(headfile, "wb").write(d)
        c.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok")
    c.close()

while True:
    c, _ = srv.accept()
    threading.Thread(target=serve, args=(c,), daemon=True).start()
PYEOF

# The client: "tunnel" does CONNECT, sends 5 bytes and reads 5. "hold"
# does the same, then waits (the test stops it). "get" sends a plain GET.
cat >"$H/client.py" <<'PYEOF'
import socket, sys, time
mode, pport = sys.argv[1], int(sys.argv[2])
tport = int(sys.argv[3]) if mode not in ("bad", "ka") else 0
c = socket.create_connection(("127.0.0.1", pport))
if mode == "ka":
    # Two requests in one write, each for its own origin port, both with
    # keep-alive. Read until the proxy closes the connection.
    reqs = b""
    for p in sys.argv[3:]:
        reqs += (b"GET http://127.0.0.1:%s/one HTTP/1.1\r\nHost: 127.0.0.1:%s\r\nConnection: keep-alive\r\nProxy-Connection: keep-alive\r\nKeep-Alive: 5\r\n\r\n" % (p.encode(), p.encode()))
    c.sendall(reqs)
    c.settimeout(10)
    r = b""
    while True:
        x = c.recv(4096)
        if not x:
            break
        r += x
    print(r.count(b"HTTP/1.1 200"))
    print("closed")
    sys.exit(0)
if mode == "bad":
    c.sendall(b"CONNECT " + sys.argv[3].encode() + b" HTTP/1.1\r\n\r\n")
    print(c.recv(4096).split(b"\r\n")[0].decode())
    sys.exit(0)
if mode == "holdreset":
    c.sendall(b"CONNECT 127.0.0.1:%d HTTP/1.1\r\n\r\n" % tport)
    c.recv(4096)
    c.sendall(b"hello")
    open(sys.argv[4], "w").write("ready\n")
    time.sleep(60)
if mode in ("tunnel", "hold", "refuse"):
    c.sendall(b"CONNECT 127.0.0.1:%d HTTP/1.1\r\nHost: 127.0.0.1:%d\r\n\r\n" % (tport, tport))
    r = b""
    while b"\r\n\r\n" not in r:
        x = c.recv(4096)
        if not x:
            break
        r += x
    print(r.split(b"\r\n")[0].decode())
    if mode == "refuse":
        sys.exit(0)
    c.sendall(b"hello")
    got = b""
    while len(got) < 5:
        got += c.recv(4096)
    print(got.decode())
    if mode == "hold":
        open(sys.argv[4], "w").write("ready\n")
        time.sleep(60)
    c.close()
else:
    c.sendall(b"GET http://127.0.0.1:%d/secret-path?token=abc HTTP/1.1\r\nProxy-Authorization: Basic eA==\r\nHost: 127.0.0.1:%d\r\nproxy-connection: keep-alive\r\nConnection: close\r\n\r\n" % (tport, tport))
    r = b""
    while True:
        x = c.recv(4096)
        if not x:
            break
        r += x
    print(r.split(b"\r\n")[0].decode())
    print(r.split(b"\r\n\r\n")[1].decode())
PYEOF

raw=$T/raw
mkdir -m 0700 "$raw"
python3 -I "$H/server.py" echo "$H/echo.port" "$H/unused" &
bg_pid $!
python3 -I "$H/server.py" keep "$H/ka1.port" "$H/ka1.head" &
bg_pid $!
python3 -I "$H/server.py" keep "$H/ka2.port" "$H/ka2.head" &
bg_pid $!
python3 -I "$H/server.py" reset "$H/reset.port" "$H/unused2" &
bg_pid $!
python3 -I "$H/server.py" http "$H/http.port" "$H/http.head" &
bg_pid $!
wait_file "$H/echo.port" && wait_file "$H/http.port" && wait_file "$H/reset.port" && wait_file "$H/ka1.port" && wait_file "$H/ka2.port" || fail "servers start" "no port file"
eport=$(cat "$H/echo.port")
hport=$(cat "$H/http.port")
rport=$(cat "$H/reset.port")
k1=$(cat "$H/ka1.port")
k2=$(cat "$H/ka2.port")

python3 -I "$proxy" --log "$raw/proxy.jsonl" --port-file "$raw/proxy.port" &
ppid=$!
bg_pid "$ppid"
if wait_file "$raw/proxy.port"; then pass "proxy: the port file is written"; else fail "proxy: the port file is written" "no file"; fi
pport=$(cat "$raw/proxy.port")

# jfield N KEY: the value of KEY in line N of the log.
jfield() {
  sed -n "$1p" "$raw/proxy.jsonl" | python3 -I -c 'import json,sys; print(json.loads(sys.stdin.read())[sys.argv[1]])' "$2"
}

# CONNECT and 5 bytes each way.
python3 -I "$H/client.py" tunnel "$pport" "$eport" >"$T/o" 2>&1
expect_line "connect: the client gets 200" '^HTTP/1.1 200' "$T/o"
expect_line "connect: the client gets the echo" '^hello$' "$T/o"
wait_file "$raw/proxy.jsonl"
_n=0
while [ "$(wc -l <"$raw/proxy.jsonl")" -lt 1 ] && [ "$_n" -lt 100 ]; do sleep 0.05; _n=$((_n + 1)); done
for kv in up=5 down=5 status=ok host=127.0.0.1 method=CONNECT port=$eport; do
  got=$(jfield 1 "${kv%%=*}")
  if [ "$got" = "${kv#*=}" ]; then pass "connect: ${kv%%=*} is ${kv#*=}"; else fail "connect: ${kv%%=*} is ${kv#*=}" "$got"; fi
done
st=$(jfield 1 start)
en=$(jfield 1 end)
now=$(python3 -I -c 'import time; print(time.time_ns() // 1000000)')
if [ "$st" -le "$en" ] && [ "$en" -le "$now" ] && [ "$st" -gt 1700000000000 ]; then pass "connect: start and end are epoch milliseconds"; else fail "connect: start and end are epoch milliseconds" "$st $en $now"; fi

# CONNECT to a closed port: the port of a server that is gone.
python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])' >"$T/closed"
python3 -I "$H/client.py" refuse "$pport" "$(cat "$T/closed")" >"$T/o" 2>&1
expect_line "refused: the client gets 502" '^HTTP/1.1 502' "$T/o"
_n=0
while [ "$(wc -l <"$raw/proxy.jsonl")" -lt 2 ] && [ "$_n" -lt 100 ]; do sleep 0.05; _n=$((_n + 1)); done
got=$(jfield 2 status)
if [ "$got" = refused ]; then pass "refused: status is refused"; else fail "refused: status is refused" "$got"; fi

# A plain GET: origin-form to the host, no path in the log.
python3 -I "$H/client.py" get "$pport" "$hport" >"$T/o" 2>&1
expect_line "plain: the client gets 200" '^HTTP/1.1 200' "$T/o"
expect_line "plain: the client gets the body" '^ok$' "$T/o"
_n=0
while [ "$(wc -l <"$raw/proxy.jsonl")" -lt 3 ] && [ "$_n" -lt 100 ]; do sleep 0.05; _n=$((_n + 1)); done
expect_no_line "plain: no path in the log" 'secret-path|token|abc' "$raw/proxy.jsonl"
got=$(jfield 3 method)
if [ "$got" = GET ]; then pass "plain: method is GET"; else fail "plain: method is GET" "$got"; fi
want=$(printf 'GET /secret-path?token=abc HTTP/1.1\r\nHost: 127.0.0.1:%s\r\nConnection: close\r\n\r\n' "$hport" | od -An -c | tr -d ' \n')
got=$(od -An -c <"$H/http.head" | tr -d ' \n')
if [ "$got" = "$want" ]; then pass "plain: origin-form, no proxy header, no added header"; else fail "plain: origin-form, no proxy header, no added header" "$got"; fi

# wait_lines N: wait up to 10 s for N lines in the log.
wait_lines() {
  _n=0
  while [ "$(wc -l <"$raw/proxy.jsonl")" -lt "$1" ] && [ "$_n" -lt 200 ]; do sleep 0.05; _n=$((_n + 1)); done
}

# The host resets the connection after data, and the client keeps its
# socket open: the proxy closes both sides, and writes the line with the
# status error (a reset is not a normal end).
python3 -I "$H/client.py" holdreset "$pport" "$rport" "$H/held2" >"$T/o" 2>&1 &
bg_pid $!
wait_file "$H/held2"
wait_lines 4
got=$(jfield 4 status)
if [ "$got" = error ]; then pass "reset: status is error, with the client socket open"; else fail "reset: status is error, with the client socket open" "$got"; fi

# A bad CONNECT target gets 400 and no line.
for bad in 'user@127.0.0.1:80' '::1:80' 'a:b:80' '127.0.0.1:http' '127.0.0.1:' '127.0.0.1:0' '[::1' ; do
  python3 -I "$H/client.py" bad "$pport" "$bad" >"$T/o" 2>&1
  expect_line "bad target $bad: 400" '^HTTP/1.1 400' "$T/o"
done
n=$(wc -l <"$raw/proxy.jsonl")
if [ "$n" -eq 4 ]; then pass "bad target: no line in the log"; else fail "bad target: no line in the log" "$n lines"; fi

# 10 CONNECTs in parallel: 10 whole lines.
cat >"$H/par.py" <<'PYEOF'
import socket, sys, threading
pport, tport = int(sys.argv[1]), int(sys.argv[2])
def one():
    c = socket.create_connection(("127.0.0.1", pport))
    c.sendall(b"CONNECT 127.0.0.1:%d HTTP/1.1\r\n\r\n" % tport)
    c.recv(4096)
    c.sendall(b"hello")
    got = b""
    while len(got) < 5:
        got += c.recv(4096)
    c.close()
ts = [threading.Thread(target=one) for _ in range(10)]
for t in ts: t.start()
for t in ts: t.join()
PYEOF
python3 -I "$H/par.py" "$pport" "$eport"
wait_lines 14
if python3 -I -c '
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1])][4:]
assert len(rows) == 10 and all(r["up"] == 5 and r["down"] == 5 and r["status"] == "ok" for r in rows)' "$raw/proxy.jsonl"; then
  pass "parallel: 10 whole JSON lines"
else
  fail "parallel: 10 whole JSON lines" "$(wc -l <"$raw/proxy.jsonl") lines"
fi

# One request on each plain connection: two keep-alive requests in one
# write, for two origins. Only the first goes out.
python3 -I "$H/client.py" ka "$pport" "$k1" "$k2" >"$T/o" 2>&1
expect_line "keep-alive: the client sees one response" '^1$' "$T/o"
expect_line "keep-alive: the proxy closed the client connection" '^closed$' "$T/o"
wait_lines 15
if [ "$(grep -c '^GET ' "$H/ka1.head")" = 1 ]; then pass "keep-alive: the first origin got one request"; else fail "keep-alive: the first origin got one request" "$(cat "$H/ka1.head")"; fi
expect_line "keep-alive: the origin got Connection: close" '^Connection: close' "$H/ka1.head"
expect_no_line "keep-alive: no keep-alive header at the origin" '[Kk]eep-[Aa]live' "$H/ka1.head"
if [ ! -s "$H/ka2.head" ]; then pass "keep-alive: the second origin got nothing"; else fail "keep-alive: the second origin got nothing" "$(cat "$H/ka2.head")"; fi
got=$(jfield 15 port)
if [ "$got" = "$k1" ]; then pass "keep-alive: one line, with the first port"; else fail "keep-alive: one line, with the first port" "$got"; fi
python3 -I "$H/client.py" ka "$pport" "$k2" >"$T/o" 2>&1
wait_lines 16
got=$(jfield 16 port)
if [ "$got" = "$k2" ]; then pass "keep-alive: a new connection gets its own line"; else fail "keep-alive: a new connection gets its own line" "$got"; fi
if [ "$(wc -l <"$raw/proxy.jsonl")" = 16 ]; then pass "keep-alive: two lines in all"; else fail "keep-alive: two lines in all" "$(wc -l <"$raw/proxy.jsonl")"; fi

# TERM with one open connection: one line with status open, exit 0.
python3 -I "$H/client.py" hold "$pport" "$eport" "$H/held" >"$T/o" 2>&1 &
bg_pid $!
wait_file "$H/held"
before=$(wc -l <"$raw/proxy.jsonl")
kill -TERM "$ppid"
wait "$ppid"
expect_code "term: the proxy exits 0" 0 $?
after=$(wc -l <"$raw/proxy.jsonl")
if [ "$((after - before))" = 1 ]; then pass "term: one line for the open connection"; else fail "term: one line for the open connection" "$before -> $after"; fi
got=$(jfield "$after" status)
if [ "$got" = open ]; then pass "term: status is open"; else fail "term: status is open" "$got"; fi
got=$(jfield "$after" up)
if [ "$got" = 5 ]; then pass "term: the open line has up 5"; else fail "term: the open line has up 5" "$got"; fi
if kill -0 "$ppid" 2>/dev/null; then fail "term: the proxy stopped" "pid runs"; else pass "term: the proxy stopped"; fi

# The session cases need a backend: tmux, else pty.
if have tmux; then
  via=tmux
elif have pty; then
  via=pty
else
  echo "skip: session: no backend tool"
  done_tests
fi

# Session: the proxy variables. A subshell sets the variables for one call
# only: macOS sh keeps a variable that is set before a function call.
export AGENT_SIGNALS_RUN="$T/run1"
mkdir -m 700 "$T/run1"
printf '%s\n' "$pport" >"$raw/proxy.port"
python3 -I -c 'import time; print(time.time_ns() // 1000000)' >"$raw/t0"
(KIT_TRACE=$raw; KIT_TRACE_CHECKS=; export KIT_TRACE KIT_TRACE_CHECKS
 kit session start n1 stub --via $via --cmd "sh '$stub'") >"$T/o" 2>&1
expect_code "session: start exits 0" 0 $?
cond=$T/run1/sessions/n1/conditions
for v in HTTPS_PROXY HTTP_PROXY ALL_PROXY https_proxy http_proxy all_proxy NO_PROXY no_proxy; do
  expect_line "session: the conditions name $v" "^environment:.* $v( |\$)" "$cond"
done
expect_no_line "session: the conditions hold no port" "127\\.0\\.0\\.1:$pport" "$cond"
kit session stop n1 >"$T/o" 2>&1

# KIT_TRACE_CHECKS=terminal: no proxy variable.
(KIT_TRACE=$raw; KIT_TRACE_CHECKS=terminal; export KIT_TRACE KIT_TRACE_CHECKS
 kit session start n2 stub --via $via --cmd "sh '$stub'") >"$T/o" 2>&1
expect_code "terminal only: start exits 0" 0 $?
expect_no_line "terminal only: no proxy variable" '_?PROXY|_?proxy' "$T/run1/sessions/n2/conditions"
kit session stop n2 >"$T/o" 2>&1

# KIT_TRACE_CHECKS=files,network: the variables.
(KIT_TRACE=$raw; KIT_TRACE_CHECKS=files,network; export KIT_TRACE KIT_TRACE_CHECKS
 kit session start n3 stub --via $via --cmd "sh '$stub'") >"$T/o" 2>&1
expect_line "network listed: the proxy variables" '^environment:.* HTTPS_PROXY' "$T/run1/sessions/n3/conditions"
kit session stop n3 >"$T/o" 2>&1

# No proxy.port: no proxy variable.
rm -f "$raw/proxy.port"
(KIT_TRACE=$raw; KIT_TRACE_CHECKS=; export KIT_TRACE KIT_TRACE_CHECKS
 kit session start n4 stub --via $via --cmd "sh '$stub'") >"$T/o" 2>&1
expect_no_line "no port file: no proxy variable" '_?PROXY|_?proxy' "$T/run1/sessions/n4/conditions"
kit session stop n4 >"$T/o" 2>&1

done_tests
