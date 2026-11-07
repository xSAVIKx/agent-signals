package fakemodel

import (
	"bytes"
	"compress/gzip"
	"encoding/base64"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"
)

// The Cursor protocol: Connect RPC with protobuf messages. The field numbers
// come from the client CursorClientVersion.

// field is one protobuf field: an int is a varint, a []byte or a string is a
// length-delimited field.
type field struct {
	no int
	v  any
}

func appendVarint(b []byte, n uint64) []byte {
	for n >= 0x80 {
		b = append(b, byte(n)|0x80)
		n >>= 7
	}
	return append(b, byte(n))
}

// pb encodes FIELDS as one protobuf message.
func pb(fields ...field) []byte {
	var out []byte
	for _, f := range fields {
		switch v := f.v.(type) {
		case int:
			out = appendVarint(out, uint64(f.no)<<3)
			out = appendVarint(out, uint64(v))
		case string:
			out = appendVarint(out, uint64(f.no)<<3|2)
			out = appendVarint(out, uint64(len(v)))
			out = append(out, v...)
		case []byte:
			out = appendVarint(out, uint64(f.no)<<3|2)
			out = appendVarint(out, uint64(len(v)))
			out = append(out, v...)
		}
	}
	if out == nil {
		out = []byte{}
	}
	return out
}

var errProto = errors.New("bad protobuf")

func readVarint(b []byte, i int) (uint64, int, error) {
	var n uint64
	for shift := 0; shift < 64; shift += 7 {
		if i >= len(b) {
			return 0, i, errProto
		}
		c := b[i]
		i++
		n |= uint64(c&0x7f) << shift
		if c < 0x80 {
			return n, i, nil
		}
	}
	return 0, i, errProto
}

// pbField is one parsed field. bytes is nil for a varint or a fixed field.
type pbField struct {
	no    int
	bytes []byte
}

func pbFields(b []byte) ([]pbField, error) {
	var out []pbField
	i := 0
	for i < len(b) {
		key, j, err := readVarint(b, i)
		if err != nil {
			return nil, err
		}
		i = j
		f := pbField{no: int(key >> 3)}
		switch key & 7 {
		case 0:
			if _, i, err = readVarint(b, i); err != nil {
				return nil, err
			}
		case 2:
			n, j, err := readVarint(b, i)
			if err != nil || uint64(len(b)-j) < n {
				return nil, errProto
			}
			f.bytes = b[j : j+int(n)]
			if f.bytes == nil {
				f.bytes = []byte{}
			}
			i = j + int(n)
		case 1:
			if i+8 > len(b) {
				return nil, errProto
			}
			i += 8
		case 5:
			if i+4 > len(b) {
				return nil, errProto
			}
			i += 4
		default:
			return nil, errProto
		}
		out = append(out, f)
	}
	return out, nil
}

// pbGet returns the bytes at the field path. ok is false when a field is
// missing, is not length-delimited, or the message is bad.
func pbGet(b []byte, path ...int) ([]byte, bool) {
	for _, no := range path {
		if b == nil {
			return nil, false
		}
		fields, err := pbFields(b)
		if err != nil {
			return nil, false
		}
		var next []byte
		for _, f := range fields {
			if f.no == no {
				next = f.bytes
				break
			}
		}
		b = next
	}
	return b, b != nil
}

func b64(v any) string {
	j, _ := json.Marshal(v)
	return base64.RawURLEncoding.EncodeToString(j)
}

func fakeJWT() string {
	now := time.Now().Unix()
	return b64(map[string]any{"alg": "HS256", "typ": "JWT"}) + "." +
		b64(map[string]any{"sub": "auth0|fixture", "iat": now, "exp": now + 86400}) + ".c2ln"
}

var (
	cursorModel = pb(field{1, "fixture"}, field{3, "fixture"}, field{4, "Fixture"}, field{5, "Fixture"})
	cursorReply = map[string][]byte{
		"aiserver.v1.AiService/GetUsableModels":       pb(field{1, cursorModel}),
		"aiserver.v1.AiService/GetDefaultModelForCli": pb(field{1, cursorModel}),
	}
	// AgentServerMessage: 1 interaction_update {1 text_delta {1 text}, 13
	// heartbeat, 14 turn_ended}, 2 exec_server_message.
	cursorHeartbeat = pb(field{1, pb(field{13, []byte{}})})
	cursorTurnEnded = pb(field{1, pb(field{14, []byte{}})})
	// 3 conversation_checkpoint_update: the client keeps the chat only
	// after it.
	cursorCheckpoint = pb(field{3, []byte{}})
)

