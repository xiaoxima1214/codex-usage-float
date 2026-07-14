#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
APP="$ROOT/dist/Codex Usage.app"
CONTENTS="$APP/Contents"

mkdir -p "$CONTENTS/MacOS"
xcrun clang "$ROOT/CodexUsageFloat.m" -fobjc-arc -fblocks -O2 -framework Cocoa -o "$CONTENTS/MacOS/CodexUsageFloat"
cp "$ROOT/Info.plist" "$CONTENTS/Info.plist"
codesign --force --deep --sign - "$APP" >/dev/null
print "Built: $APP"
