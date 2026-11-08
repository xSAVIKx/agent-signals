// Package fakemodel is a local fake model for test sessions of agent CLIs.
//
// It lets the real Codex CLI, Claude Code, agy and the Cursor CLI run a test
// session with no login, no network and no cost. It serves the API of one
// agent on 127.0.0.1 with fixed answers. No model decides anything, so a run
// measures the agent and its screens, not the behaviour of a model. It is the
// Go form of probes/agent/fake-model.py and gives the same answers.
//
// Run binds a free port, writes the settings files of the agent in
// Options.Home (a throwaway home), and then writes Options.EnvFile: one
// KEY=VALUE line for each environment variable that the agent needs. A caller
// waits for that file. Run serves until its context ends, or for
// Options.Lifetime (default 30 minutes). Options.Log gets one line for each
// request, with no request text.
//
//   - codex: the Responses API. HOME/.codex/config.toml names the fake
//     provider.
//   - claude: the Messages API, from ANTHROPIC_BASE_URL.
//     HOME/.claude/.claude.json marks the first-start screens as done and
//     approves the fake key. HOME/.claude/settings.json sets the "default"
//     permission mode.
//   - agy: the Chat Completions API, from AGY_LLM_GATEWAY_URL. agy shows a
//     gateway terms page on a new home.
//     HOME/.gemini/antigravity-cli/cache/onboarding.json marks it as done.
//     That page applies to a real gateway; this fake gateway has no account
//     and no terms.
//   - cursor-agent: the Connect RPC API of the Cursor CLI, from
//     CURSOR_API_ENDPOINT. It is not a public API: the field numbers come
//     from the client CursorClientVersion, and a new client can change them.
//     HOME/.cursor/cli-config.json selects HTTP/1.1 for the agent stream.
//
// The answer depends on the last user message of a request with tools. See
// the Trigger constants. A request with no tools (a title or a summary) gets a
// text reply.
package fakemodel

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
)

// The texts that select an answer. The server looks for each text in the last
// user message, in this order. Other text gets the reply Text. cursor-agent
// gets the reply Text for TriggerWrite and TriggerWriteOutside.
const (
	// TriggerHold: no reply. The turn stays busy until the client ends it,
	// or for 2 minutes.
	TriggerHold = "Count from"
	// TriggerTool: a shell command that needs an approval (Command), then
	// the reply ToolDone after the tool result.
	TriggerTool = "Create a file"
	// TriggerWrite: one call of the file-write tool of the agent for the
	// file WriteFile in the work folder, then the reply ToolDone after the
	// tool result. Claude Code gets Write, Codex gets apply_patch, agy gets
	// write_file. Claude Code and agy need an absolute path: the server reads
	// the work folder from the system prompt.
	TriggerWrite = "Write a file"
	// TriggerWriteOutside: the same call for the absolute path that follows
	// this text in the message, for example "Write outside /work/x.txt". A
	// message with no absolute path gets the reply NoPath.
	TriggerWriteOutside = "Write outside"
	// TriggerChoice: Claude Code gets an AskUserQuestion call with the two
	// options "Red" and "Blue", then the reply ToolDone after the answer.
	// The other agents have no choice tool and get the reply Question.
	TriggerChoice = "Let me choose"
	// TriggerQuestion: a text reply that ends with a question (Question).
	TriggerQuestion = "End your reply with a question"
)

// The fixed texts of the answers.
const (
	Command   = "touch agent-signals-test.txt"
	Text      = "The fixture has no more to say."
	ToolDone  = "The fixture finished the tool call."
	Question  = "The fixture has one question. Do you want to go on?"
	WriteFile = "agent-signals-write.txt"
	WriteText = "The fixture wrote this file.\n"
	NoPath    = "The fixture found no absolute path after \"Write outside\"."
)

// CursorClientVersion is the Cursor CLI version that gave the field numbers of
// the Cursor protocol in this package (agent-signals fact 78).
const CursorClientVersion = "2026.11.05-86047df"

// The agent names. CursorAgent also accepts "cursor" and "agent".
const (
	Codex       = "codex"
	Claude      = "claude"
	Agy         = "agy"
	CursorAgent = "cursor-agent"
)

