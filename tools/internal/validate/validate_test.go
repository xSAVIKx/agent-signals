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
	for _, name := range []string{"screen.schema.json", "coverage.schema.json"} {
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
	"cline", "kilo", "auggie", "openhands",
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
