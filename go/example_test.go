package agentsignals_test

import (
	"bytes"
	"fmt"
	"testing"

	agentsignals "github.com/xSAVIKx/agent-signals/go"
)

// classify is a fake reader. A real tool puts its own classifier here.
func classify(screen []byte) string {
	if bytes.Contains(screen, []byte("Do you want")) {
		return "PERMISSION"
	}
	return "UNKNOWN"
}

// A table test: each screen of one agent goes to the classifier, and the
// result is compared with the expected state.
func ExampleScreensFor() {
	screens, err := agentsignals.ScreensFor("claude")
	if err != nil {
		fmt.Println(err)
		return
	}
	// In a real test, use t.Run(s.Slug, ...) and t.Errorf for each mismatch.
	// The fake classifier is wrong for most screens, so this example only counts.
	wrong := 0
	for _, s := range screens {
		if classify(s.Bytes) != s.Expect.State {
			wrong++
		}
	}
	fmt.Println(len(screens) > 0, wrong <= len(screens))
	// Output: true true
}

func TestFakeClassifier(t *testing.T) {
	screens, err := agentsignals.ScreensFor("claude")
	if err != nil {
		t.Fatal(err)
	}
	for _, s := range screens {
		t.Run(s.Slug, func(t *testing.T) {
			if s.KnownFalsePositive {
				t.Skip(s.KnownFalsePositiveReason)
			}
			got := classify(s.Bytes)
			// The fake classifier knows only one state. A real one must match all.
			if got == "PERMISSION" && s.Expect.State != "PERMISSION" {
				t.Errorf("classified %s as PERMISSION, want %s", s.Slug, s.Expect.State)
			}
		})
	}
}
