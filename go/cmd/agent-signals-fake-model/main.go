// Command agent-signals-fake-model serves a local fake model for a test
// session of an agent CLI, with no login, no network and no cost. Read the
// documentation of the package fakemodel.
//
// Usage:
//
//	agent-signals-fake-model --agent codex|claude|agy|cursor-agent|opencode --home HOME
//	    --env-file FILE --log FILE [--pid-file FILE]
//
// It writes the settings files of the agent in HOME, then FILE with one
// KEY=VALUE line for each variable that the agent needs. It serves until it
// gets SIGINT or SIGTERM, or for 30 minutes. Exit codes: 0 ok, 1 an error,
// 2 bad use.
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"github.com/xSAVIKx/agent-signals/go/fakemodel"
)

func main() {
	var o fakemodel.Options
	fs := flag.NewFlagSet("agent-signals-fake-model", flag.ContinueOnError)
	fs.StringVar(&o.Agent, "agent", "", "codex, claude, agy, cursor-agent or opencode")
	fs.StringVar(&o.Home, "home", "", "the throwaway home of the test session")
	fs.StringVar(&o.EnvFile, "env-file", "", "the file for the variables")
	fs.StringVar(&o.Log, "log", "", "the log file")
	fs.StringVar(&o.PIDFile, "pid-file", "", "a file for the process ID")
	if err := fs.Parse(os.Args[1:]); err != nil {
		os.Exit(2)
	}
	if fs.NArg() > 0 || o.Agent == "" || o.Home == "" || o.EnvFile == "" || o.Log == "" {
		fmt.Fprintln(os.Stderr, "usage: agent-signals-fake-model --agent codex|claude|agy|cursor-agent|opencode --home HOME --env-file FILE --log FILE [--pid-file FILE]")
		os.Exit(2)
	}
	if _, err := fakemodel.Agent(o.Agent); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	if err := fakemodel.Run(ctx, o); err != nil {
		fmt.Fprintln(os.Stderr, "agent-signals-fake-model:", err)
		os.Exit(1)
	}
}
