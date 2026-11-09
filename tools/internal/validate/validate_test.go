package validate

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const goodMeta = `schema: 1
agent: claude
agent_version: 2.1.309
measured: 2026-10-24
capture: plain
pane: {cols: 80, rows: 24}
provenance: measured
expect:
  state: PERMISSION
  dialog: question
  question: Which colour?
  options:
    - {n: 1, label: Red, selected: true}
    - {n: 2, label: Blue}
facts: [1]
`

const goodScreen = " Which colour?\n ❯ 1. Red\n   2. Blue\n\n Esc to cancel\n"

// corpus builds a minimal valid repository in a temporary folder, with the
// real schemas, and returns its root.
func corpus(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	for _, name := range []string{"screen.schema.json", "coverage.schema.json", "trace.schema.json"} {
		data, err := os.ReadFile(filepath.Join("..", "..", "..", "schema", name))
		if err != nil {
			t.Fatal(err)
		}
		write(t, root, "schema/"+name, string(data))
	}
	write(t, root, "facts/001-example-fact.md", "# Example\n")
	write(t, root, "corpus/claude/coverage.yaml", "agent: claude\nverified:\n  - {version: 2.1.309, date: 2026-10-24, method: manual capture}\n")
	write(t, root, "corpus/claude/screens/ask.screen", goodScreen)
	write(t, root, "corpus/claude/screens/ask.yaml", goodMeta)
	return root
}

