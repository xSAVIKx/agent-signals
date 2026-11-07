#!/bin/sh
# Builds the probe kit archive from the paths in tools/kit-paths.txt.
#
# Usage: sh tools/kit-archive.sh tar.gz|zip OUT [VERSION]
#
# The archive holds the folder agent-signals-kit/ with the paths of
# HEAD (git archive), so a change that is not committed is not in it.
# With VERSION, the archive also holds agent-signals-kit/VERSION with
# that text; the agent kit reads it (kit version).
# The archive also holds agent-signals-kit/AGENTS.md, a copy of
# tasks/run-the-kit-as-an-agent.md. So an agent can read the task of the
# kit that it downloaded.
# With KIT_ARCHIVE_WORKTREE=1, the archive holds the files of the work
# tree instead, for tests of changes that are not committed (tar.gz only).
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
[ "$#" -ge 2 ] || { echo "usage: kit-archive.sh tar.gz|zip OUT [VERSION]" >&2; exit 2; }
fmt=$1 out=$2 ver=${3:-}
case $fmt in tar.gz|zip) ;; *) echo "kit-archive: unknown format: $fmt" >&2; exit 2 ;; esac
task=tasks/run-the-kit-as-an-agent.md
paths=$(grep -v '^#' "$root/tools/kit-paths.txt" | grep -v '^$')
case $out in /*|[A-Za-z]:*) ;; *) out=$(pwd)/$out ;; esac

if [ -n "${KIT_ARCHIVE_WORKTREE:-}" ]; then
  [ "$fmt" = tar.gz ] || { echo "kit-archive: the work tree form makes only tar.gz" >&2; exit 2; }
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  mkdir "$tmp/agent-signals-kit"
  # shellcheck disable=SC2086
  (cd "$root" && tar -cf - $paths) | (cd "$tmp/agent-signals-kit" && tar -xf -)
  [ -n "$ver" ] && printf '%s\n' "$ver" >"$tmp/agent-signals-kit/VERSION"
  cp "$root/$task" "$tmp/agent-signals-kit/AGENTS.md"
  (cd "$tmp" && tar -czf "$out" agent-signals-kit)
  exit 0
fi

# The command substitution removes the last newline. The line below gives it
# back, so that the copy has the bytes of the file at HEAD.
set -- "--add-virtual-file=agent-signals-kit/AGENTS.md:$(cd "$root" && git show "HEAD:$task")
"
[ -n "$ver" ] && set -- "$@" "--add-virtual-file=agent-signals-kit/VERSION:$ver
"
# shellcheck disable=SC2086
(cd "$root" && git archive --format="$fmt" --prefix=agent-signals-kit/ -o "$out" "$@" HEAD $paths)
