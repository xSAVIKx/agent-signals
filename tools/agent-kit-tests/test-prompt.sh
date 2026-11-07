#!/bin/sh
# Checks that the home page and the task file give the same unattended
# prompt for Linux and macOS, and that the home page has a Windows prompt.
set -u
. "$ROOT/tools/agent-kit-tests/lib.sh"

readme=$ROOT/README.md
task=$ROOT/tasks/run-the-kit-as-an-agent.md
page=$(grep '^Run this command: `curl ' "$readme")
quoted=$(sed -n 's/^> \(Run this command: `curl .*\)$/\1/p' "$task")
if [ -n "$page" ] && [ "$page" = "$quoted" ]; then
  pass "the home page and the task file give the same prompt"
else
  fail "the home page and the task file give the same prompt" "page: $page task: $quoted"
fi
expect_line "the prompt runs unattended with a home mode" 'do its task unattended, with the home mode real\. Do not ask me anything\.$' "$readme"
expect_line "the home page has a Windows prompt" '^Run this PowerShell command: `\$env:AGENT_SIGNALS_GET = .*irm https://xsavikx\.github\.io/agent-signals/kit\.ps1 \| iex`\.' "$readme"
expect_line "the task file has the unattended section" '^## Unattended runs$' "$task"
expect_line "the task file starts an unattended run" 'kit start --home real --unattended --out DIR' "$task"
done_tests