func cursorText(text string) []byte {
	return pb(field{1, pb(field{1, pb(field{1, text})})})
}

// cursorShell is an exec_server_message with the shell command: the client
// shows the "Run this command?" dialog. Field 8, the parsed command, is
// required.
func cursorShell(cwd string) []byte {
	arg := pb(field{1, "word"}, field{2, "agent-signals-test.txt"})
	parsed := pb(field{2, pb(field{1, "touch"}, field{2, arg}, field{3, Command})})
	shell := pb(field{1, Command}, field{2, cwd}, field{3, 30000}, field{4, "fixture-call"}, field{5, "touch"}, field{8, parsed})
	return pb(field{2, pb(field{1, 1}, field{15, "fixture-exec"}, field{2, shell})})
}

func envelope(payload []byte, flags byte) []byte {
	out := make([]byte, 5, 5+len(payload))
	out[0] = flags
	binary.BigEndian.PutUint32(out[1:], uint32(len(payload)))
	return append(out, payload...)
}

func unenvelope(b []byte) [][]byte {
	var out [][]byte
	for i := 0; i+5 <= len(b); {
		flags := b[i]
		n := int(binary.BigEndian.Uint32(b[i+1 : i+5]))
		end := i + 5 + n
		if end > len(b) {
			end = len(b)
		}
		p := b[i+5 : end]
		i = end
		if flags&1 != 0 {
			z, err := gzip.NewReader(bytes.NewReader(p))
			if err != nil {
				continue
			}
			if p, err = io.ReadAll(z); err != nil {
				continue
			}
		}
		out = append(out, p)
	}
	return out
}

// cursorRuns holds the client messages of each agent run (BidiAppend puts
// them, RunSSE reads them) and the newest RunSSE stream of each run. The
// client can open a second stream for a run (fact 78), and the old stream
// must then stop taking messages.
type cursorRuns struct {
	mu      sync.Mutex
	queues  map[string]chan []byte
	streams map[string]int
}

func newCursorRuns() *cursorRuns {
	return &cursorRuns{queues: map[string]chan []byte{}, streams: map[string]int{}}
}

func (c *cursorRuns) queue(rid string) chan []byte {
	c.mu.Lock()
	defer c.mu.Unlock()
	q, ok := c.queues[rid]
	if !ok {
		q = make(chan []byte, 1024)
		c.queues[rid] = q
	}
	return q
}

func (c *cursorRuns) newStream(rid string) int {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.streams[rid]++
	return c.streams[rid]
}

func (c *cursorRuns) current(rid string, stream int) bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.streams[rid] == stream
}

var errStale = errors.New("a newer RunSSE stream has the run")

func sendRaw(w http.ResponseWriter, ctype string, data []byte) {
	w.Header().Set("Content-Type", ctype)
	w.Header().Set("Content-Length", strconv.Itoa(len(data)))
	w.WriteHeader(http.StatusOK)
	w.Write(data)
}

func (s *server) cursorPost(w http.ResponseWriter, r *http.Request) {
	rpc := strings.TrimPrefix(r.URL.Path, "/")
	body, _ := readBody(r)
	ctype := r.Header.Get("Content-Type")
	if ctype == "" {
		ctype = "application/proto"
	}
	switch rpc {
	case "auth/exchange_user_api_key":
		s.note("POST %s reply", rpc)
		sendJSON(w, http.StatusOK, map[string]any{"accessToken": fakeJWT(), "refreshToken": fakeJWT()})
	case "aiserver.v1.BidiService/BidiAppend":
		ridb, _ := pbGet(body, 2, 1)
		// The client message is in field 4 (bytes) or in field 1 (hex).
		data, ok := pbGet(body, 4)
		if !ok || len(data) == 0 {
			h, _ := pbGet(body, 1)
			data, _ = hex.DecodeString(string(h))
		}
		if data == nil {
			data = []byte{}
		}
		select {
		case s.runs.queue(string(ridb)) <- data:
		default:
		}
		s.note("POST %s append", rpc)
		sendRaw(w, "application/proto", nil)
	case "agent.v1.AgentService/RunSSE":
		s.cursorRun(w, r, rpc, body)
	default:
		reply, ok := cursorReply[rpc]
		state := "reply"
		if !ok {
			state = "empty"
			reply = []byte{}
			if strings.Contains(ctype, "json") {
				reply = []byte("{}")
			}
		}
		s.note("POST %s %s", rpc, state)
		sendRaw(w, ctype, reply)
	}
}

