#!/bin/zsh
set -euo pipefail

LABEL="com.local.codex-usage-float.autostart"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
WATCHER="$HOME/Library/Application Support/CodexUsageFloat/watch-codex.sh"

/bin/launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
if [[ -f "$PLIST" ]]; then
  /bin/rm "$PLIST"
fi
if [[ -f "$WATCHER" ]]; then
  /bin/rm "$WATCHER"
fi

print "Codex-triggered auto-start disabled. The app remains in $HOME/Applications."
