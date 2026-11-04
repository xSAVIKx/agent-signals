#!/bin/sh
# A fake agent program of the kit doctor tests. When it runs, it writes a
# marker file, so that a test can see that the doctor ran it.
[ -n "${DOCTOR_MARKER:-}" ] && : >"$DOCTOR_MARKER.$(basename "$0")"
echo "fake agent"
