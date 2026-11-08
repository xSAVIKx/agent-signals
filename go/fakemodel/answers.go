package fakemodel

import (
	"bytes"
	"compress/gzip"
	"encoding/json"
	"io"
	"net/http"
	"regexp"
	"strings"
	"time"
)

// The kinds of answer.
const (
	kindText     = "text"
	kindTool     = "tool"
	kindHold     = "hold"
	kindChoice   = "choice"
	kindQuestion = "question"
	kindWrite    = "write"
	// A review answer. The log names the verdict: "review allow" or
	// "review deny".
	kindReview = "review"
	// The answer to a request with a JSON schema that is not a review.
	kindStructured = "structured"
)

// severityForm is the text of the Claude Code review prompt that asks for
// the verdict.
const severityForm = "<severity>N</severity>"

// verdict returns "deny" when TEXT holds TriggerDeny, else "allow".
func verdict(text string) string {
	if strings.Contains(text, TriggerDeny) {
		return "deny"
	}
	return "allow"
}

// fill returns a value for the JSON SCHEMA: the first enum value, "Fixture"
// for a string, 0 for a number, false for a boolean, and an object with each
// required property. For the property "outcome" the value is VERDICT.
func fill(schema map[string]any, verdictValue string) any {
	if e := list(schema["enum"]); len(e) > 0 {
		return e[0]
	}
	switch schema["type"] {
	case "object":
		out := map[string]any{}
		props := obj(schema["properties"])
		for _, r := range list(schema["required"]) {
			name, _ := r.(string)
			if name == "outcome" {
				out[name] = verdictValue
				continue
			}
			out[name] = fill(obj(props[name]), verdictValue)
		}
		return out
	case "array":
		return []any{}
	case "number", "integer":
		return 0
	case "boolean":
		return false
	}
	return "Fixture"
}

// classify returns the kind of answer for the last user text.
func classify(text string, hasTools bool) string {
	switch {
	case !hasTools:
		return kindText
	case strings.Contains(text, TriggerHold):
		return kindHold
	case strings.Contains(text, TriggerTool):
		return kindTool
	case strings.Contains(text, TriggerWrite), strings.Contains(text, TriggerWriteOutside):
		return kindWrite
	case strings.Contains(text, TriggerChoice):
		return kindChoice
	case strings.Contains(text, TriggerQuestion):
		return kindQuestion
	}
	return kindText
}

// absPath matches an absolute path: /x on Unix, or C:\x on Windows.
var absPath = regexp.MustCompile(`(?:[A-Za-z]:\\|/)[^\s"'<>]+`)

