// Package agentsignals loads the agent-signals corpus: measured terminal
// screens of AI coding agents, with the result that a reader must give for
// each screen.
//
// The corpus is embedded in the package, so a program needs no file at run
// time. The embedded copy is in the data folder. A test fails when that copy
// differs from the corpus of the repository.
package agentsignals

import (
	"embed"
	"fmt"
	"io/fs"
	"path"
	"sort"
	"strings"

	"go.yaml.in/yaml/v3"
)

// SchemaVersion is the version of the screen schema that this package reads.
const SchemaVersion = 1

//go:generate sh ../tools/sync-go-data.sh

//go:embed all:data
var data embed.FS

// Pane is the size of the tmux pane of a capture.
type Pane struct {
	Cols int
	Rows int
}

// Option is one choice of a menu on a screen. N is 0 when the menu has no
// numbers.
type Option struct {
	N        int
	Label    string
	Selected bool
}

// Expect is the result that a reader must give for a screen.
type Expect struct {
	State    string
	Dialog   string
	Question string
	Options  []Option
	// BoxText is nil when the screen does not pin the text of the input box.
	// It points to an empty string when the box is empty.
	BoxText *string
}

// Screen is one measured screen with its metadata.
type Screen struct {
	Agent                    string
	Slug                     string
	AgentVersion             string
	Measured                 string
	Capture                  string
	Pane                     *Pane
	Provenance               string
	Edits                    []string
	DerivedFrom              string
	Description              string
	Expect                   Expect
	NegativeControlFor       string
	KnownFalsePositive       bool
	KnownFalsePositiveReason string
	Facts                    []int
	// Bytes holds the exact content of the .screen file.
	Bytes []byte
}

// Verified is one agent version that was checked against the corpus.
type Verified struct {
	Version string
	Date    string
	Method  string
	Notes   string
}

type screenFile struct {
	Schema       int    `yaml:"schema"`
	Agent        string `yaml:"agent"`
	AgentVersion string `yaml:"agent_version"`
	Measured     string `yaml:"measured"`
	Capture      string `yaml:"capture"`
	Pane         *struct {
		Cols int `yaml:"cols"`
		Rows int `yaml:"rows"`
	} `yaml:"pane"`
	Provenance  string   `yaml:"provenance"`
	Edits       []string `yaml:"edits"`
	DerivedFrom string   `yaml:"derived_from"`
	Description string   `yaml:"description"`
	Expect      struct {
		State    string `yaml:"state"`
		Dialog   string `yaml:"dialog"`
		Question string `yaml:"question"`
		Options  []struct {
			N        int    `yaml:"n"`
			Label    string `yaml:"label"`
			Selected bool   `yaml:"selected"`
		} `yaml:"options"`
		BoxText *string `yaml:"box_text"`
	} `yaml:"expect"`
	NegativeControlFor       string `yaml:"negative_control_for"`
	KnownFalsePositive       bool   `yaml:"known_false_positive"`
	KnownFalsePositiveReason string `yaml:"known_false_positive_reason"`
	Facts                    []int  `yaml:"facts"`
}

type coverageFile struct {
	Agent    string `yaml:"agent"`
	Verified []struct {
		Version string `yaml:"version"`
		Date    string `yaml:"date"`
		Method  string `yaml:"method"`
		Notes   string `yaml:"notes"`
	} `yaml:"verified"`
}

// Screens returns all screens of all agents, sorted by agent and then by slug.
func Screens() ([]Screen, error) {
	agents, err := fs.ReadDir(data, "data/corpus")
	if err != nil {
		return nil, err
	}
	var all []Screen
	for _, a := range agents {
		if !a.IsDir() {
			continue
		}
		s, err := loadAgent(a.Name())
		if err != nil {
			return nil, err
		}
		all = append(all, s...)
	}
	return all, nil
}

