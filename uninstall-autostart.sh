#!/bin/zsh
set -euo pipefail

LABEL="com.local.codex-usage-float.autostart"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

/bin/launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
if [[ -f "$PLIST" ]]; then
  /bin/rm "$PLIST"
fi

print "Auto-start disabled. The app remains in $HOME/Applications."