const (
	defaultLifetime = 30 * time.Minute
	holdTime        = 2 * time.Minute
	keyVariable     = "AGENT_SIGNALS_FAKE_KEY"
	// Claude Code shows the last 20 characters of a key in its approval list.
	claudeKey = "sk-ant-api03-agent-signals-fixture-key-0000"
	agyModel  = "fixture-model"
)

// Options of Run.
type Options struct {
	Agent    string        // codex, claude, agy or cursor-agent
	Home     string        // the throwaway home of the test session
	EnvFile  string        // Run writes the variables here when it serves
	Log      string        // the log file; Run appends one line per request
	PIDFile  string        // optional: Run writes the process ID here
	Lifetime time.Duration // 0 means 30 minutes
}

// Agent returns the agent name for NAME, or an error for an unknown name.
// "cursor" and "agent" give CursorAgent.
func Agent(name string) (string, error) {
	switch name {
	case Codex, Claude, Agy, CursorAgent:
		return name, nil
	case "cursor", "agent":
		return CursorAgent, nil
	}
	return "", fmt.Errorf("unknown agent %q: use codex, claude, agy or cursor-agent", name)
}

// Run serves the fake model of one agent until ctx ends or the lifetime ends.
// It returns nil then. It returns an error when it cannot start.
func Run(ctx context.Context, o Options) error {
	agent, err := Agent(o.Agent)
	if err != nil {
		return err
	}
	if o.Home == "" || o.EnvFile == "" || o.Log == "" {
		return errors.New("fakemodel: Home, EnvFile and Log are required")
	}
	lifetime := o.Lifetime
	if lifetime <= 0 {
		lifetime = defaultLifetime
	}
	logFile, err := os.OpenFile(o.Log, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
	if err != nil {
		return err
	}
	defer logFile.Close()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return err
	}
	if o.PIDFile != "" {
		if err := os.WriteFile(o.PIDFile, []byte(strconv.Itoa(os.Getpid())), 0o600); err != nil {
			ln.Close()
			return err
		}
	}
	port := ln.Addr().(*net.TCPAddr).Port
	env, err := prepare(agent, o.Home, port)
	if err != nil {
		ln.Close()
		return err
	}
	var b strings.Builder
	for _, kv := range env {
		b.WriteString(kv[0] + "=" + kv[1] + "\n")
	}
	if err := writeFile(o.EnvFile, b.String()); err != nil {
		ln.Close()
		return err
	}
	s := newServer(agent, logFile)
	srv := &http.Server{Handler: s, ReadHeaderTimeout: 30 * time.Second}
	ctx, cancel := context.WithTimeout(ctx, lifetime)
	defer cancel()
	done := make(chan error, 1)
	go func() { done <- srv.Serve(ln) }()
	select {
	case <-ctx.Done():
		srv.Close()
		<-done
		return nil
	case err := <-done:
		return err
	}
}

// writeFile writes TEXT to PATH through a new file and a rename.
func writeFile(path, text string) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	if err := os.WriteFile(path+".new", []byte(text), 0o600); err != nil {
		return err
	}
	return os.Rename(path+".new", path)
}

func jsonText(v any) string {
	b, _ := json.MarshalIndent(v, "", "  ")
	return string(b) + "\n"
}

// codexConfig has no "model" line: a name that Codex does not know makes it
// swap the model at start, and the swap loses a prompt.
const codexConfig = `model_provider = "fixture"
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
base_url = "http://127.0.0.1:%d/v1"
env_key = "%s"
wire_api = "responses"
supports_websockets = false
requires_openai_auth = false
request_max_retries = 0
stream_max_retries = 0
`

