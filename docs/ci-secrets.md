# Secrets for CI

The no-login probes and scenarios need no secret. The model scenarios need
one secret for each agent. Only the operator adds a secret. An agent never
adds one.

## Rules

1. A job that uses a secret runs only on `workflow_dispatch` or on a
   schedule. A pull request cannot start it, and no workflow uses
   `pull_request_target`.
2. GitHub gives no secret to a pull request from a fork.
3. A scenario passes a key to the agent through a file that only the owner
   can read (`scenarios/lib.sh`), not on the command line.
4. One full run of all model scenarios with API keys must cost less than
   2 USD. Each scenario records its cost.

## The secrets

| Secret | Agent | What it enables | Status |
|---|---|---|---|
| `CLAUDE_CODE_OAUTH_TOKEN` or `ANTHROPIC_API_KEY` | Claude Code | the permission scenario on macOS runners | The variable names are not checked in CI. |
| `OPENAI_API_KEY` | Codex CLI | the approval scenarios; the scenario runs `codex login --with-api-key` in the throwaway `HOME` | from `codex login --help` |
| `CURSOR_API_KEY` | Cursor CLI | all Cursor model scenarios, on the Linux server too: it has no Cursor login | from `cursor-agent --help` |
| none known | agy | agy logs in with OAuth in a browser. No key login was found. Its scenarios run only on a machine with a login. | open |
| provider keys | opencode | not checked | open |

## How to add a secret

1. Open the repository settings: Secrets and variables, then Actions.
2. Add the secret with the name in the table.
3. Tell the agent-signals session which names you added.
