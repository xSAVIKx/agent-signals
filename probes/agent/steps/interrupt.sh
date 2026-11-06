#!/bin/sh
# Step "interrupt": a test session. Read steps/session-step.sh.
exec sh "$(dirname "$0")/session-step.sh" "$@"
