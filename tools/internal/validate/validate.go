// Package validate checks the corpus: the schema of each metadata file, the
// pairs of screen files, the references between screens and facts, the bytes
// of each screen, and text that must not be published.
package validate

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/santhosh-tekuri/jsonschema/v6"
	"go.yaml.in/yaml/v3"
)

// Problem is one defect in the corpus. Path is relative to the repository root.
type Problem struct {
	Path    string
	Message string
}

func (p Problem) String() string { return p.Path + ": " + p.Message }

// handBuilt is the derived_from value of a screen that has no source screen.
const handBuilt = "hand-built"

// private holds text that must not be published: host paths, account homes,
// session addresses and tailnet names. A screen uses /work/example instead.
// A match counts only when it also matches need, when need is set.
var private = []struct {
	re   *regexp.Regexp
	need *regexp.Regexp
	what string
}{
	{regexp.MustCompile(`/srv/`), nil, "a host path (/srv/)"},
	{regexp.MustCompile(`/home/[A-Za-z0-9_.-]+`), nil, "a home folder (/home/<user>)"},
	{regexp.MustCompile(`/var/lib/`), nil, "a host path (/var/lib/)"},
	{regexp.MustCompile(`/Users/[A-Za-z0-9_.-]+`), nil, "a home folder (/Users/<user>)"},
	{regexp.MustCompile(`(?i)[A-Z]:\\Users\\`), nil, `a home folder (C:\Users\)`},
	{regexp.MustCompile(`/tmp/claude-[0-9]+`), nil, "a session scratch path"},
	// A session address holds digits. A word such as session_persistence
	// (a file name in the plugin marketplace of Claude Code) does not.
	{regexp.MustCompile(`session_[A-Za-z0-9]{8,}`), regexp.MustCompile(`[0-9]`), "a session address"},
	{regexp.MustCompile(`\.ts\.net\b`), nil, "a tailnet name"},
}

// Check validates the corpus under root and returns every problem it finds,
// sorted by path. An empty result means the corpus is valid.
func Check(root string) ([]Problem, error) {
	screenSchema, err := compile(root, "screen.schema.json")
	if err != nil {
		return nil, err
	}
	coverageSchema, err := compile(root, "coverage.schema.json")
	if err != nil {
		return nil, err
	}
	traceSchema, err := compile(root, "trace.schema.json")
	if err != nil {
		return nil, err
	}
	facts, err := factNumbers(root)
	if err != nil {
		return nil, err
	}

	var problems []Problem
	add := func(path, format string, args ...any) {
		problems = append(problems, Problem{Path: path, Message: fmt.Sprintf(format, args...)})
	}

	agents, err := os.ReadDir(filepath.Join(root, "corpus"))
	if err != nil {
		return nil, err
	}
	for _, a := range agents {
		if !a.IsDir() {
			add(rel("corpus", a.Name()), "unexpected file; corpus/ holds one folder per agent")
			continue
		}
		agent := a.Name()
		checkCoverage(root, agent, coverageSchema, add)
		checkScreens(root, agent, screenSchema, facts, add)
	}

	checkTraces(root, traceSchema, add)

	sort.Slice(problems, func(i, j int) bool {
		if problems[i].Path != problems[j].Path {
			return problems[i].Path < problems[j].Path
		}
		return problems[i].Message < problems[j].Message
	})
	return problems, nil
}

type addFunc func(path, format string, args ...any)

func checkCoverage(root, agent string, schema *jsonschema.Schema, add addFunc) {
	path := rel("corpus", agent, "coverage.yaml")
	doc, err := loadYAML(filepath.Join(root, path))
	if err != nil {
		add(path, "%v", err)
		return
	}
	if err := schema.Validate(doc); err != nil {
		add(path, "schema: %v", oneLine(err))
		return
	}
	if got := doc.(map[string]any)["agent"]; got != agent {
		add(path, "agent is %v, but the folder is %s", got, agent)
	}
}

