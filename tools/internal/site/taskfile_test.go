package site

import (
	"bufio"
	"bytes"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"
)

// agentPrompt is the one prompt for all machines and all agents. Read part 1
// of docs/design/2026-11-01-agent-run-kit.md.
const agentPrompt = "Read https://xsavikx.github.io/agent-signals/tasks/run-the-kit-as-an-agent.md and do the task. Ask me before each step that needs me."

// agentTask is the task file that the prompt names.
const agentTask = "tasks/run-the-kit-as-an-agent.md"

// TestHomePageHasThePrompt checks that the home page holds the exact prompt
// and a copy button, that the button works with the plain script of the
// site, and that the site serves the task file at the URL of the prompt.
func TestHomePageHasThePrompt(t *testing.T) {
	files, err := Build("../../..")
	if err != nil {
		t.Fatal(err)
	}
	byPath := map[string][]byte{}
	for _, f := range files {
		byPath[f.Path] = f.Data
	}
	home := string(byPath["index.html"])
	if !strings.Contains(home, `<code id="agent-prompt">`+agentPrompt+`</code>`) {
		t.Errorf("index.html: no element agent-prompt with the exact prompt")
	}
	if !strings.Contains(home, `<button type="button" class="copy-prompt" data-copy="agent-prompt" aria-describedby="copy-prompt-status" hidden>`) {
		t.Errorf("index.html: no copy button for the prompt")
	}
	if !strings.Contains(home, `id="copy-prompt-status"`) || !strings.Contains(home, `<script src="assets/page.js" defer></script>`) {
		t.Errorf("index.html: no status element or no page.js for the copy button")
	}
	js := string(byPath["assets/page.js"])
	for _, s := range []string{`button.copy-prompt`, `data-copy`, `navigator.clipboard.writeText`, `copy-prompt-status`} {
		if !strings.Contains(js, s) {
			t.Errorf("assets/page.js: no %q", s)
		}
	}
	for _, s := range []string{"import ", "require(", "<script"} {
		if strings.Contains(js, s) {
			t.Errorf("assets/page.js: %q; the script must use no framework and no module", s)
		}
	}
	url := strings.Fields(agentPrompt)[1]
	served, ok := strings.CutPrefix(url, BaseURL)
	if !ok || served != agentTask {
		t.Fatalf("the prompt names %q, not the task file %s", url, agentTask)
	}
	src, err := os.ReadFile(filepath.Join("../../..", agentTask))
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(byPath[served], src) {
		t.Errorf("the site does not serve %s at %s with the bytes of the source", agentTask, url)
	}
}

// taskCommands gives the lines of the fenced code blocks with the info
// string sh or powershell in a Markdown file. The blocks with the info
// string text hold output, not commands.
func taskCommands(t *testing.T, path string) []string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var lines []string
	in, cmd := false, false
	sc := bufio.NewScanner(bytes.NewReader(data))
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if strings.HasPrefix(line, "```") {
			if in {
				in = false
				continue
			}
			in = true
			info := strings.TrimPrefix(line, "```")
			cmd = info == "sh" || info == "powershell"
			continue
		}
		if in && cmd && line != "" {
			lines = append(lines, line)
		}
	}
	if err := sc.Err(); err != nil {
		t.Fatal(err)
	}
	return lines
}

// kitWord finds the command after "kit " in a line of a code block.
var kitWord = regexp.MustCompile(`^kit ([a-z-]+)`)

// TestTaskFileNamesOnlyKitCommands checks that each command in a code block
// of the task file starts the kit or runs a kit command, and that each kit
// command exists for the dispatcher probes/agent/kit.sh. A kit command has
// the file probes/agent/<command>.sh. Other pull requests add these files.
// The test skips the second check while a file is missing.
func TestTaskFileNamesOnlyKitCommands(t *testing.T) {
	root := "../../.."
	lines := taskCommands(t, filepath.Join(root, agentTask))
	if len(lines) == 0 {
		t.Fatalf("%s: no sh or powershell code block", agentTask)
	}
	allowed := []string{"kit ", "sh ", "curl ", "irm ", "$env:AGENT_SIGNALS_GET=", "powershell "}
	used := map[string]bool{}
	for _, l := range lines {
		ok := false
		for _, p := range allowed {
			if strings.HasPrefix(l, p) {
				ok = true
			}
		}
		if !ok {
			t.Errorf("%s: the command %q does not start with one of %q", agentTask, l, allowed)
		}
		if m := kitWord.FindStringSubmatch(l); m != nil {
			used[m[1]] = true
		}
	}
	if len(used) == 0 {
		t.Fatalf("%s: no kit command in a code block", agentTask)
	}
	kit := filepath.Join(root, "probes", "agent", "kit.sh")
	if _, err := os.Stat(kit); err != nil {
		t.Skipf("%s is not in this tree: %v", kit, err)
	}
	var missing []string
	for c := range used {
		if c == "version" {
			continue // kit.sh runs "version" itself.
		}
		if _, err := os.Stat(filepath.Join(root, "probes", "agent", c+".sh")); err != nil {
			missing = append(missing, c)
		}
	}
	if len(missing) > 0 {
		sort.Strings(missing)
		t.Skipf("the kit has no file probes/agent/<command>.sh yet for: %s", strings.Join(missing, ", "))
	}
}

// TestTaskFileMatchesStepsTSV checks that the task file names each step
// kind of probes/agent/steps.tsv. It skips while steps.tsv is not in the
// tree.
func TestTaskFileMatchesStepsTSV(t *testing.T) {
	root := "../../.."
	tsv := filepath.Join(root, "probes", "agent", "steps.tsv")
	data, err := os.ReadFile(tsv)
	if err != nil {
		t.Skipf("%s is not in this tree: %v", tsv, err)
	}
	task, err := os.ReadFile(filepath.Join(root, agentTask))
	if err != nil {
		t.Fatal(err)
	}
	kinds := map[string]bool{}
	col := -1
	for _, line := range strings.Split(string(data), "\n") {
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		f := strings.Split(line, "\t")
		if col < 0 {
			for i, name := range f {
				if name == "kind" {
					col = i
				}
			}
			if col < 0 {
				t.Fatalf("%s: no column kind", tsv)
			}
			continue
		}
		if col < len(f) {
			kinds[f[col]] = true
		}
	}
	if len(kinds) == 0 {
		t.Fatalf("%s: no step", tsv)
	}
	for k := range kinds {
		if !bytes.Contains(task, []byte("`"+k+"`")) {
			t.Errorf("%s: the step kind %q of steps.tsv is not named as `%s`", agentTask, k, k)
		}
	}
}