// ScreensFor returns the screens of one agent, sorted by slug. It returns an
// error when the corpus has no such agent.
func ScreensFor(agent string) ([]Screen, error) {
	return loadAgent(agent)
}

// Coverage returns the agent versions that were checked against the corpus
// for one agent, in the order of the coverage file.
func Coverage(agent string) ([]Verified, error) {
	if err := checkAgent(agent); err != nil {
		return nil, err
	}
	raw, err := data.ReadFile(path.Join("data/corpus", agent, "coverage.yaml"))
	if err != nil {
		return nil, err
	}
	var c coverageFile
	if err := yaml.Unmarshal(raw, &c); err != nil {
		return nil, fmt.Errorf("agentsignals: %s coverage: %w", agent, err)
	}
	out := make([]Verified, 0, len(c.Verified))
	for _, v := range c.Verified {
		out = append(out, Verified(v))
	}
	return out, nil
}

func checkAgent(agent string) error {
	if agent == "" || strings.ContainsAny(agent, `/\`) || agent == "." || agent == ".." {
		return fmt.Errorf("agentsignals: unknown agent %q", agent)
	}
	info, err := fs.Stat(data, path.Join("data/corpus", agent))
	if err != nil || !info.IsDir() {
		return fmt.Errorf("agentsignals: unknown agent %q", agent)
	}
	return nil
}

func loadAgent(agent string) ([]Screen, error) {
	if err := checkAgent(agent); err != nil {
		return nil, err
	}
	dir := path.Join("data/corpus", agent, "screens")
	entries, err := fs.ReadDir(data, dir)
	if err != nil {
		return nil, err
	}
	var out []Screen
	for _, e := range entries {
		slug, ok := strings.CutSuffix(e.Name(), ".yaml")
		if !ok {
			continue
		}
		s, err := loadScreen(dir, agent, slug)
		if err != nil {
			return nil, err
		}
		out = append(out, s)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Slug < out[j].Slug })
	return out, nil
}

func loadScreen(dir, agent, slug string) (Screen, error) {
	meta, err := data.ReadFile(path.Join(dir, slug+".yaml"))
	if err != nil {
		return Screen{}, err
	}
	bytes, err := data.ReadFile(path.Join(dir, slug+".screen"))
	if err != nil {
		return Screen{}, fmt.Errorf("agentsignals: %s/%s has no .screen file: %w", agent, slug, err)
	}
	var f screenFile
	if err := yaml.Unmarshal(meta, &f); err != nil {
		return Screen{}, fmt.Errorf("agentsignals: %s/%s: %w", agent, slug, err)
	}
	if f.Schema != SchemaVersion {
		return Screen{}, fmt.Errorf("agentsignals: %s/%s has schema %d, this package reads %d", agent, slug, f.Schema, SchemaVersion)
	}
	if f.Agent != agent {
		return Screen{}, fmt.Errorf("agentsignals: %s/%s has agent %q", agent, slug, f.Agent)
	}
	s := Screen{
		Agent: agent, Slug: slug, AgentVersion: f.AgentVersion,
		Measured: f.Measured, Capture: f.Capture, Provenance: f.Provenance,
		Edits: f.Edits, DerivedFrom: f.DerivedFrom, Description: f.Description,
		NegativeControlFor: f.NegativeControlFor, KnownFalsePositive: f.KnownFalsePositive,
		KnownFalsePositiveReason: f.KnownFalsePositiveReason, Facts: f.Facts,
		Bytes: bytes,
		Expect: Expect{
			State: f.Expect.State, Dialog: f.Expect.Dialog,
			Question: f.Expect.Question, BoxText: f.Expect.BoxText,
		},
	}
	if f.Pane != nil {
		s.Pane = &Pane{Cols: f.Pane.Cols, Rows: f.Pane.Rows}
	}
	for _, o := range f.Expect.Options {
		s.Expect.Options = append(s.Expect.Options, Option(o))
	}
	return s, nil
}
