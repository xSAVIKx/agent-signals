package site

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"go.yaml.in/yaml/v3"
)

// This file makes the outputs for agents and other programs: a Markdown copy
// of each page, llms.txt, llms-full.txt, and JSON indexes of the corpus and
// the facts. They hold the same data as the HTML pages.

// mdOut gives the path of the Markdown copy of an HTML page.
func mdOut(out string) string { return strings.TrimSuffix(out, ".html") + ".md" }

// mdDoc is one Markdown source that has a page, for llms.txt.
type mdDoc struct {
	Title, Lead, Src, Out string
	Group                 string // the section of llms.txt
}

// addMarkdown adds the Markdown copy of the source of a page. It gives the
// path of the copy.
func (b *builder) addMarkdown(src, out, title, lead, group string) (string, error) {
	data, err := os.ReadFile(filepath.Join(b.root, filepath.FromSlash(src)))
	if err != nil {
		return "", err
	}
	md := mdOut(out)
	b.files = append(b.files, File{Path: md, Data: data})
	b.mdDocs = append(b.mdDocs, mdDoc{Title: title, Lead: lead, Src: src, Out: md, Group: group})
	return md, nil
}

// jsonScreen is one screen in corpus.json.
type jsonScreen struct {
	Key    string         `json:"key"`
	Page   string         `json:"page"`
	Screen string         `json:"screen"`
	Meta   string         `json:"meta"`
	Source string         `json:"source"`
	Fields map[string]any `json:"fields"`
}

type jsonAgent struct {
	Name     string       `json:"name"`
	Display  string       `json:"display"`
	Coverage []Coverage   `json:"coverage"`
	Screens  []jsonScreen `json:"screens"`
}

type jsonFact struct {
	Number   int      `json:"number"`
	ID       string   `json:"id"`
	Title    string   `json:"title"`
	Date     string   `json:"date"`
	Agents   []string `json:"agents"`
	Page     string   `json:"page"`
	Markdown string   `json:"markdown"`
	Source   string   `json:"source"`
}

func writeJSON(v any) ([]byte, error) {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	enc.SetIndent("", "  ")
	if err := enc.Encode(v); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

// machine adds corpus.json, facts.json, llms.txt and llms-full.txt. It runs
// after the pages, so the Markdown copies exist.
func (b *builder) machine() error {
	agents := []jsonAgent{}
	for _, a := range b.agents {
		ja := jsonAgent{Name: a.Name, Display: a.Display, Coverage: a.Coverage, Screens: []jsonScreen{}}
		if ja.Coverage == nil {
			ja.Coverage = []Coverage{}
		}
		for _, s := range a.Screens {
			fields := map[string]any{}
			if err := yaml.Unmarshal(s.MetaBytes, &fields); err != nil {
				return fmt.Errorf("%s: %w", s.Key(), err)
			}
			src := "corpus/" + s.Agent + "/screens/" + s.Slug
			ja.Screens = append(ja.Screens, jsonScreen{
				Key:    s.Key(),
				Page:   BaseURL + screenOut(s),
				Screen: BaseURL + "corpus/" + s.Agent + "/" + s.Slug + ".screen",
				Meta:   BaseURL + "corpus/" + s.Agent + "/" + s.Slug + ".yaml",
				Source: GitHubBlob + src + ".yaml",
				Fields: fields,
			})
			b.files = append(b.files, File{Path: "corpus/" + s.Agent + "/" + s.Slug + ".yaml", Data: s.MetaBytes})
		}
		agents = append(agents, ja)
	}
	data, err := writeJSON(map[string]any{"format": 1, "agents": agents})
	if err != nil {
		return err
	}
	b.files = append(b.files, File{Path: "corpus.json", Data: data})

	facts := []jsonFact{}
	for _, f := range b.facts {
		agents := f.Agents
		if agents == nil {
			agents = []string{}
		}
		facts = append(facts, jsonFact{Number: f.Num, ID: f.ID(), Title: f.Title, Date: f.Date, Agents: agents,
			Page: BaseURL + factOut(f), Markdown: BaseURL + mdOut(factOut(f)), Source: GitHubBlob + "facts/" + f.Slug + ".md"})
	}
	if data, err = writeJSON(map[string]any{"format": 1, "facts": facts}); err != nil {
		return err
	}
	b.files = append(b.files, File{Path: "facts.json", Data: data})
	return b.llms()
}

// llmsGroups gives the order of the sections of llms.txt.
var llmsGroups = []string{"Start", "Docs", "Tasks", "Facts", "Optional"}

// llms writes llms.txt (an index, see https://llmstxt.org/) and
// llms-full.txt (all Markdown pages in one file).
func (b *builder) llms() error {
	var s strings.Builder
	s.WriteString("# agent-signals\n\n")
	s.WriteString("> Measured signals of AI coding agents (terminal screens, hook payloads, session files), as a language-neutral test corpus. Each screen has the exact bytes and the result that a reader must give.\n\n")
	s.WriteString("Each page that comes from a Markdown file has a Markdown copy at the same path, with `.md` in place of `.html`. ")
	s.WriteString("The JSON indexes give every screen and every fact with its URLs. ")
	s.WriteString("The repository is " + strings.TrimSuffix(GitHubBlob, "blob/main/") + ". Agents that work in the repository start with AGENTS.md.\n\n")
	s.WriteString("## Data\n\n")
	s.WriteString("- [corpus.json](" + BaseURL + "corpus.json): every agent, its verified versions, and every screen with its fields and the URLs of the `.screen` and `.yaml` files\n")
	s.WriteString("- [facts.json](" + BaseURL + "facts.json): every fact with its number, date, agents and URLs\n")
	s.WriteString("- [llms-full.txt](" + BaseURL + "llms-full.txt): all Markdown pages of this site in one file\n")
	for _, g := range llmsGroups {
		var lines []string
		for _, d := range b.mdDocs {
			if d.Group != g {
				continue
			}
			line := "- [" + d.Title + "](" + BaseURL + d.Out + ")"
			if d.Lead != "" {
				line += ": " + oneLine(d.Lead)
			}
			lines = append(lines, line)
		}
		if len(lines) == 0 {
			continue
		}
		s.WriteString("\n## " + g + "\n\n" + strings.Join(lines, "\n") + "\n")
	}
	b.files = append(b.files, File{Path: "llms.txt", Data: []byte(s.String())})

	var full strings.Builder
	full.WriteString("# agent-signals: all pages\n\n")
	full.WriteString("This file holds the Markdown source of each page of " + BaseURL + ", in the order of llms.txt. A line \"Source:\" starts each page.\n")
	for _, g := range llmsGroups {
		for _, d := range b.mdDocs {
			if d.Group != g {
				continue
			}
			data, err := os.ReadFile(filepath.Join(b.root, filepath.FromSlash(d.Src)))
			if err != nil {
				return err
			}
			full.WriteString("\n---\n\nSource: " + GitHubBlob + d.Src + "\n\n")
			full.Write(bytes.TrimRight(data, "\n"))
			full.WriteString("\n")
		}
	}
	b.files = append(b.files, File{Path: "llms-full.txt", Data: []byte(full.String())})
	return nil
}

// oneLine joins the lines of a text with spaces.
func oneLine(s string) string { return strings.Join(strings.Fields(s), " ") }
