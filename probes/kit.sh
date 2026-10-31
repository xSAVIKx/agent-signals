#!/bin/sh
# One-line start of the probe kit on Linux and macOS:
#
#   curl -fsSL https://xsavikx.github.io/agent-signals/kit.sh | sh
#   curl -fsSL https://xsavikx.github.io/agent-signals/kit.sh | sh -s -- --guided permission cursor
#
# It downloads the kit of the latest release (agent-signals-kit.tar.gz) to a
# temporary folder, runs probes/run.sh with the arguments, and deletes the
# folder. The kit writes its file in the current folder. Read probes/run.sh
# for the arguments. When the release has no kit file, it downloads the
# repository archive of main.
#
# The environment can change the source:
#   AGENT_SIGNALS_REF  a branch or a tag; the kit then comes from the
#                      repository archive of that ref
#   AGENT_SIGNALS_URL  the URL of a .tar.gz archive; a file:// URL works too
set -eu
repo=https://github.com/xSAVIKx/agent-signals
if [ -n "${AGENT_SIGNALS_URL:-}" ]; then
  urls=$AGENT_SIGNALS_URL
elif [ -n "${AGENT_SIGNALS_REF:-}" ]; then
  urls=https://codeload.github.com/xSAVIKx/agent-signals/tar.gz/$AGENT_SIGNALS_REF
else
  urls="$repo/releases/latest/download/agent-signals-kit.tar.gz https://codeload.github.com/xSAVIKx/agent-signals/tar.gz/main"
fi

tmp=$(mktemp -d 2>/dev/null || mktemp -d -t agent-signals)
trap 'rm -rf "$tmp"' EXIT INT TERM

fetch() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$1" -o "$tmp/kit.tar.gz"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$tmp/kit.tar.gz" "$1"
  else
    echo "kit: needs curl or wget" >&2
    exit 1
  fi
}
got=
for url in $urls; do
  echo "kit: download $url" >&2
  if fetch "$url" 2>/dev/null; then
    got=$url
    break
  fi
done
if [ -z "$got" ]; then
  echo "kit: the download failed" >&2
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
