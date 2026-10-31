#!/bin/sh
# Read-only probe of the terminal programs on macOS.
#
# It lists the terminal programs that run, the tty of each Terminal and
# iTerm2 tab, and the tty of each agent process, so that a tool can find
# the tab of a session. It changes nothing: it does not select a tab.
# Run: sh probes/terminals/macos.sh > terminals-probe.txt 2>&1
# The output holds real paths. Send it through tools/scrub.sh first.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=probes/lib.sh
. "$here/lib.sh"

header terminals/macos.sh 1 tmux
[ "$PROBE_OS" = macos ] || { echo "this probe is for macOS"; exit 0; }

section "Terminal programs that run now"
ps -axo comm= | grep -E -i 'Terminal|iTerm|Ghostty|WezTerm|kitty|Alacritty|Warp|pycharm|idea|webstorm|goland|clion|rider|Code Helper|Cursor Helper|/Cursor$|/Code$' |
  sed -e 's#.*/##' -e 's#\(extension-host\) .*#\1 <workspace>#' -e 's#\(fileWatcher\) \[.*#\1 <workspace>#' | sort | uniq -c

section "tty and terminal of each agent process"
for x in $(pids '(^|[ /])(claude|codex|agy|opencode|cursor-agent)( |$)|(^|[ /])agent .*index\.js|/\.local/bin/agent( |$)'); do
  echo "== $x tty: $(ps -o tty= -p "$x" | tr -d ' ') name: $(ps -o comm= -p "$x" | sed 's#.*/##')"
  chain "$x" | awk '{print "  " $0}' | sed 's#  */[^ ]*/#  #'
done

# Caution: the first osascript call to a terminal program can open a macOS
# dialog that asks for Automation access. Each call below is read-only. The
# rest of the output does not need the access.
section "Terminal tabs and their ttys"
if ps -axo comm= | grep -q '/Terminal$'; then
  osascript -e 'tell application "Terminal" to get tty of every tab of every window' 2>&1
else
  echo "Terminal: not running"
fi

section "iTerm2 sessions and their ttys"
if ps -axo comm= | grep -q '/iTerm2$'; then
  osascript -e 'tell application "iTerm2" to get tty of every session of every tab of every window' 2>&1
else
  echo "iTerm2: not running"
fi

section "Scripting support of other terminals"
for app in Ghostty WezTerm kitty Alacritty Warp; do
  d=/Applications/$app.app
  if [ -d "$d" ]; then
    sdef "$d" >/dev/null 2>&1 && echo "$app: has an AppleScript dictionary" || echo "$app: no AppleScript dictionary"
  else
    echo "$app: not installed"
  fi
done
command -v wezterm >/dev/null 2>&1 && echo "wezterm cli: $(wezterm cli list 2>&1 | head -n 1 | cut -c1-80)"
command -v kitten >/dev/null 2>&1 && echo "kitty remote control: kitten is installed"
for ide in "PyCharm" "IntelliJ IDEA" "WebStorm" "GoLand"; do
  for d in /Applications/"$ide"*.app; do
    [ -d "$d" ] && { sdef "$d" >/dev/null 2>&1 && echo "$ide: has an AppleScript dictionary" || echo "$ide: no AppleScript dictionary"; }
  done
done

section "tmux"
if command -v tmux >/dev/null 2>&1; then
  tmux -V
  tmux ls 2>&1 | sed 's/^[^:]*:/<session>:/' | head -n 20
else
  echo "not installed: tmux"
fi
exit 0
