# Instructions for agents

This repository holds measured signals of AI coding agents: terminal
screens, hook payloads, session files and open files. Tools such as aw and
tg-bridge test their readers against it.

Read `CLAUDE.md` first. Its rules apply to every agent, not only to Claude:
no secrets, no host details, no session details, Conventional Commits, and
prose in ASD-STE100 Simplified Technical English.

## Jobs

Each job has a task file. Follow the task file step by step.

| Job | Task file |
|---|---|
| Run the probe kit on a real machine and send the file | `tasks/run-the-kit.md` |
| Write a fact from probe or scenario output | `tasks/write-a-fact.md` |
| Add a probe for a new agent or a new OS | `tasks/add-a-probe.md` |
| Add an agent to the roadmap, the probes and CI | `tasks/add-an-agent.md` |

## Where things are

| Path | Content |
|---|---|
| `docs/roadmap.md` | The agents to cover, in order, and the state of each cell of the matrix. |
| `docs/os-checks.md` | For each OS: how to see a process, its terminal, its open files and its folder. |
| `docs/ci-secrets.md` | The repository secrets that the model scenarios need. |
| `probes/README.md` | The rules for a probe, and the kit. |
| `scenarios/README.md` | The rules for a scenario. |
| `facts/README.md` | The parts of a fact. |
| `docs/format.md` | The format of a screen. |

## Checks before a commit

1. `cd tools && go test ./... && go run ./cmd/validate ..`
2. `sh tools/sync-go-data.sh`, then `cd go && go test ./...`
   and `pytest python` in a virtual environment with `pip install -e "python[test]"`.
   The sync script also makes the copy for the Python library.
3. `shellcheck --severity=warning` on each changed `.sh` file.
4. `sh tools/test-scrub.sh` when the scrub changed.