// prepare writes the settings files of AGENT in HOME and returns the
// variables.
func prepare(agent, home string, port int) ([][2]string, error) {
	base := fmt.Sprintf("http://127.0.0.1:%d", port)
	switch agent {
	case Codex:
		dir := filepath.Join(home, ".codex")
		if err := writeFile(filepath.Join(dir, "config.toml"), fmt.Sprintf(codexConfig, port, keyVariable)); err != nil {
			return nil, err
		}
		return [][2]string{{keyVariable, "dummy"}, {"CODEX_HOME", dir}}, nil
	case Claude:
		conf := filepath.Join(home, ".claude")
		state := map[string]any{
			"hasCompletedOnboarding":   true,
			"theme":                    "dark",
			"hasSeenAutoDefaultNotice": true,
			"hasSeenAutoDefaultNudge":  true,
			"customApiKeyResponses": map[string]any{
				"approved": []string{claudeKey[len(claudeKey)-20:]},
				"rejected": []string{},
			},
		}
		if err := writeFile(filepath.Join(conf, ".claude.json"), jsonText(state)); err != nil {
			return nil, err
		}
		settings := map[string]any{"permissions": map[string]any{"defaultMode": "default"}}
		if err := writeFile(filepath.Join(conf, "settings.json"), jsonText(settings)); err != nil {
			return nil, err
		}
		return [][2]string{
			{"CLAUDE_CONFIG_DIR", conf},
			{"ANTHROPIC_BASE_URL", base},
			{"ANTHROPIC_API_KEY", claudeKey},
			{"CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC", "1"},
			{"DISABLE_AUTOUPDATER", "1"},
		}, nil
	case CursorAgent:
		// Without HTTP/1.1 the agent stream needs HTTP/2, and the client
		// shows "Reconnecting".
		cfg := map[string]any{"version": 1, "network": map[string]any{"useHttp1ForAgent": true}}
		if err := writeFile(filepath.Join(home, ".cursor", "cli-config.json"), jsonText(cfg)); err != nil {
			return nil, err
		}
		return [][2]string{{"CURSOR_API_ENDPOINT", base}, {"CURSOR_API_KEY", "dummy"}}, nil
	}
	onb := map[string]any{
		"consumerOnboardingComplete":   false,
		"enterpriseOnboardingComplete": true,
		"onboardingComplete":           false,
	}
	if err := writeFile(filepath.Join(home, ".gemini", "antigravity-cli", "cache", "onboarding.json"), jsonText(onb)); err != nil {
		return nil, err
	}
	return [][2]string{
		{"AGY_LLM_GATEWAY_URL", base + "/v1"},
		{"AGY_LLM_GATEWAY_API_KEY", "dummy"},
		{"AGY_LLM_GATEWAY_WIRE_PROTOCOL", "openai"},
		{"AGY_CLI_DISABLE_AUTO_UPDATE", "1"},
	}, nil
}

// server is the HTTP handler of one agent.
type server struct {
	agent string
	mu    sync.Mutex
	log   *os.File
	count int
	runs  *cursorRuns
}

func newServer(agent string, log *os.File) *server {
	return &server{agent: agent, log: log, runs: newCursorRuns()}
}

func (s *server) note(format string, a ...any) {
	s.mu.Lock()
	defer s.mu.Unlock()
	fmt.Fprintf(s.log, format+"\n", a...)
}

func (s *server) nextID() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.count++
	return "fixture-" + strconv.Itoa(s.count)
}

func sendJSON(w http.ResponseWriter, code int, v any) {
	b, _ := json.Marshal(v)
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Content-Length", strconv.Itoa(len(b)))
	w.WriteHeader(code)
	w.Write(b)
}

func (s *server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodHead:
		s.note("HEAD %s", r.URL.RequestURI())
		w.Header().Set("Content-Length", "0")
		w.WriteHeader(http.StatusOK)
	case http.MethodGet:
		s.note("GET %s", r.URL.RequestURI())
		switch {
		case !strings.Contains(r.URL.RequestURI(), "models"):
			sendJSON(w, http.StatusNotFound, map[string]any{})
		case s.agent == Agy:
			model := map[string]any{"id": agyModel, "object": "model", "created": 0, "owned_by": "kit"}
			sendJSON(w, http.StatusOK, map[string]any{"object": "list", "data": []any{model}})
		default:
			sendJSON(w, http.StatusOK, map[string]any{"data": []any{}, "models": []any{}})
		}
	case http.MethodPost:
		if s.agent == CursorAgent {
			s.cursorPost(w, r)
			return
		}
		s.post(w, r)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

// hold keeps a busy turn: it returns when the client closes the connection,
// or after the hold time.
func hold(r *http.Request) {
	t := time.NewTimer(holdTime)
	defer t.Stop()
	select {
	case <-r.Context().Done():
	case <-t.C:
	}
}