func checkScreens(root, agent string, schema *jsonschema.Schema, facts map[int]bool, add addFunc) {
	dir := rel("corpus", agent, "screens")
	entries, err := os.ReadDir(filepath.Join(root, dir))
	if err != nil {
		add(dir, "%v", err)
		return
	}

	screens := map[string]bool{}
	metas := map[string]bool{}
	for _, e := range entries {
		name := e.Name()
		switch {
		case name == ".gitkeep":
		case e.IsDir():
			add(rel(dir, name), "unexpected folder")
		case strings.HasSuffix(name, ".screen"):
			screens[strings.TrimSuffix(name, ".screen")] = true
		case strings.HasSuffix(name, ".yaml"):
			metas[strings.TrimSuffix(name, ".yaml")] = true
		default:
			add(rel(dir, name), "unexpected file; a screen is <slug>.screen and <slug>.yaml")
		}
	}

	for slug := range screens {
		if !metas[slug] {
			add(rel(dir, slug+".screen"), "no %s.yaml beside it", slug)
		}
		checkBytes(root, rel(dir, slug+".screen"), add)
	}
	for slug := range metas {
		if !screens[slug] {
			add(rel(dir, slug+".yaml"), "no %s.screen beside it", slug)
		}
		checkMeta(root, rel(dir, slug+".yaml"), agent, schema, screens, facts, add)
	}
}

// checkTraces validates traces/ when it exists. A file is trace.json or
// terminal.cast at depth AGENT/VERSION/STEP/. Each trace.json must follow the
// schema, name its provenance, and list its edits when it is measured-edited.
func checkTraces(root string, schema *jsonschema.Schema, add addFunc) {
	base := filepath.Join(root, "traces")
	if _, err := os.Stat(base); err != nil {
		if !os.IsNotExist(err) {
			add("traces", "%v", err)
		}
		return
	}
	err := filepath.WalkDir(base, func(full string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		r, _ := filepath.Rel(root, full)
		path := filepath.ToSlash(r)
		if d.IsDir() {
			return nil
		}
		parts := strings.Split(path, "/")
		name := d.Name()
		if len(parts) != 5 || (name != "trace.json" && name != "terminal.cast") {
			add(path, "unexpected file; traces/ holds AGENT/VERSION/STEP/trace.json and terminal.cast")
			return nil
		}
		data, err := os.ReadFile(full)
		if err != nil {
			add(path, "%v", err)
			return nil
		}
		checkPrivate(path, data, add)
		if name == "trace.json" {
			checkTrace(path, data, schema, add)
		}
		return nil
	})
	if err != nil {
		add("traces", "%v", err)
	}
}

func checkTrace(path string, data []byte, schema *jsonschema.Schema, add addFunc) {
	doc, err := jsonschema.UnmarshalJSON(bytes.NewReader(data))
	if err != nil {
		add(path, "json: %v", err)
		return
	}
	if err := schema.Validate(doc); err != nil {
		add(path, "schema: %v", oneLine(err))
		return
	}
	m := doc.(map[string]any)
	prov, ok := m["provenance"].(string)
	if !ok {
		add(path, "no provenance; the kit writes \"measured\"")
		return
	}
	if edits, _ := m["edits"].([]any); prov == "measured-edited" && len(edits) == 0 {
		add(path, "provenance is measured-edited, but edits has no line")
	}
}

func checkBytes(root, path string, add addFunc) {
	data, err := os.ReadFile(filepath.Join(root, path))
	if err != nil {
		add(path, "%v", err)
		return
	}
	switch {
	case len(data) == 0:
		add(path, "empty screen")
	case !utf8.Valid(data):
		add(path, "not valid UTF-8")
	case bytes.Contains(data, []byte("\r")):
		add(path, "holds a carriage return; a screen uses LF line endings")
	case data[len(data)-1] != '\n':
		add(path, "no trailing newline; capture-pane -p ends each screen with one")
	}
	checkPrivate(path, data, add)
}

