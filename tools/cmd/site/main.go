// Command site builds the documentation website from the repository.
//
//	cd tools && go run ./cmd/site -root .. -out ../_site
//
// The build uses no network. The same input gives the same bytes.
package main

import (
	"flag"
	"fmt"
	"os"
	"time"

	"github.com/xSAVIKx/agent-signals/tools/internal/site"
)

func main() {
	root := flag.String("root", "..", "the repository folder")
	out := flag.String("out", "../_site", "the output folder; the build replaces it")
	flag.Parse()
	start := time.Now()
	n, err := site.Write(*root, *out)
	if err != nil {
		fmt.Fprintln(os.Stderr, "site:", err)
		os.Exit(1)
	}
	fmt.Printf("site: wrote %d files to %s in %s\n", n, *out, time.Since(start).Round(time.Millisecond))
}
