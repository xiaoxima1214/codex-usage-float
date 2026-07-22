#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
LABEL="com.local.codex-usage-float.autostart"
INSTALL_DIR="$HOME/Applications"
APP="$INSTALL_DIR/Codex Usage.app"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SUPPORT_DIR="$HOME/Library/Application Support/CodexUsageFloat"
WATCHER="$SUPPORT_DIR/watch-codex.sh"

"$ROOT/build.sh"
mkdir -p "$INSTALL_DIR" "$HOME/Library/LaunchAgents" "$SUPPORT_DIR"
/usr/bin/ditto "$ROOT/dist/Codex Usage.app" "$APP"
/usr/bin/ditto "$ROOT/watch-codex.sh" "$WATCHER"
/bin/chmod +x "$WATCHER"

/usr/bin/plutil -create xml1 "$PLIST"
/usr/bin/plutil -replace Label -string "$LABEL" "$PLIST"
/usr/bin/plutil -replace ProgramArguments -json "[\"$WATCHER\",\"$APP\"]" "$PLIST"
/usr/bin/plutil -replace RunAtLoad -bool true "$PLIST"
/usr/bin/plutil -replace KeepAlive -bool true "$PLIST"
/usr/bin/plutil -replace ProcessType -string Background "$PLIST"

/bin/launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
/bin/launchctl bootstrap "gui/$UID" "$PLIST"
/bin/launchctl kickstart -k "gui/$UID/$LABEL"

print "Codex-triggered auto-start enabled: $APP"