func checkMeta(root, path, agent string, schema *jsonschema.Schema, screens map[string]bool, facts map[int]bool, add addFunc) {
	data, err := os.ReadFile(filepath.Join(root, path))
	if err != nil {
		add(path, "%v", err)
		return
	}
	checkPrivate(path, data, add)

	doc, err := parseYAML(data)
	if err != nil {
		add(path, "%v", err)
		return
	}
	if err := schema.Validate(doc); err != nil {
		add(path, "schema: %v", oneLine(err))
		return
	}
	m := doc.(map[string]any)

	if m["agent"] != agent {
		add(path, "agent is %v, but the folder is %s", m["agent"], agent)
	}
	if src, ok := m["derived_from"].(string); ok && src != handBuilt {
		// derived_from starts with the source slug, then says what changed.
		slug := strings.FieldsFunc(src, func(r rune) bool { return r == ' ' || r == ':' || r == ',' })[0]
		if !screens[slug] {
			add(path, "derived_from names %q, which is not a screen of %s; use %q for a screen with no source", slug, agent, handBuilt)
		}
	}
	for _, key := range []string{"negative_control_for", "superseded_by"} {
		if slug, ok := m[key].(string); ok && !screens[slug] {
			add(path, "%s names %q, which is not a screen of %s", key, slug, agent)
		}
	}
	if list, ok := m["facts"].([]any); ok {
		for _, f := range list {
			n, err := f.(json.Number).Int64()
			if err == nil && !facts[int(n)] {
				add(path, "facts names %d, but facts/ has no %03d-*.md", n, n)
			}
		}
	}
}

func checkPrivate(path string, data []byte, add addFunc) {
	for _, p := range private {
		for _, loc := range p.re.FindAllIndex(data, -1) {
			if p.need != nil && !p.need.Match(data[loc[0]:loc[1]]) {
				continue
			}
			line := bytes.Count(data[:loc[0]], []byte("\n")) + 1
			add(path, "line %d holds %s; scrub it (paths use /work/example)", line, p.what)
			break
		}
	}
}

var factName = regexp.MustCompile(`^([0-9]{3})-[a-z0-9-]+\.md$`)

// factNumbers returns the numbers of the fact files in facts/.
func factNumbers(root string) (map[int]bool, error) {
	entries, err := os.ReadDir(filepath.Join(root, "facts"))
	if err != nil {
		return nil, err
	}
	out := map[int]bool{}
	for _, e := range entries {
		if m := factName.FindStringSubmatch(e.Name()); m != nil {
			var n int
			fmt.Sscanf(m[1], "%d", &n)
			out[n] = true
		}
	}
	return out, nil
}

func compile(root, name string) (*jsonschema.Schema, error) {
	path := filepath.Join(root, "schema", name)
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	doc, err := jsonschema.UnmarshalJSON(f)
	if err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	c := jsonschema.NewCompiler()
	c.AssertFormat()
	if err := c.AddResource(name, doc); err != nil {
		return nil, err
	}
	return c.Compile(name)
}

func loadYAML(path string) (any, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	return parseYAML(data)
}

// parseYAML decodes YAML into the JSON value model that the schema
// validator expects: maps with string keys, json.Number numbers, and dates as
// strings.
func parseYAML(data []byte) (any, error) {
	var v any
	if err := yaml.Unmarshal(data, &v); err != nil {
		return nil, fmt.Errorf("yaml: %w", err)
	}
	j, err := json.Marshal(toJSON(v))
	if err != nil {
		return nil, err
	}
	return jsonschema.UnmarshalJSON(bytes.NewReader(j))
}

func toJSON(v any) any {
	switch t := v.(type) {
	case map[string]any:
		for k, e := range t {
			t[k] = toJSON(e)
		}
		return t
	case []any:
		for i, e := range t {
			t[i] = toJSON(e)
		}
		return t
	case time.Time:
		return t.Format("2006-01-02")
	default:
		return v
	}
}

func rel(parts ...string) string { return filepath.ToSlash(filepath.Join(parts...)) }

func oneLine(err error) string {
	return strings.Join(strings.Fields(err.Error()), " ")
}
