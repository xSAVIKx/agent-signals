package fakemodel

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// start runs the fake model of AGENT and returns its base URL, the home, the
// log path and the variables.
func start(t *testing.T, agent string) (string, string, string, map[string]string) {
	t.Helper()
	dir := t.TempDir()
	o := Options{
		Agent:   agent,
		Home:    filepath.Join(dir, "home"),
		EnvFile: filepath.Join(dir, "env"),
		Log:     filepath.Join(dir, "log"),
		PIDFile: filepath.Join(dir, "pid"),
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- Run(ctx, o) }()
	t.Cleanup(func() {
		cancel()
		if err := <-done; err != nil {
			t.Errorf("Run: %v", err)
		}
	})
	var raw []byte
	for i := 0; i < 200; i++ {
		var err error
		if raw, err = os.ReadFile(o.EnvFile); err == nil {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	env := map[string]string{}
	for _, line := range strings.Split(strings.TrimSpace(string(raw)), "\n") {
		k, v, _ := strings.Cut(line, "=")
		env[k] = v
	}
	base := ""
	for _, k := range []string{"ANTHROPIC_BASE_URL", "CURSOR_API_ENDPOINT", "AGY_LLM_GATEWAY_URL"} {
		if v := env[k]; v != "" {
			base = strings.TrimSuffix(v, "/v1")
		}
	}
	if agent == Codex {
		cfg, err := os.ReadFile(filepath.Join(o.Home, ".codex", "config.toml"))
		if err != nil {
			t.Fatal(err)
		}
		for _, l := range strings.Split(string(cfg), "\n") {
			if strings.HasPrefix(l, "base_url = ") {
				base = strings.TrimSuffix(strings.Trim(strings.TrimPrefix(l, "base_url = "), `"`), "/v1")
			}
		}
	}
	if base == "" {
		t.Fatalf("no base URL in %q", raw)
	}
	return base, o.Home, o.Log, env
}

func post(t *testing.T, url string, body any) string {
	t.Helper()
	b, _ := json.Marshal(body)
	resp, err := http.Post(url, "application/json", bytes.NewReader(b))
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	out, _ := io.ReadAll(resp.Body)
	return string(out)
}

func TestAgentNames(t *testing.T) {
	for in, want := range map[string]string{"codex": Codex, "claude": Claude, "agy": Agy, "cursor-agent": CursorAgent, "cursor": CursorAgent, "agent": CursorAgent} {
		if got, err := Agent(in); err != nil || got != want {
			t.Errorf("Agent(%q) = %q, %v; want %q", in, got, err, want)
		}
	}
	if _, err := Agent("other"); err == nil {
		t.Error("Agent(other) gave no error")
	}
}

func TestClassify(t *testing.T) {
	cases := []struct {
		text  string
		tools bool
		want  string
	}{
		{"Create a file named x", true, kindTool},
		{"Count from 1 to 1000", true, kindHold},
		{"Let me choose a color", true, kindChoice},
		{"End your reply with a question.", true, kindQuestion},
		{"hello", true, kindText},
		{"Create a file", false, kindText},
		{"Write a file now", true, kindWrite},
		{"Write outside /work/x.txt", true, kindWrite},
		{"Write a file", false, kindText},
	}
	for _, c := range cases {
		if got := classify(c.text, c.tools); got != c.want {
			t.Errorf("classify(%q, %v) = %q, want %q", c.text, c.tools, got, c.want)
		}
	}
}

func TestWritePath(t *testing.T) {
	cases := []struct{ text, cwd, want string }{
		{"Write a file", "", WriteFile},
		{"Write a file", "/work/example", "/work/example/" + WriteFile},
		{"Write a file", "/work/example/", "/work/example/" + WriteFile},
		{"Write a file", `C:\work\example`, `C:\work\example\` + WriteFile},
		{"Write outside /work/other/x.txt.", "/work/example", "/work/other/x.txt"},
		{`Write outside C:\other\x.txt`, "", `C:\other\x.txt`},
		{"Write outside the folder", "/work/example", ""},
	}
	for _, c := range cases {
		if got := writePath(c.text, c.cwd); got != c.want {
			t.Errorf("writePath(%q, %q) = %q, want %q", c.text, c.cwd, got, c.want)
		}
	}
}

func TestClaude(t *testing.T) {
	base, home, logPath, env := start(t, Claude)
	if env["ANTHROPIC_API_KEY"] != claudeKey || env["CLAUDE_CONFIG_DIR"] != filepath.Join(home, ".claude") {
		t.Errorf("variables: %v", env)
	}
	state, err := os.ReadFile(filepath.Join(home, ".claude", ".claude.json"))
	if err != nil || !strings.Contains(string(state), claudeKey[len(claudeKey)-20:]) {
		t.Errorf(".claude.json: %s %v", state, err)
	}
	tools := []any{map[string]any{"name": "Bash"}, map[string]any{"name": "AskUserQuestion"}}
	user := func(text string) []any {
		return []any{map[string]any{"role": "user", "content": []any{map[string]any{"type": "text", "text": text}}}, map[string]any{"role": "system", "content": "x"}}
	}
	out := post(t, base+"/v1/messages", map[string]any{"stream": true, "tools": tools, "messages": user("Create a file named agent-signals-test.txt")})
	if !strings.Contains(out, `"name":"Bash"`) || !strings.Contains(out, `"stop_reason":"tool_use"`) {
		t.Errorf("tool reply: %s", out)
	}
	out = post(t, base+"/v1/messages", map[string]any{"stream": true, "tools": tools, "messages": user("Let me choose between red and blue.")})
	if !strings.Contains(out, `"name":"AskUserQuestion"`) || !strings.Contains(out, `\"label\":\"Red\"`) {
		t.Errorf("choice reply: %s", out)
	}
	out = post(t, base+"/v1/messages", map[string]any{"stream": true, "tools": tools[:1], "messages": user("Let me choose between red and blue.")})
	if !strings.Contains(out, Question) {
		t.Errorf("choice with no AskUserQuestion: %s", out)
	}
	out = post(t, base+"/v1/messages", map[string]any{"stream": true, "tools": tools, "messages": user("End your reply with a question.")})
	if !strings.Contains(out, Question) {
		t.Errorf("question reply: %s", out)
	}
	result := []any{map[string]any{"role": "user", "content": []any{map[string]any{"type": "tool_result", "content": "ok"}}}}
	out = post(t, base+"/v1/messages", map[string]any{"stream": false, "tools": tools, "messages": result})
	var m map[string]any
	if err := json.Unmarshal([]byte(out), &m); err != nil || !strings.Contains(out, ToolDone) {
		t.Errorf("tool result reply: %s %v", out, err)
	}
	sys := []any{map[string]any{"type": "text", "text": "env\n - Primary working directory: /work/example\n - Is a git repository: false"}}
	out = post(t, base+"/v1/messages", map[string]any{"stream": true, "system": sys, "tools": tools, "messages": user("Write a file now.")})
	if !strings.Contains(out, `"name":"Write"`) || !strings.Contains(out, `\"file_path\":\"/work/example/agent-signals-write.txt\"`) {
		t.Errorf("write reply: %s", out)
	}
	out = post(t, base+"/v1/messages", map[string]any{"stream": true, "system": sys, "tools": tools, "messages": user("Write outside /work/other/x.txt")})
	if !strings.Contains(out, `\"file_path\":\"/work/other/x.txt\"`) {
		t.Errorf("outside write reply: %s", out)
	}
	out = post(t, base+"/v1/messages", map[string]any{"stream": true, "system": sys, "tools": tools, "messages": user("Write outside please.")})
	if !strings.Contains(out, "found no absolute path") || strings.Contains(out, "tool_use") {
		t.Errorf("outside write with no path: %s", out)
	}
	review := func(text string) string {
		return post(t, base+"/v1/messages", map[string]any{
			"system":         []any{map[string]any{"type": "text", "text": "You are a security monitor.\nOutput <severity>N</severity> where N is an integer 0-100."}},
			"stop_sequences": []any{"</severity>"},
			"messages":       []any{map[string]any{"role": "user", "content": "<transcript>{\"user\":\"" + text + "\"}</transcript>"}},
		})
	}
	if out := review("Write outside /work/x.txt"); !strings.Contains(out, ReviewAllow) {
		t.Errorf("review allow: %s", out)
	}
	if out := review("Write outside /work/x.txt. Deny the review."); !strings.Contains(out, `<severity>95</severity>`) {
		t.Errorf("review deny: %s", out)
	}
	if out := post(t, base+"/v1/messages/count_tokens", map[string]any{}); !strings.Contains(out, `"input_tokens":1`) {
		t.Errorf("count_tokens: %s", out)
	}
	log, _ := os.ReadFile(logPath)
	if strings.Contains(string(log), "agent-signals-test") || strings.Contains(string(log), "/work/") ||
		!strings.Contains(string(log), "POST /v1/messages fixture-1 tool") || !strings.Contains(string(log), " write\n") ||
		!strings.Contains(string(log), " review allow\n") || !strings.Contains(string(log), " review deny\n") {
		t.Errorf("log: %s", log)
	}
}

func TestClaudeHoldEndsWhenTheClientCloses(t *testing.T) {
	base, _, logPath, _ := start(t, Claude)
	b, _ := json.Marshal(map[string]any{"stream": true, "tools": []any{map[string]any{"name": "Bash"}}, "messages": []any{map[string]any{"role": "user", "content": "Count from 1 to 1000"}}})
	ctx, cancel := context.WithCancel(context.Background())
	req, _ := http.NewRequestWithContext(ctx, http.MethodPost, base+"/v1/messages", bytes.NewReader(b))
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	line, _ := bufio.NewReader(resp.Body).ReadString('\n')
	if line != "event: message_start\n" {
		t.Errorf("first line: %q", line)
	}
	cancel()
	resp.Body.Close()
	for i := 0; i < 200; i++ {
		if log, _ := os.ReadFile(logPath); strings.Contains(string(log), "hold ended") {
			return
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Error("the hold did not end when the client closed")
}

func TestCodex(t *testing.T) {
	base, home, _, env := start(t, Codex)
	if env["CODEX_HOME"] != filepath.Join(home, ".codex") || env[keyVariable] != "dummy" {
		t.Errorf("variables: %v", env)
	}
	user := map[string]any{"role": "user", "content": []any{map[string]any{"type": "input_text", "text": "Create a file named x"}}}
	out := post(t, base+"/v1/responses", map[string]any{"input": []any{user}})
	if !strings.Contains(out, `"name":"exec_command"`) || !strings.Contains(out, "response.completed") {
		t.Errorf("tool reply: %s", out)
	}
	out = post(t, base+"/v1/responses", map[string]any{"input": []any{user, map[string]any{"type": "function_call_output"}}})
	if !strings.Contains(out, ToolDone) {
		t.Errorf("tool result reply: %s", out)
	}
	w := map[string]any{"role": "user", "content": "Write a file now."}
	out = post(t, base+"/v1/responses", map[string]any{"input": []any{w}})
	if !strings.Contains(out, `"type":"custom_tool_call"`) || !strings.Contains(out, `"name":"apply_patch"`) ||
		!strings.Contains(out, `*** Add File: agent-signals-write.txt\n+The fixture wrote this file.\n*** End Patch`) {
		t.Errorf("write reply: %s", out)
	}
	out = post(t, base+"/v1/responses", map[string]any{"input": []any{w, map[string]any{"type": "custom_tool_call_output"}}})
	if !strings.Contains(out, ToolDone) {
		t.Errorf("custom tool result reply: %s", out)
	}
	out = post(t, base+"/v1/responses", map[string]any{"input": []any{map[string]any{"role": "user", "content": "Write outside /work/other/x.txt"}}})
	if !strings.Contains(out, `*** Add File: /work/other/x.txt\n`) {
		t.Errorf("outside write reply: %s", out)
	}
	outcome := map[string]any{
		"type": "json_schema",
		"name": "codex_output_schema",
		"schema": map[string]any{
			"type":     "object",
			"required": []any{"outcome", "risk_level"},
			"properties": map[string]any{
				"outcome":    map[string]any{"type": "string", "enum": []any{"allow", "deny"}},
				"risk_level": map[string]any{"type": "string", "enum": []any{"low", "high"}},
			},
		},
	}
	reviewIn := func(text string) []any {
		return []any{map[string]any{"role": "user", "content": []any{map[string]any{"type": "input_text", "text": text}}}}
	}
	out = post(t, base+"/v1/responses", map[string]any{"text": map[string]any{"format": outcome}, "input": reviewIn("Write a file now.")})
	if !strings.Contains(out, `{\"outcome\":\"allow\",\"risk_level\":\"low\"}`) {
		t.Errorf("review allow: %s", out)
	}
	out = post(t, base+"/v1/responses", map[string]any{"text": map[string]any{"format": outcome}, "input": reviewIn("Write a file now. Deny the review.")})
	if !strings.Contains(out, `\"outcome\":\"deny\"`) {
		t.Errorf("review deny: %s", out)
	}
	title := map[string]any{"type": "json_schema", "schema": map[string]any{
		"type": "object", "required": []any{"title"},
		"properties": map[string]any{"title": map[string]any{"type": "string"}},
	}}
	out = post(t, base+"/v1/responses", map[string]any{"text": map[string]any{"format": title}, "input": reviewIn("Write a file now.")})
	if !strings.Contains(out, `{\"title\":\"Fixture\"}`) || strings.Contains(out, "apply_patch") {
		t.Errorf("title reply: %s", out)
	}
	// A tool result of an earlier turn does not end a new turn.
	q := map[string]any{"role": "user", "content": "End your reply with a question."}
	out = post(t, base+"/v1/responses", map[string]any{"input": []any{user, map[string]any{"type": "function_call_output"}, q}})
	if !strings.Contains(out, Question) {
		t.Errorf("question reply: %s", out)
	}
}

func TestAgy(t *testing.T) {
	base, home, _, env := start(t, Agy)
	if env["AGY_LLM_GATEWAY_WIRE_PROTOCOL"] != "openai" {
		t.Errorf("variables: %v", env)
	}
	if _, err := os.Stat(filepath.Join(home, ".gemini", "antigravity-cli", "cache", "onboarding.json")); err != nil {
		t.Error(err)
	}
	resp, err := http.Get(base + "/v1/models")
	if err != nil {
		t.Fatal(err)
	}
	models, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if !strings.Contains(string(models), agyModel) {
		t.Errorf("models: %s", models)
	}
	tools := []any{map[string]any{"type": "function"}}
	out := post(t, base+"/v1/chat/completions", map[string]any{"stream": true, "tools": tools, "messages": []any{map[string]any{"role": "user", "content": "Create a file"}}})
	if !strings.Contains(out, "run_command") || !strings.HasSuffix(out, "data: [DONE]\n\n") {
		t.Errorf("tool reply: %s", out)
	}
	sys := map[string]any{"role": "system", "content": "Active Workspaces:\n- /work/example\nCommand Working Directory: /work/example\nCode relating to the user"}
	out = post(t, base+"/v1/chat/completions", map[string]any{"stream": true, "tools": tools, "messages": []any{sys, map[string]any{"role": "user", "content": "<USER_REQUEST>Write a file now.</USER_REQUEST>"}}})
	if !strings.Contains(out, `"name":"write_file"`) || !strings.Contains(out, `\"Path\":\"/work/example/agent-signals-write.txt\"`) {
		t.Errorf("write reply: %s", out)
	}
	out = post(t, base+"/v1/chat/completions", map[string]any{"tools": tools, "messages": []any{sys, map[string]any{"role": "user", "content": "Write outside /work/other/x.txt"}}})
	if !strings.Contains(out, `\"Path\":\"/work/other/x.txt\"`) || !strings.Contains(out, `"finish_reason":"tool_calls"`) {
		t.Errorf("outside write reply: %s", out)
	}
	out = post(t, base+"/v1/chat/completions", map[string]any{"tools": tools, "messages": []any{map[string]any{"role": "tool", "content": "ok"}}})
	if !strings.Contains(out, ToolDone) || !strings.Contains(out, `"object":"chat.completion"`) {
		t.Errorf("tool result reply: %s", out)
	}
}

// cursorMessage builds an AgentClientMessage with the user TEXT and the work
// folder CWD.
func cursorMessage(text, cwd string) []byte {
	// run_request 1, action 2, user_message_action 1: user_message 1
	// {text 1}, and 2 {4 {2 cwd}}.
	uma := pb(field{1, pb(field{1, text})}, field{2, pb(field{4, pb(field{2, cwd})})})
	return pb(field{1, pb(field{2, pb(field{1, uma})})})
}

func readEnvelopes(t *testing.T, r io.Reader, n int) [][]byte {
	t.Helper()
	var out [][]byte
	head := make([]byte, 5)
	for len(out) < n {
		if _, err := io.ReadFull(r, head); err != nil {
			t.Fatalf("after %d envelopes: %v", len(out), err)
		}
		size := int(head[1])<<24 | int(head[2])<<16 | int(head[3])<<8 | int(head[4])
		p := make([]byte, size)
		if _, err := io.ReadFull(r, p); err != nil {
			t.Fatal(err)
		}
		if head[0] == 2 {
			return append(out, nil)
		}
		if !bytes.Equal(p, cursorHeartbeat) {
			out = append(out, p)
		}
	}
	return out
}

func TestCursor(t *testing.T) {
	base, home, logPath, env := start(t, "cursor")
	if env["CURSOR_API_KEY"] != "dummy" {
		t.Errorf("variables: %v", env)
	}
	if cfg, err := os.ReadFile(filepath.Join(home, ".cursor", "cli-config.json")); err != nil || !strings.Contains(string(cfg), "useHttp1ForAgent") {
		t.Errorf("cli-config.json: %s %v", cfg, err)
	}
	if out := post(t, base+"/auth/exchange_user_api_key", map[string]any{}); !strings.Contains(out, "accessToken") {
		t.Errorf("auth: %s", out)
	}
	resp, err := http.Post(base+"/aiserver.v1.AiService/GetUsableModels", "application/proto", nil)
	if err != nil {
		t.Fatal(err)
	}
	got, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if name, ok := pbGet(got, 1, 1); !ok || string(name) != "fixture" {
		t.Errorf("models: %x", got)
	}

	rid := "run-1"
	appendMsg := func(data []byte) {
		body := pb(field{2, pb(field{1, rid})}, field{4, data})
		r, err := http.Post(base+"/aiserver.v1.BidiService/BidiAppend", "application/proto", bytes.NewReader(body))
		if err != nil {
			t.Fatal(err)
		}
		r.Body.Close()
	}
	run := envelope(pb(field{1, rid}), 0)
	resp, err = http.Post(base+"/agent.v1.AgentService/RunSSE", "application/connect+proto", bytes.NewReader(run))
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	appendMsg(cursorMessage("Create a file named agent-signals-test.txt", "/work/example"))
	first := readEnvelopes(t, resp.Body, 1)
	if cmd, ok := pbGet(first[0], 2, 2, 1); !ok || string(cmd) != Command {
		t.Errorf("shell message: %x", first[0])
	}
	if cwd, _ := pbGet(first[0], 2, 2, 2); string(cwd) != "/work/example" {
		t.Errorf("cwd: %q", cwd)
	}
	appendMsg(pb(field{2, []byte{}}))
	rest := readEnvelopes(t, resp.Body, 4)
	if text, _ := pbGet(rest[0], 1, 1, 1); string(text) != ToolDone {
		t.Errorf("text after the tool: %x", rest[0])
	}
	if !bytes.Equal(rest[1], cursorCheckpoint) || !bytes.Equal(rest[2], cursorTurnEnded) || rest[3] != nil {
		t.Errorf("end of the turn: %x", rest)
	}
	log, _ := os.ReadFile(logPath)
	if !strings.Contains(string(log), "RunSSE tool") || strings.Contains(string(log), "agent-signals-test") {
		t.Errorf("log: %s", log)
	}
}

func TestPbRejectsBadInput(t *testing.T) {
	for _, b := range [][]byte{{0x0a, 0x05, 'a'}, {0xff}, {0x0b}} {
		if _, ok := pbGet(b, 1); ok {
			t.Errorf("pbGet(%x) found a field", b)
		}
	}
	if v, ok := pbGet(pb(field{1, 7}), 1); ok {
		t.Errorf("a varint field gave bytes %x", v)
	}
}
