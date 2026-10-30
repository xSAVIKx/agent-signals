package site

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
)

// Fact is the summary of one file in facts/, for the facts table.
type Fact struct {
	Num        int
	Slug       string // the file name without ".md"
	Title      string // the heading without the number
	Date       string // the first date in the "Measured" section
	MeasuredOn string // the value of the "Measured on:" line, or ""
	Agents     []string
}

// ID gives the number with three digits, as in the file name.
func (f Fact) ID() string { return fmt.Sprintf("%03d", f.Num) }

var factFile = regexp.MustCompile(`^(\d{3})-([a-z0-9-]+)\.md$`)
var factTitle = regexp.MustCompile(`(?m)^# (\d+)\.\s+(.+)$`)
var datePattern = regexp.MustCompile(`\b\d{4}-\d{2}-\d{2}\b`)
var measuredOn = regexp.MustCompile(`\bMeasured on:\s*`)

// agentNames gives the display name of each agent, in the order of the
// roadmap, and the pattern that finds the agent in a text.
var agentNames = []struct {
	name string
	re   *regexp.Regexp
}{
	{"Claude Code", regexp.MustCompile(`\bClaude\b`)},
	{"Codex CLI", regexp.MustCompile(`\b[Cc]odex\b`)},
	{"Antigravity CLI", regexp.MustCompile(`\bagy\b|Antigravity`)},
	{"Cursor CLI", regexp.MustCompile(`\bCursor\b`)},
	{"opencode", regexp.MustCompile(`\bopencode\b`)},
	{"Gemini CLI", regexp.MustCompile(`\bGemini CLI\b`)},
	{"Copilot CLI", regexp.MustCompile(`\bCopilot\b`)},
	{"Qwen Code", regexp.MustCompile(`\bQwen\b`)},
	{"Aider", regexp.MustCompile(`\bAider\b`)},
	{"Amp", regexp.MustCompile(`\bAmp\b`)},
	{"Goose", regexp.MustCompile(`\bGoose\b`)},
	{"Crush", regexp.MustCompile(`\bCrush\b`)},
	{"Kimi Code CLI", regexp.MustCompile(`\bKimi\b`)},
	{"Continue CLI", regexp.MustCompile(`\bContinue CLI\b`)},
	{"Factory Droid", regexp.MustCompile(`\bDroid\b`)},
	{"Cline CLI", regexp.MustCompile(`\bCline\b`)},
	{"Kilo Code CLI", regexp.MustCompile(`\bKilo\b`)},
	{"Auggie", regexp.MustCompile(`\bAuggie\b`)},
	{"OpenHands CLI", regexp.MustCompile(`\bOpenHands\b`)},
}

// agentDisplay maps the folder name of an agent in corpus/ to its name.
var agentDisplay = map[string]string{
	"claude":    "Claude Code",
	"codex":     "Codex CLI",
	"agy":       "Antigravity CLI",
	"cursor":    "Cursor CLI",
	"opencode":  "opencode",
	"gemini":    "Gemini CLI",
	"copilot":   "Copilot CLI",
	"qwen":      "Qwen Code",
	"aider":     "Aider",
	"amp":       "Amp",
	"goose":     "Goose",
	"crush":     "Crush",
	"kimi":      "Kimi Code CLI",
	"continue":  "Continue CLI",
	"droid":     "Factory Droid",
	"cline":     "Cline CLI",
	"kilo":      "Kilo Code CLI",
	"auggie":    "Auggie",
	"openhands": "OpenHands CLI",
}

// section gives the text of the level-2 section with the heading name, or "".
func section(md, name string) string {
	start := strings.Index(md, "\n## "+name+"\n")
	if start < 0 {
		return ""
	}
	rest := md[start+len(name)+5:]
	if end := strings.Index(rest, "\n## "); end >= 0 {
		rest = rest[:end]
	}
	return rest
}

// ParseFact reads the summary of a fact from its file name and its text.
// screenAgents holds the folder names of the agents whose screens name the fact.
func ParseFact(name, md string, screenAgents []string) (Fact, error) {
	m := factFile.FindStringSubmatch(name)
	if m == nil {
		return Fact{}, fmt.Errorf("%s: the name is not NNN-<slug>.md", name)
	}
	num, _ := strconv.Atoi(m[1])
	f := Fact{Num: num, Slug: strings.TrimSuffix(name, ".md")}
	t := factTitle.FindStringSubmatch(md)
	if t == nil {
		return Fact{}, fmt.Errorf("%s: no heading of the form \"# NNN. Title\"", name)
	}
	if n, _ := strconv.Atoi(t[1]); n != num {
		return Fact{}, fmt.Errorf("%s: the heading has the number %d", name, n)
	}
	f.Title = strings.TrimSpace(t[2])
	measured := section(md, "Measured")
	if d := datePattern.FindString(measured); d != "" {
		f.Date = d
	} else {
		f.Date = datePattern.FindString(md)
	}
	if loc := measuredOn.FindStringIndex(md); loc != nil {
		f.MeasuredOn = sentence(md[loc[1]:])
	}
	text := f.Title + "\n" + measured
	seen := map[string]bool{}
	for _, a := range screenAgents {
		if n, ok := agentDisplay[a]; ok {
			seen[n] = true
		}
	}
	for _, a := range agentNames {
		if seen[a.name] || a.re.MatchString(text) {
			f.Agents = append(f.Agents, a.name)
		}
	}
	if strings.Contains(f.Title, "tmux") {
		f.Agents = append(f.Agents, "tmux")
	}
	return f, nil
}

// sentence gives the first sentence of a paragraph, with its line breaks
// joined and without the final full stop.
func sentence(s string) string {
	if end := strings.Index(s, "\n\n"); end >= 0 {
		s = s[:end]
	}
	s = strings.Join(strings.Fields(s), " ")
	if end := strings.Index(s, ". "); end >= 0 {
		s = s[:end]
	}
	return strings.TrimSuffix(s, ".")
}