func (s *server) cursorRun(w http.ResponseWriter, r *http.Request, rpc string, body []byte) {
	msgs := unenvelope(body)
	rid := ""
	if len(msgs) > 0 {
		b, _ := pbGet(msgs[0], 1)
		rid = string(b)
	}
	w.Header().Set("Content-Type", "application/connect+proto")
	w.WriteHeader(http.StatusOK)
	// Send the headers now, as the client waits for them before it appends
	// a message.
	f, _ := w.(http.Flusher)
	if f != nil {
		f.Flush()
	}
	send := func(payload []byte, flags byte) error {
		if _, err := w.Write(envelope(payload, flags)); err != nil {
			return err
		}
		if f != nil {
			f.Flush()
		}
		return nil
	}
	s.note("POST %s start", rpc)
	q := s.runs.queue(rid)
	stream := s.runs.newStream(rid)

	// take returns the next client message, or nil after TIMEOUT.
	take := func(timeout time.Duration) ([]byte, error) {
		t := time.NewTimer(timeout)
		defer t.Stop()
		var data []byte
		select {
		case data = <-q:
		case <-t.C:
		case <-r.Context().Done():
			return nil, r.Context().Err()
		}
		if !s.runs.current(rid, stream) {
			if data != nil {
				select {
				case q <- data:
				default:
				}
			}
			return nil, errStale
		}
		return data, nil
	}

	err := func() (err error) {
		// A bad message must not leave the stream open.
		defer func() {
			if p := recover(); p != nil {
				err = errors.New("panic")
			}
		}()
		for {
			data, err := take(holdTime)
			if err != nil {
				return err
			}
			if data == nil {
				break
			}
			// AgentClientMessage: 1 run_request, 2 action, 1
			// user_message_action, 1 user_message, 1 text.
			text, ok := pbGet(data, 1, 2, 1, 1, 1)
			if !ok {
				continue
			}
			kind := classify(string(text), true)
			s.note("POST %s %s", rpc, kind)
			switch kind {
			case kindHold:
				if err := s.cursorHold(take, send); err != nil {
					return err
				}
			case kindTool:
				cwd, _ := pbGet(data, 1, 2, 1, 2, 4, 2)
				if err := send(cursorShell(string(cwd)), 0); err != nil {
					return err
				}
				if err := s.cursorWait(take, send); err != nil {
					return err
				}
				if err := send(cursorText(ToolDone), 0); err != nil {
					return err
				}
			case kindChoice, kindQuestion:
				if err := send(cursorText(Question), 0); err != nil {
					return err
				}
			default:
				if err := send(cursorText(Text), 0); err != nil {
					return err
				}
			}
			if err := send(cursorCheckpoint, 0); err != nil {
				return err
			}
			if err := send(cursorTurnEnded, 0); err != nil {
				return err
			}
			break
		}
		return send([]byte("{}"), 2)
	}()
	switch {
	case err == nil:
	case errors.Is(err, errStale):
		s.note("POST %s replaced", rpc)
	case err.Error() == "panic":
		s.note("POST %s error panic", rpc)
		if send(cursorTurnEnded, 0) == nil {
			send([]byte("{}"), 2)
		}
	default:
		s.note("POST %s closed", rpc)
	}
}

// cursorHold keeps the turn busy: a heartbeat every 2 s, until a client
// message with field 4 (a stop) or the hold time.
func (s *server) cursorHold(take func(time.Duration) ([]byte, error), send func([]byte, byte) error) error {
	end := time.Now().Add(holdTime)
	for time.Now().Before(end) {
		data, err := take(2 * time.Second)
		if err != nil {
			return err
		}
		if data == nil {
			if err := send(cursorHeartbeat, 0); err != nil {
				return err
			}
			continue
		}
		if _, ok := pbGet(data, 4); ok {
			break
		}
	}
	s.note("hold ended")
	return nil
}

// cursorWait waits for the result of the shell command or a stop. The
// heartbeats keep the stream open while the dialog shows.
func (s *server) cursorWait(take func(time.Duration) ([]byte, error), send func([]byte, byte) error) error {
	end := time.Now().Add(holdTime)
	for time.Now().Before(end) {
		data, err := take(2 * time.Second)
		if err != nil {
			return err
		}
		if data == nil {
			if err := send(cursorHeartbeat, 0); err != nil {
				return err
			}
			continue
		}
		names := "bad"
		if fields, err := pbFields(data); err == nil {
			var n []string
			for _, f := range fields {
				n = append(n, strconv.Itoa(f.no))
			}
			names = strings.Join(n, ",")
		}
		s.note("POST agent.v1.AgentService/RunSSE client %s", names)
		_, stop := pbGet(data, 2)
		_, cancel := pbGet(data, 4)
		if stop || cancel {
			return nil
		}
	}
	return nil
}
