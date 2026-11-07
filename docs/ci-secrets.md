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
| none known | agy | agy logs in with OAuth in a browser. No key login was found. Its scenarios run only on a machine with a login. The kit fixture uses the gateway variables `AGY_LLM_GATEWAY_URL` and `AGY_LLM_GATEWAY_API_KEY` with a fake model (fact 77). | open |
| provider keys | opencode | not checked | open |

## The agent kit workflow

The kit jobs of `.github/workflows/scenarios.yml` run the agent kit
(`probes/agent`) against real agents once a week.

- The jobs `kit-no-login` and `kit-no-login-windows` use no secret. A start
  by hand with the input `job` set to `kit-no-login` runs only these jobs.
- A start by hand runs the login jobs only with the input `job` set to
  `kit-login`. The input `all` does not run them.
- The jobs `kit-login` (Linux and macOS) and `kit-login-windows` use
  `ANTHROPIC_API_KEY`, `OPENAI_API_KEY` and `CURSOR_API_KEY`. They run only
  on the main branch. Each job installs only the agents with a key.
- `scenarios/kit-login.sh` and `scenarios/kit-login.ps1` take one agent at
  a time. They write the key of that agent to a file that only the owner
  can read, run its first `permission-*` step in the plan, and delete the
  key. Claude Code reads the file through `apiKeyHelper` and uses the
  model `haiku`. Codex CLI gets the key on the stdin of
  `codex login --with-api-key` and uses a fixed model. The Cursor CLI gets
  `CURSOR_API_KEY` from a small wrapper, because the kit starts each
  session with a clean environment.
- An agent with no key prints `skip: no secret (<agent>)`. A job with no
  key prints `skip: no secret` and passes. A job fails when a step fails,
  when `codex login` fails, or when an agent with a key has no step.
- The login jobs upload the archive only when the input `upload_login` is
  on. Keep it off until the operator read one archive of a run by hand.
- The cost: one model turn for each `permission-*` step (the `cost` column
  of `probes/agent/steps.tsv`), for three agents on three runners. This is
  nine turns at most. The cost is not measured yet.

## How to add a secret

1. Open the repository settings: Secrets and variables, then Actions.
2. Add the secret with the name in the table.
3. Tell the agent-signals session which names you added.
