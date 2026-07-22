#!/bin/zsh
set -u

APP="${1:-$HOME/Applications/Codex Usage.app}"
codex_was_running=0

while true; do
  codex_is_running=0

  if /usr/bin/pgrep -x Codex >/dev/null 2>&1 \
    || /usr/bin/pgrep -x ChatGPT >/dev/null 2>&1 \
    || /usr/bin/pgrep -f '/Codex.app/Contents/MacOS/' >/dev/null 2>&1 \
    || /usr/bin/pgrep -f '/ChatGPT.app/Contents/MacOS/ChatGPT' >/dev/null 2>&1; then
    codex_is_running=1
  fi

  if (( codex_is_running == 1 && codex_was_running == 0 )); then
    /usr/bin/open "$APP"
  fi

  codex_was_running=$codex_is_running
  /bin/sleep 3
done
