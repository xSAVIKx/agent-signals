// Command validate checks the corpus and prints each problem. It exits 1 when
// it finds a problem.
//
//	go run ./cmd/validate <repository root>
package main

import (
	"fmt"
	"os"

	"github.com/xSAVIKx/agent-signals/tools/internal/validate"
)

func main() {
	root := "."
	if len(os.Args) > 1 {
		root = os.Args[1]
	}
	problems, err := validate.Check(root)
	if err != nil {
		fmt.Fprintln(os.Stderr, "validate:", err)
		os.Exit(2)
	}
	for _, p := range problems {
		fmt.Println(p)
	}
	if len(problems) > 0 {
		fmt.Fprintf(os.Stderr, "validate: %d problems\n", len(problems))
		os.Exit(1)
	}
	fmt.Println("validate: the corpus is valid")
}