func write(t *testing.T, root, path, content string) {
	t.Helper()
	full := filepath.Join(root, filepath.FromSlash(path))
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(full, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func check(t *testing.T, root string) []Problem {
	t.Helper()
	problems, err := Check(root)
	if err != nil {
		t.Fatal(err)
	}
	return problems
}

// wantOne asserts exactly one problem, on path, whose message holds want.
func wantOne(t *testing.T, problems []Problem, path, want string) {
	t.Helper()
	if len(problems) != 1 || problems[0].Path != path || !strings.Contains(problems[0].Message, want) {
		t.Fatalf("want one problem on %s with %q, got %v", path, want, problems)
	}
}

func TestAValidCorpusHasNoProblem(t *testing.T) {
	if p := check(t, corpus(t)); len(p) != 0 {
		t.Fatalf("want no problem, got %v", p)
	}
}

func TestTheRepositoryCorpusIsValid(t *testing.T) {
	if p := check(t, filepath.Join("..", "..", "..")); len(p) != 0 {
		t.Fatalf("the corpus of this repository has problems: %v", p)
	}
}

func TestAScreenWithoutMetadataIsAProblem(t *testing.T) {
	root := corpus(t)
	write(t, root, "corpus/claude/screens/lonely.screen", goodScreen)
	wantOne(t, check(t, root), "corpus/claude/screens/lonely.screen", "no lonely.yaml")
}

func TestMetadataWithoutAScreenIsAProblem(t *testing.T) {
	root := corpus(t)
	write(t, root, "corpus/claude/screens/lonely.yaml", goodMeta)
	wantOne(t, check(t, root), "corpus/claude/screens/lonely.yaml", "no lonely.screen")
}

func TestAnUnknownStateFailsTheSchema(t *testing.T) {
	root := corpus(t)
	write(t, root, "corpus/claude/screens/ask.yaml", strings.Replace(goodMeta, "PERMISSION", "WAITING", 1))
	wantOne(t, check(t, root), "corpus/claude/screens/ask.yaml", "schema")
}

func TestAMeasuredEditedScreenNeedsItsEdits(t *testing.T) {
	root := corpus(t)
	write(t, root, "corpus/claude/screens/ask.yaml", strings.Replace(goodMeta, "provenance: measured", "provenance: measured-edited", 1))
	wantOne(t, check(t, root), "corpus/claude/screens/ask.yaml", "schema")
}

func TestOnlyAMeasuredScreenNeedsItsPane(t *testing.T) {
	root := corpus(t)
	noPane := strings.Replace(goodMeta, "pane: {cols: 80, rows: 24}\n", "", 1)
	write(t, root, "corpus/claude/screens/ask.yaml", noPane)
	wantOne(t, check(t, root), "corpus/claude/screens/ask.yaml", "schema")

	edited := strings.Replace(noPane, "provenance: measured", "provenance: measured-edited\nedits: [rule lines shortened]", 1)
	write(t, root, "corpus/claude/screens/ask.yaml", edited)
	if p := check(t, root); len(p) != 0 {
		t.Fatalf("an edited screen with no known pane is valid, got %v", p)
	}
	derived := strings.Replace(noPane, "provenance: measured", "provenance: derived\nderived_from: hand-built", 1)
	write(t, root, "corpus/claude/screens/ask.yaml", derived)
	if p := check(t, root); len(p) != 0 {
		t.Fatalf("a derived screen with no known pane is valid, got %v", p)
	}
}

func TestADerivedScreenMustNameAnExistingSource(t *testing.T) {
	root := corpus(t)
	meta := strings.Replace(goodMeta, "provenance: measured", "provenance: derived\nderived_from: \"missing: one Down\"", 1)
	write(t, root, "corpus/claude/screens/ask.yaml", meta)
	wantOne(t, check(t, root), "corpus/claude/screens/ask.yaml", `"missing"`)

	write(t, root, "corpus/claude/screens/ask.yaml", strings.Replace(meta, "missing", "ask", 1))
	if p := check(t, root); len(p) != 0 {
		t.Fatalf("a source that exists is valid, got %v", p)
	}
	write(t, root, "corpus/claude/screens/ask.yaml", strings.Replace(meta, `"missing: one Down"`, "hand-built", 1))
	if p := check(t, root); len(p) != 0 {
		t.Fatalf("hand-built is valid, got %v", p)
	}
}

func TestAKnownFalsePositiveNeedsAReason(t *testing.T) {
	root := corpus(t)
	write(t, root, "corpus/claude/screens/ask.yaml", goodMeta+"known_false_positive: true\n")
	wantOne(t, check(t, root), "corpus/claude/screens/ask.yaml", "schema")

	write(t, root, "corpus/claude/screens/ask.yaml", goodMeta+"known_false_positive: true\nknown_false_positive_reason: a quoted dialog is read as a dialog, which is safe\n")
	if p := check(t, root); len(p) != 0 {
		t.Fatalf("want no problem, got %v", p)
	}
}

func TestAnAgentThatDiffersFromItsFolderIsAProblem(t *testing.T) {
	root := corpus(t)
	write(t, root, "corpus/claude/screens/ask.yaml", strings.Replace(goodMeta, "agent: claude", "agent: agy", 1))
	wantOne(t, check(t, root), "corpus/claude/screens/ask.yaml", "folder is claude")
}

func TestAMissingFactIsAProblem(t *testing.T) {
	root := corpus(t)
	write(t, root, "corpus/claude/screens/ask.yaml", strings.Replace(goodMeta, "facts: [1]", "facts: [1, 7]", 1))
	wantOne(t, check(t, root), "corpus/claude/screens/ask.yaml", "no 007-*.md")
}

func TestAMissingNegativeControlTargetIsAProblem(t *testing.T) {
	root := corpus(t)
	write(t, root, "corpus/claude/screens/ask.yaml", goodMeta+"negative_control_for: nothing\n")
	wantOne(t, check(t, root), "corpus/claude/screens/ask.yaml", `"nothing"`)
}

func TestScreenBytes(t *testing.T) {
	for name, content := range map[string]string{
		"no trailing newline": strings.TrimSuffix(goodScreen, "\n"),
		"carriage return":     strings.ReplaceAll(goodScreen, "\n", "\r\n"),
		"not valid UTF-8":     "\xff\xfe\n",
		"empty screen":        "",
	} {
		t.Run(name, func(t *testing.T) {
			root := corpus(t)
			write(t, root, "corpus/claude/screens/ask.screen", content)
			wantOne(t, check(t, root), "corpus/claude/screens/ask.screen", name)
		})
	}
}

func TestPrivateTextIsAProblem(t *testing.T) {
	for _, text := range []string{
		"/srv/work/project",
		"/home/someone/code",
		"/Users/someone/code",
		`C:\Users\someone`,
		"https://claude.ai/code/session_0123456789abcdef",
		"host.example.ts.net",
	} {
		t.Run(text, func(t *testing.T) {
			root := corpus(t)
			write(t, root, "corpus/claude/screens/ask.screen", goodScreen+" "+text+"\n")
			wantOne(t, check(t, root), "corpus/claude/screens/ask.screen", "line 6 holds")
		})
	}
}

func TestTheScrubbedPathIsAllowed(t *testing.T) {
	root := corpus(t)
	write(t, root, "corpus/claude/screens/ask.screen", goodScreen+" /work/example\n")
	if p := check(t, root); len(p) != 0 {
		t.Fatalf("want no problem, got %v", p)
	}
}

func TestACoverageFileOfTheWrongAgentIsAProblem(t *testing.T) {
	root := corpus(t)
	write(t, root, "corpus/claude/coverage.yaml", "agent: codex\nverified: []\n")
	wantOne(t, check(t, root), "corpus/claude/coverage.yaml", "folder is claude")
}

// agents holds each folder name that the schemas allow.
var agents = []string{
	"claude", "agy", "codex", "copilot", "gemini", "cursor", "opencode",
	"qwen", "aider", "amp", "goose", "crush", "kimi", "continue", "droid",
	"cline", "kilo", "auggie", "openhands", "opencode2", "kiro", "junie",
	"codebuff", "qoder", "codebuddy", "letta", "neovate", "everycode", "iflow",
	"vibe", "gptme", "interpreter", "grok",
}

func TestEachKnownAgentIsValid(t *testing.T) {
	for _, a := range agents {
		t.Run(a, func(t *testing.T) {
			root := corpus(t)
			write(t, root, "corpus/"+a+"/coverage.yaml", "agent: "+a+"\nverified:\n  - {version: 1.0.0, date: 2026-10-30, method: CI capture}\n")
			write(t, root, "corpus/"+a+"/screens/ask.screen", goodScreen)
			write(t, root, "corpus/"+a+"/screens/ask.yaml", strings.Replace(goodMeta, "agent: claude", "agent: "+a, 1))
			if p := check(t, root); len(p) != 0 {
				t.Fatalf("want no problem, got %v", p)
			}
		})
	}
}

func TestAnUnknownAgentIsAProblem(t *testing.T) {
	root := corpus(t)
	write(t, root, "corpus/nobody/coverage.yaml", "agent: nobody\nverified: []\n")
	write(t, root, "corpus/nobody/screens/ask.screen", goodScreen)
	write(t, root, "corpus/nobody/screens/ask.yaml", strings.Replace(goodMeta, "agent: claude", "agent: nobody", 1))
	p := check(t, root)
	if len(p) != 2 {
		t.Fatalf("want two schema problems, got %v", p)
	}
	for _, q := range p {
		if !strings.Contains(q.Message, "schema") {
			t.Errorf("want a schema problem, got %v", q)
		}
	}
}

// tracesRoot builds a corpus with the trace schema and one trace file from
// testdata/trace under traces/claude/2.1.319/<step>/trace.json.
func tracesRoot(t *testing.T, step, testFile string) (string, string) {
	t.Helper()
	root := corpus(t)
	data, err := os.ReadFile(filepath.Join("..", "..", "testdata", "trace", testFile))
	if err != nil {
		t.Fatal(err)
	}
	path := "traces/claude/2.1.319/" + step + "/trace.json"
	write(t, root, path, string(data))
	return root, path
}

func TestTraces(t *testing.T) {
	t.Run("a valid trace has no problem", func(t *testing.T) {
		root, _ := tracesRoot(t, "permission", "valid.json")
		if p := check(t, root); len(p) != 0 {
			t.Fatalf("want no problem, got %v", p)
		}
	})
	t.Run("a trace without provenance is a problem", func(t *testing.T) {
		root, path := tracesRoot(t, "permission", "no-provenance.json")
		wantOne(t, check(t, root), path, "provenance")
	})
	t.Run("an unknown event kind fails the schema", func(t *testing.T) {
		root, path := tracesRoot(t, "question", "bad-kind.json")
		wantOne(t, check(t, root), path, "schema:")
	})
	t.Run("a measured-edited trace needs one edits line", func(t *testing.T) {
		root, path := tracesRoot(t, "permission", "valid.json")
		data, _ := os.ReadFile(filepath.Join(root, path))
		write(t, root, path, strings.Replace(string(data), `"measured"`, `"measured-edited"`, 1))
		wantOne(t, check(t, root), path, "edits")
	})
	t.Run("a terminal cast is allowed at the step folder", func(t *testing.T) {
		root, _ := tracesRoot(t, "permission", "valid.json")
		write(t, root, "traces/claude/2.1.319/permission/terminal.cast", "{\"version\": 2}\n")
		if p := check(t, root); len(p) != 0 {
			t.Fatalf("want no problem, got %v", p)
		}
	})
	t.Run("private text in a trace is a problem", func(t *testing.T) {
		root, path := tracesRoot(t, "permission", "valid.json")
		data, _ := os.ReadFile(filepath.Join(root, path))
		write(t, root, path, strings.Replace(string(data), "WORK/note.txt", "/srv/work/note.txt", 1))
		if p := check(t, root); len(p) == 0 || p[0].Path != path || !strings.Contains(p[0].Message, "/srv/") {
			t.Fatalf("want a private-text problem on %s, got %v", path, p)
		}
	})
	t.Run("another file is a problem", func(t *testing.T) {
		root, _ := tracesRoot(t, "permission", "valid.json")
		write(t, root, "traces/x.txt", "x\n")
		wantOne(t, check(t, root), "traces/x.txt", "unexpected file")
	})
	t.Run("a file at the wrong depth is a problem", func(t *testing.T) {
		root, _ := tracesRoot(t, "permission", "valid.json")
		write(t, root, "traces/claude/trace.json", "{}\n")
		wantOne(t, check(t, root), "traces/claude/trace.json", "unexpected file")
	})
}
