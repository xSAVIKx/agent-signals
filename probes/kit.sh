#!/bin/sh
# One-line start of the probe kit on Linux and macOS:
#
#   curl -fsSL https://xsavikx.github.io/agent-signals/kit.sh | sh
#   curl -fsSL https://xsavikx.github.io/agent-signals/kit.sh | sh -s -- --guided permission cursor
#
# It downloads the repository archive to a temporary folder, runs
# probes/run.sh with the arguments, and deletes the folder. The kit writes
# its file in the current folder. Read probes/run.sh for the arguments.
#
# The environment can change the source:
#   AGENT_SIGNALS_REF  a branch or a tag (default: main)
#   AGENT_SIGNALS_URL  the URL of a .tar.gz archive; a file:// URL works too
set -eu
ref=${AGENT_SIGNALS_REF:-main}
url=${AGENT_SIGNALS_URL:-https://codeload.github.com/xSAVIKx/agent-signals/tar.gz/$ref}

tmp=$(mktemp -d 2>/dev/null || mktemp -d -t agent-signals)
trap 'rm -rf "$tmp"' EXIT INT TERM

echo "kit: download $url" >&2
if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$url" -o "$tmp/kit.tar.gz"
elif command -v wget >/dev/null 2>&1; then
  wget -q -O "$tmp/kit.tar.gz" "$url"
else
  echo "kit: needs curl or wget" >&2
  exit 1
fi
mkdir "$tmp/src"
tar -xzf "$tmp/kit.tar.gz" -C "$tmp/src"
run=$(find "$tmp/src" -maxdepth 3 -path '*/probes/run.sh' | head -n 1)
if [ -z "$run" ]; then
  echo "kit: no probes/run.sh in the archive" >&2
  exit 1
fi

# With "curl | sh", stdin is the script. The kit asks questions, so it
# reads from the terminal.
if [ -t 1 ] && (: </dev/tty) 2>/dev/null; then
  sh "$run" "$@" </dev/tty
else
  sh "$run" "$@" </dev/null
fi
