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

## The agent kit workflow

The kit jobs of `.github/workflows/scenarios.yml` run the agent kit
(`probes/agent`) against real agents once a week.

- The jobs `kit-no-login` and `kit-no-login-windows` use no secret. A start
  by hand with the input `job` set to `kit-no-login` runs only these jobs.
- A start by hand runs the login jobs only with the input `job` set to
  `kit-login`. The input `all` does not run them.
- The jobs `kit-login` (Linux and macOS) and `kit-login-windows` use
  `ANTHROPIC_API_KEY`, `OPENAI_API_KEY` and `CURSOR_API_KEY`. They run the
  `permission-*` step of each agent with a key, one backend each, then
  `kit check`. An agent with no key prints `skip: no secret (<agent>)`. A
  job with no key prints `skip: no secret` and passes.
- The job writes each key to a file that only the owner can read. Claude
  Code reads its file through `apiKeyHelper` and uses the model `haiku`.
  Codex CLI reads its file through `codex login --with-api-key`. The Cursor
  CLI gets `CURSOR_API_KEY` from a small wrapper that reads its file,
  because the kit starts each session with a clean environment.
- The cost: one model turn for each `permission-*` step (the `cost` column
  of `probes/agent/steps.tsv`), for three agents on three runners. This is
  nine turns at most. The cost is not measured yet.

## How to add a secret

1. Open the repository settings: Secrets and variables, then Actions.
2. Add the secret with the name in the table.
3. Tell the agent-signals session which names you added.
