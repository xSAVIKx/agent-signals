package site

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"go.yaml.in/yaml/v3"
)

// Screen is one screen of the corpus: the metadata and the exact bytes.
type Screen struct {
	Agent     string
	Slug      string
	Meta      ScreenMeta
	Bytes     []byte
	MetaBytes []byte
}

// ScreenMeta holds the fields of a screen .yaml file. docs/format.md and
// schema/screen.schema.json define them.
type ScreenMeta struct {
	Schema                   int      `yaml:"schema"`
	Agent                    string   `yaml:"agent"`
	AgentVersion             string   `yaml:"agent_version"`
	ValidFrom                string   `yaml:"valid_from"`
	SupersededBy             string   `yaml:"superseded_by"`
	Measured                 string   `yaml:"measured"`
	Capture                  string   `yaml:"capture"`
	Pane                     *Pane    `yaml:"pane"`
	Provenance               string   `yaml:"provenance"`
	Edits                    []string `yaml:"edits"`
	DerivedFrom              string   `yaml:"derived_from"`
	Description              string   `yaml:"description"`
	Expect                   Expect   `yaml:"expect"`
	NegativeControlFor       string   `yaml:"negative_control_for"`
	KnownFalsePositive       bool     `yaml:"known_false_positive"`
	KnownFalsePositiveReason string   `yaml:"known_false_positive_reason"`
	Facts                    []int    `yaml:"facts"`
}

// Pane is the size of the tmux pane.
type Pane struct {
	Cols int `yaml:"cols"`
	Rows int `yaml:"rows"`
}

// Expect is the result that a reader must give for the screen.
type Expect struct {
	State    string   `yaml:"state"`
	Dialog   string   `yaml:"dialog"`
	Question string   `yaml:"question"`
	Shape    string   `yaml:"shape"`
	Options  []Option `yaml:"options"`
	BoxText  *string  `yaml:"box_text"`
}

// Option is one option of a dialog.
type Option struct {
	N        int    `yaml:"n"`
	Label    string `yaml:"label"`
	Selected bool   `yaml:"selected"`
}

// Key gives the reference of the screen, "agent/slug".
func (s Screen) Key() string { return s.Agent + "/" + s.Slug }

// Agent is one folder of corpus/.
type Agent struct {
	Name     string // the folder name
	Display  string
	Coverage []Coverage
	Screens  []Screen
}

// Coverage is one verified version in coverage.yaml.
type Coverage struct {
	Version string `yaml:"version" json:"version"`
	Date    string `yaml:"date" json:"date,omitempty"`
	Method  string `yaml:"method" json:"method,omitempty"`
	Notes   string `yaml:"notes" json:"notes,omitempty"`
}

// LoadCorpus reads every agent folder of corpus/ in name order, and every
// screen of each agent in slug order.
func LoadCorpus(root string) ([]Agent, error) {
	dirs, err := os.ReadDir(filepath.Join(root, "corpus"))
	if err != nil {
		return nil, err
	}
	var agents []Agent
	for _, d := range dirs {
		if !d.IsDir() {
			continue
		}
		a := Agent{Name: d.Name(), Display: agentDisplay[d.Name()]}
		if a.Display == "" {
			a.Display = d.Name()
		}
		cov, err := os.ReadFile(filepath.Join(root, "corpus", a.Name, "coverage.yaml"))
		if err == nil {
			var c struct {
				Verified []Coverage `yaml:"verified"`
			}
			if err := yaml.Unmarshal(cov, &c); err != nil {
				return nil, fmt.Errorf("corpus/%s/coverage.yaml: %w", a.Name, err)
			}
			a.Coverage = c.Verified
		}
		files, err := filepath.Glob(filepath.Join(root, "corpus", a.Name, "screens", "*.yaml"))
		if err != nil {
			return nil, err
		}
		sort.Strings(files)
		for _, f := range files {
			slug := strings.TrimSuffix(filepath.Base(f), ".yaml")
			s := Screen{Agent: a.Name, Slug: slug}
			if s.MetaBytes, err = os.ReadFile(f); err != nil {
				return nil, err
			}
			if err := yaml.Unmarshal(s.MetaBytes, &s.Meta); err != nil {
				return nil, fmt.Errorf("corpus/%s/screens/%s.yaml: %w", a.Name, slug, err)
			}
			if s.Bytes, err = os.ReadFile(strings.TrimSuffix(f, ".yaml") + ".screen"); err != nil {
				return nil, err
			}
			a.Screens = append(a.Screens, s)
		}
		agents = append(agents, a)
	}
	return agents, nil
}

// ScreenText gives the text of a screen for a <pre> element. Each byte stays
// as it is, except a control character other than a line feed or a tab: HTML
// cannot hold it, so it becomes the visible Unicode control picture, for
// example U+241B for ESC. The second result tells if a byte changed.
func ScreenText(b []byte) (string, bool) {
	changed := false
	var sb strings.Builder
	sb.Grow(len(b))
	for _, c := range b {
		switch {
		case c == '\n' || c == '\t':
			sb.WriteByte(c)
		case c < 0x20:
			sb.WriteRune(rune(0x2400 + int(c)))
			changed = true
		case c == 0x7f:
			sb.WriteRune(0x2421)
			changed = true
		default:
			sb.WriteByte(c)
		}
	}
	return sb.String(), changed
}

// Facet is one filter of the corpus page: a <select> with its options.
type Facet struct {
	Key     string // the data-* name and the query parameter
	Label   string
	Options []FacetOption
}

// FacetOption is one value of a facet. Value is what the rows carry.
type FacetOption struct {
	Value string
	Label string
}

// DialogNone is the value of the dialog facet for a screen without a dialog.
const DialogNone = "none"

// DialogValue gives the value of the dialog facet for a screen.
func (s Screen) DialogValue() string {
	if s.Meta.Expect.Dialog == "" {
		return DialogNone
	}
	return s.Meta.Expect.Dialog
}

// corpusFacets reads the values of the five facets from the screens, in sorted
// order. The agent facet keeps the display name.
func corpusFacets(agents []Agent) []Facet {
	seen := map[string]map[string]bool{}
	for _, k := range []string{"state", "dialog", "version", "provenance"} {
		seen[k] = map[string]bool{}
	}
	var agentOpts []FacetOption
	for _, a := range agents {
		if len(a.Screens) == 0 {
			continue
		}
		agentOpts = append(agentOpts, FacetOption{a.Name, a.Display})
		for _, s := range a.Screens {
			seen["state"][s.Meta.Expect.State] = true
			seen["dialog"][s.DialogValue()] = true
			seen["version"][s.Meta.AgentVersion] = true
			seen["provenance"][s.Meta.Provenance] = true
		}
	}
	options := func(k string) []FacetOption {
		var vals []string
		for v := range seen[k] {
			vals = append(vals, v)
		}
		sort.Strings(vals)
		var out []FacetOption
		for _, v := range vals {
			out = append(out, FacetOption{v, v})
		}
		return out
	}
	return []Facet{
		{"agent", "Agent", agentOpts},
		{"state", "State", options("state")},
		{"dialog", "Dialog", options("dialog")},
		{"version", "Agent version", options("version")},
		{"provenance", "Provenance", options("provenance")},
	}
}
