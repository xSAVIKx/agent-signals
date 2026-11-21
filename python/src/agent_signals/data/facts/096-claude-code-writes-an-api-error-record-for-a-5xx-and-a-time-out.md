# 096. Claude Code writes an API error record for a 5xx and a time-out

## Measured

2026-11-18 (UTC), Claude Code 2.1.327, on Linux (Debian 13, x64), with
`claude -p "<prompt>" --output-format json`, a throwaway `HOME`, a
throwaway work folder and no login. The fake model of the kit
(`probes/agent/fake-model.py`) answered on 127.0.0.1. The answers came
from the fake model, not from the real API. Measured on: real machine.

## Method

1. The fake model got three new answers for a Messages API request with
   tools. The last user text selects the answer:
   - `Fail with 500`: HTTP 500, the body
     `{"type":"error","error":{"type":"api_error","message":"..."},"request_id":"..."}`
     and a `request-id` header.
   - `Fail with 529`: HTTP 529, the same body with the error type
     `overloaded_error`.
   - `Answer late`: no status line and no byte, until the client closes
     the connection.
2. Each case ran once with `CLAUDE_CODE_MAX_RETRIES=1`. The 500 case ran
   one more time with `CLAUDE_CODE_MAX_RETRIES=0`. The late case had
   `API_TIMEOUT_MS=5000`. The fake model set `ANTHROPIC_BASE_URL`,
   `ANTHROPIC_API_KEY` and `CLAUDE_CONFIG_DIR`.
3. After each run, the transcript
   `$CLAUDE_CONFIG_DIR/projects/<key>/<session id>.jsonl` was read. The
   field names below come from it. The message texts are not given here.

## What was measured

1. Each case ended the turn with one record of the type `assistant`. Its
   fields, in addition to the usual `parentUuid`, `uuid`, `timestamp`,
   `sessionId`, `cwd`, `version`, `gitBranch`, `userType`, `entrypoint`:

   | Field | 500 | 529 | Time-out |
   |---|---|---|---|
   | `isApiErrorMessage` | `true` | `true` | `true` |
   | `error` | `"server_error"` | `"server_error"` | `"server_error"` |
   | `apiErrorStatus` | `500` | `529` | absent |
   | `apiErrorType` | `"api_error"` | `"overloaded_error"` | absent |
   | `requestId` | the `request-id` of the last attempt | the same | absent |
   | `message.model` | `"<synthetic>"` | `"<synthetic>"` | `"<synthetic>"` |
   | `message.content` | one `text` block | one `text` block | one `text` block |
   | `message.stop_reason` | `"stop_sequence"` | `"stop_sequence"` | `"stop_sequence"` |
   | `message.usage` | all counts 0 | all counts 0 | all counts 0 |
   | `failedResponseHadNoToolCall` | `true` | `true` | `true` |

   The record has no field with the name `apiError`. The values of
   `apiErrorType` are the error types of the response body.
2. Before each retry, Claude Code wrote one record of the type `system`
   with `subtype: "api_error"`, `level: "error"`, `source:
   "request_retry"`, `retryAttempt`, `maxRetries` and `retryInMs`. Its
   `error` object has the keys `message`, `formatted`, `connection`,
   `isNetworkDown` (`false`), `rateLimits` (`null`) and `noResponse`
   (`null`). For the 500 and the 529, `error` has also `status` and
   `requestId`. For the time-out, `error` has no `status` and no
   `requestId`. With `CLAUDE_CODE_MAX_RETRIES=0` there was no `system`
   record.
3. Each failed attempt wrote one `api-request` record before it. With one
   retry, a turn had two `api-request` records, one `system` record and
   one `assistant` error record.
4. The time-out came 5 s after the request, as `API_TIMEOUT_MS` set. The
   retry came about 0.5 s later (`retryInMs` 518 to 594).
5. The `result` line of `--output-format json` had `is_error: true`,
   `subtype: "success"` and `terminal_reason: "api_error"`. For the 500
   and the 529 it had `api_error_status` and `api_error_type` with the
   values of item 1. For the time-out both were `null`. The exit code was
   1.
6. A stream that stops after `message_start` (the fake answer
   `Count from`) did not cause a time-out in 120 s, also with
   `CLAUDE_ENABLE_STREAM_WATCHDOG=1` and
   `CLAUDE_STREAM_IDLE_TIMEOUT_MS=5000`. Claude Code wrote no `system`
   record. When the fake model closed the connection after 120 s, Claude
   Code sent a second request with `max_tokens` 64000 instead of 128000.
   That request timed out after 5 s and gave the time-out record of item
   1.

## Comparison with the usage limit

`docs/detection.md` gives the 429 record that aw saw: an assistant record
with `isApiErrorMessage: true`, an `apiError` field and
`apiErrorStatus: 429`. The records here have the same
`isApiErrorMessage` and `apiErrorStatus` fields. A tool can use this
rule: `isApiErrorMessage: true` with `apiErrorStatus: 429` is the usage
limit. Another `apiErrorStatus` is a server error. No `apiErrorStatus` is
a time-out or a connection error. The `apiError` field of the aw record
was not in these records. This fact did not measure a 429, so it cannot
say whether `apiError` is the same field as `error`.

## Mechanism

The model `<synthetic>` shows that Claude Code writes the error record
itself, after its last retry. The record keeps the status and the error
type of the last HTTP response. A time-out has no HTTP response, so the
record has no status. The source code was not read.

## Screens

No corpus screen pins this fact.

## Not measured

- The real API. A real 500, 529 or time-out can give other fields, other
  error types or other retry behaviour. The fake model sent a body of the
  public error form; the real body was not compared.
- The interactive mode. Only `claude -p` ran. The transcript of an
  interactive session was not read.
- The default retry count, the model fallback after many 529 answers, and
  `CLAUDE_CODE_OVERLOADED_RETRY_*`.
- Other 5xx statuses than 500 and 529, and a connection refused.
- A 429 on the fake model.
- Why the stream watchdog of item 6 did not stop the stream, and whether
  the second request of item 6 had streaming off.
- macOS and Windows, and other versions of Claude Code.