// writePath returns the path of a write call for the user TEXT, or "" when
// TriggerWriteOutside has no absolute path after it. CWD is the work folder,
// or "" for a relative path.
func writePath(text, cwd string) string {
	if i := strings.Index(text, TriggerWriteOutside); i >= 0 {
		return strings.TrimRight(absPath.FindString(text[i+len(TriggerWriteOutside):]), ".,;:)")
	}
	switch {
	case cwd == "":
		return WriteFile
	case strings.Contains(cwd, `\`) && !strings.Contains(cwd, "/"):
		return strings.TrimRight(cwd, `\`) + `\` + WriteFile
	}
	return strings.TrimRight(cwd, "/") + "/" + WriteFile
}

// labelValue returns the rest of the line after LABEL in TEXT, or "".
func labelValue(text, label string) string {
	i := strings.Index(text, label)
	if i < 0 {
		return ""
	}
	v, _, _ := strings.Cut(text[i+len(label):], "\n")
	return strings.TrimSpace(v)
}

// textOf returns the text of a message content: a string, or a list of parts
// with "text".
func textOf(content any) string {
	if s, ok := content.(string); ok {
		return s
	}
	var out []string
	for _, c := range list(content) {
		if t, ok := obj(c)["text"].(string); ok {
			out = append(out, t)
		}
	}
	return strings.Join(out, " ")
}

func obj(v any) map[string]any {
	m, _ := v.(map[string]any)
	return m
}

func list(v any) []any {
	l, _ := v.([]any)
	return l
}

func hasTools(body map[string]any) bool { return len(list(body["tools"])) > 0 }

// hasTool reports whether the request offers the tool NAME.
func hasTool(body map[string]any, name string) bool {
	for _, t := range list(body["tools"]) {
		if obj(t)["name"] == name {
			return true
		}
	}
	return false
}

// marshal returns the JSON of V with no HTML escapes, as the real APIs
// write it: "<" stays "<", not "\u003c".
func marshal(v any) []byte {
	var buf bytes.Buffer
	e := json.NewEncoder(&buf)
	e.SetEscapeHTML(false)
	e.Encode(v)
	return bytes.TrimSuffix(buf.Bytes(), []byte("\n"))
}

func sse(event string, data any) []byte {
	b := marshal(data)
	head := ""
	if event != "" {
		head = "event: " + event + "\n"
	}
	return []byte(head + "data: " + string(b) + "\n\n")
}

// readBody returns the request body. Go removes the chunked encoding; this
// removes gzip.
func readBody(r *http.Request) ([]byte, error) {
	b, err := io.ReadAll(r.Body)
	if err != nil {
		return nil, err
	}
	if r.Header.Get("Content-Encoding") == "gzip" {
		z, err := gzip.NewReader(bytes.NewReader(b))
		if err != nil {
			return nil, err
		}
		return io.ReadAll(z)
	}
	return b, nil
}

// post answers the JSON APIs of Codex, Claude Code and agy.
func (s *server) post(w http.ResponseWriter, r *http.Request) {
	var body map[string]any
	if raw, err := readBody(r); err == nil {
		json.Unmarshal(raw, &body)
	}
	if body == nil {
		body = map[string]any{}
	}
	rid := s.nextID()
	path := r.URL.Path
	if strings.HasSuffix(path, "/count_tokens") {
		s.note("POST %s %s reply", path, rid)
		sendJSON(w, http.StatusOK, map[string]any{"input_tokens": 1})
		return
	}
	model, _ := body["model"].(string)
	if model == "" {
		model = agyModel
	}
	stream := true
	var kind string
	var chunks [][]byte
	var whole func() any
	switch {
	case strings.HasSuffix(path, "/responses"):
		var items []any
		kind, items = codexAnswer(body)
		chunks = codexStream(rid, kind, items)
		if kind != kindHold && !strings.HasPrefix(kind, kindReview) && kind != kindStructured {
			kind = "reply"
		}
	case strings.HasSuffix(path, "/messages"):
		var text string
		kind, text = claudeAnswer(body)
		stream, _ = body["stream"].(bool)
		chunks = claudeStream(rid, model, kind, text)
		k, t := kind, text
		whole = func() any { blocks, stop := claudeBlocks(k, t); return claudeMessage(rid, model, blocks, stop) }
	case strings.HasSuffix(path, "/chat/completions"):
		var text string
		kind, text = agyAnswer(body)
		stream, _ = body["stream"].(bool)
		chunks = agyStream(rid, model, kind, text)
		k, t := kind, text
		whole = func() any { return agyMessage(rid, model, k, t) }
	default:
		s.note("POST %s %s unknown", path, rid)
		sendJSON(w, http.StatusNotFound, map[string]any{})
		return
	}
	s.note("POST %s %s %s", path, rid, kind)
	if !stream && kind != kindHold {
		sendJSON(w, http.StatusOK, whole())
		return
	}
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "close")
	w.WriteHeader(http.StatusOK)
	f, _ := w.(http.Flusher)
	if f != nil {
		f.Flush()
	}
	for _, c := range chunks {
		if _, err := w.Write(c); err != nil {
			return
		}
		if f != nil {
			f.Flush()
		}
	}
	if kind == kindHold {
		hold(r)
		s.note("hold ended")
	}
}

// ---------------------------------------------------------------- codex

// codexAnswer returns the kind and the output items. Only the items after the
// last user message count: a tool result of an earlier turn must not end a
// new turn.
func codexAnswer(body map[string]any) (string, []any) {
	if format := obj(obj(body["text"])["format"]); format["type"] == "json_schema" {
		schema := obj(format["schema"])
		if _, ok := obj(schema["properties"])["outcome"]; ok {
			v := verdict(inputText(body["input"]))
			out := marshal(fill(schema, v))
			return kindReview + " " + v, []any{codexText(string(out))}
		}
		out := marshal(fill(schema, ""))
		return kindStructured, []any{codexText(string(out))}
	}
	var items []map[string]any
	for _, i := range list(body["input"]) {
		if m := obj(i); m != nil {
			items = append(items, m)
		}
	}
	last := -1
	for n, i := range items {
		if i["role"] == "user" {
			last = n
		}
	}
	for _, i := range items[last+1:] {
		if i["type"] == "function_call_output" || i["type"] == "custom_tool_call_output" {
			return kindText, []any{codexText(ToolDone)}
		}
	}
	text := ""
	if last >= 0 {
		text = textOf(items[last]["content"])
	}
	switch kind := classify(text, true); kind {
	case kindHold:
		return kind, nil
	case kindTool:
		args, _ := json.Marshal(map[string]any{
			"cmd":                 Command,
			"sandbox_permissions": "require_escalated",
			"justification":       "The kit fixture asks for this write.",
		})
		return kind, []any{map[string]any{
			"type":      "function_call",
			"call_id":   "fixture-call",
			"name":      "exec_command",
			"arguments": string(args),
		}}
	case kindWrite:
		path := writePath(text, "")
		if path == "" {
			return kindText, []any{codexText(NoPath)}
		}
		patch := "*** Begin Patch\n*** Add File: " + path + "\n+" + strings.TrimSuffix(WriteText, "\n") + "\n*** End Patch\n"
		return kind, []any{map[string]any{
			"type":    "custom_tool_call",
			"call_id": "fixture-write",
			"name":    "apply_patch",
			"input":   patch,
		}}
	case kindChoice, kindQuestion:
		return kind, []any{codexText(Question)}
	}
	return kindText, []any{codexText(Text)}
}

// inputText returns the text of all user messages of a Codex input list.
func inputText(input any) string {
	var out []string
	for _, i := range list(input) {
		if m := obj(i); m["role"] == "user" {
			out = append(out, textOf(m["content"]))
		}
	}
	return strings.Join(out, " ")
}

func codexText(text string) map[string]any {
	return map[string]any{
		"type":    "message",
		"role":    "assistant",
		"id":      "fixture-message",
		"content": []any{map[string]any{"type": "output_text", "text": text}},
	}
}

func codexStream(rid, kind string, items []any) [][]byte {
	out := [][]byte{sse("response.created", map[string]any{"type": "response.created", "response": map[string]any{"id": rid}})}
	if kind == kindHold {
		return out
	}
	for _, item := range items {
		out = append(out, sse("response.output_item.done", map[string]any{"type": "response.output_item.done", "item": item}))
	}
	usage := map[string]any{
		"input_tokens":          0,
		"output_tokens":         0,
		"total_tokens":          0,
		"input_tokens_details":  nil,
		"output_tokens_details": nil,
	}
	return append(out, sse("response.completed", map[string]any{"type": "response.completed", "response": map[string]any{"id": rid, "usage": usage}}))
}

// --------------------------------------------------------------- claude

// claudeAnswer returns the kind and the text. For kindWrite the text is the
// path. Claude Code 2.1.318 puts a "system" message after the user message,
// so the last user message counts.
func claudeAnswer(body map[string]any) (string, string) {
	if strings.Contains(textOf(body["system"]), severityForm) {
		var all []string
		for _, m := range list(body["messages"]) {
			all = append(all, textOf(obj(m)["content"]))
		}
		if verdict(strings.Join(all, " ")) == "deny" {
			return kindReview + " deny", ReviewDeny
		}
		return kindReview + " allow", ReviewAllow
	}
	var last map[string]any
	msgs := list(body["messages"])
	for i := len(msgs) - 1; i >= 0; i-- {
		if m := obj(msgs[i]); m != nil && m["role"] == "user" {
			last = m
			break
		}
	}
	content := last["content"]
	for _, c := range list(content) {
		if obj(c)["type"] == "tool_result" {
			return kindText, ToolDone
		}
	}
	text := textOf(content)
	kind := classify(text, hasTools(body))
	switch {
	case kind == kindWrite:
		path := writePath(text, labelValue(textOf(body["system"]), "Primary working directory: "))
		if path == "" {
			return kindText, NoPath
		}
		return kind, path
	case kind == kindChoice && !hasTool(body, "AskUserQuestion"):
		return kindQuestion, Question
	case kind == kindQuestion:
		return kind, Question
	}
	return kind, Text
}

// claudeChoice is the input of the AskUserQuestion call.
var claudeChoice = map[string]any{
	"questions": []any{map[string]any{
		"question": "Which color do you like?",
		"header":   "Color",
		"options": []any{
			map[string]any{"label": "Red", "description": "The color red."},
			map[string]any{"label": "Blue", "description": "The color blue."},
		},
		"multiSelect": false,
	}},
}

func claudeBlocks(kind, text string) ([]any, string) {
	switch kind {
	case kindTool:
		return []any{map[string]any{
			"type":  "tool_use",
			"id":    "toolu_fixture",
			"name":  "Bash",
			"input": map[string]any{"command": Command, "description": "Create the test file"},
		}}, "tool_use"
	case kindWrite:
		return []any{map[string]any{
			"type":  "tool_use",
			"id":    "toolu_fixture_write",
			"name":  "Write",
			"input": map[string]any{"file_path": text, "content": WriteText},
		}}, "tool_use"
	case kindChoice:
		return []any{map[string]any{
			"type":  "tool_use",
			"id":    "toolu_fixture_choice",
			"name":  "AskUserQuestion",
			"input": claudeChoice,
		}}, "tool_use"
	}
	return []any{map[string]any{"type": "text", "text": text}}, "end_turn"
}

func claudeMessage(rid, model string, blocks []any, stop any) map[string]any {
	if blocks == nil {
		blocks = []any{}
	}
	return map[string]any{
		"id":            rid,
		"type":          "message",
		"role":          "assistant",
		"model":         model,
		"content":       blocks,
		"stop_reason":   stop,
		"stop_sequence": nil,
		"usage":         map[string]any{"input_tokens": 1, "output_tokens": 1},
	}
}

func claudeStream(rid, model, kind, text string) [][]byte {
	out := [][]byte{sse("message_start", map[string]any{"type": "message_start", "message": claudeMessage(rid, model, nil, nil)})}
	if kind == kindHold {
		return out
	}
	blocks, stop := claudeBlocks(kind, text)
	for i, b := range blocks {
		m := obj(b)
		var first, delta map[string]any
		if m["type"] == "text" {
			first = map[string]any{"type": "text", "text": ""}
			delta = map[string]any{"type": "text_delta", "text": m["text"]}
		} else {
			first = map[string]any{}
			for k, v := range m {
				first[k] = v
			}
			first["input"] = map[string]any{}
			in := marshal(m["input"])
			delta = map[string]any{"type": "input_json_delta", "partial_json": string(in)}
		}
		out = append(out,
			sse("content_block_start", map[string]any{"type": "content_block_start", "index": i, "content_block": first}),
			sse("content_block_delta", map[string]any{"type": "content_block_delta", "index": i, "delta": delta}),
			sse("content_block_stop", map[string]any{"type": "content_block_stop", "index": i}))
	}
	return append(out,
		sse("message_delta", map[string]any{
			"type":  "message_delta",
			"delta": map[string]any{"stop_reason": stop, "stop_sequence": nil},
			"usage": map[string]any{"output_tokens": 1},
		}),
		sse("message_stop", map[string]any{"type": "message_stop"}))
}

// ------------------------------------------------------------------ agy

// agyAnswer returns the kind and the text. For kindWrite the text is the path.
func agyAnswer(body map[string]any) (string, string) {
	var last map[string]any
	msgs := list(body["messages"])
	for i := len(msgs) - 1; i >= 0; i-- {
		if m := obj(msgs[i]); m != nil && (m["role"] == "user" || m["role"] == "tool") {
			last = m
			break
		}
	}
	if last["role"] == "tool" {
		return kindText, ToolDone
	}
	text := textOf(last["content"])
	kind := classify(text, hasTools(body))
	switch kind {
	case kindWrite:
		cwd := ""
		for _, m := range msgs {
			if v := labelValue(textOf(obj(m)["content"]), "Command Working Directory: "); v != "" {
				cwd = v
				break
			}
		}
		if path := writePath(text, cwd); path != "" {
			return kind, path
		}
		return kindText, NoPath
	case kindChoice, kindQuestion:
		return kindQuestion, Question
	}
	return kind, Text
}

func agyDelta(kind, text string) (map[string]any, string) {
	if kind == kindWrite {
		args, _ := json.Marshal(map[string]any{"Path": text, "Content": WriteText})
		call := map[string]any{
			"index":    0,
			"id":       "call_fixture_write",
			"type":     "function",
			"function": map[string]any{"name": "write_file", "arguments": string(args)},
		}
		return map[string]any{"role": "assistant", "tool_calls": []any{call}}, "tool_calls"
	}
	if kind == kindTool {
		args, _ := json.Marshal(map[string]any{
			"CommandLine":       Command,
			"toolSummary":       "Test file creation",
			"WaitMsBeforeAsync": 5000,
		})
		call := map[string]any{
			"index":    0,
			"id":       "call_fixture",
			"type":     "function",
			"function": map[string]any{"name": "run_command", "arguments": string(args)},
		}
		return map[string]any{"role": "assistant", "tool_calls": []any{call}}, "tool_calls"
	}
	return map[string]any{"role": "assistant", "content": text}, "stop"
}

func agyChunk(rid, model string, delta map[string]any, finish any) map[string]any {
	return map[string]any{
		"id":      rid,
		"object":  "chat.completion.chunk",
		"created": time.Now().Unix(),
		"model":   model,
		"choices": []any{map[string]any{"index": 0, "delta": delta, "finish_reason": finish}},
	}
}

func agyStream(rid, model, kind, text string) [][]byte {
	if kind == kindHold {
		return nil
	}
	delta, finish := agyDelta(kind, text)
	end := agyChunk(rid, model, map[string]any{}, finish)
	end["usage"] = map[string]any{"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2}
	return [][]byte{sse("", agyChunk(rid, model, delta, nil)), sse("", end), []byte("data: [DONE]\n\n")}
}

func agyMessage(rid, model, kind, text string) map[string]any {
	delta, finish := agyDelta(kind, text)
	return map[string]any{
		"id":      rid,
		"object":  "chat.completion",
		"created": time.Now().Unix(),
		"model":   model,
		"choices": []any{map[string]any{"index": 0, "message": delta, "finish_reason": finish}},
		"usage":   map[string]any{"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2},
	}
}
