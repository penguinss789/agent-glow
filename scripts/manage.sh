#!/bin/bash
set -euo pipefail
umask 077
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ACTION="${1:-}"
TARGET="${2:-}"
case "$ACTION:$TARGET" in
  install:claude|install:codex|uninstall:claude|uninstall:codex) ;;
  *) echo "Usage: $0 <install|uninstall> <claude|codex>" >&2; exit 2 ;;
esac
[ "$(uname -s)" = Darwin ] || { echo 'Glow requires macOS.' >&2; exit 1; }
command -v python3 >/dev/null || { echo 'Python 3 is required.' >&2; exit 1; }
GLOW_DIR="$HOME/.$TARGET/glow"
BIN="$GLOW_DIR/$TARGET-glow"
if [ "$TARGET" = claude ]; then
  CONFIG="$HOME/.claude/settings.json"
else
  CONFIG="$HOME/.codex/hooks.json"
fi
if [ "$ACTION" = install ]; then
  python3 "$ROOT/scripts/hooks.py" check "$TARGET" "$CONFIG" "$BIN"
  mkdir -p "$GLOW_DIR/state"
  STAMP=$(date +%Y%m%d-%H%M%S)-$$
  if [ -f "$BIN" ]; then cp -p "$BIN" "$BIN.bak.$STAMP"; fi
  bash "$ROOT/scripts/build.sh" "$TARGET" "$GLOW_DIR"
  python3 "$ROOT/scripts/hooks.py" install "$TARGET" "$CONFIG" "$BIN"
  echo "Installed: $BIN"
  if [ "$TARGET" = codex ]; then
    echo 'Review and trust the updated definitions in Codex /hooks, then start a new session.'
  else
    echo 'Start a new Claude Code session to load the hooks.'
  fi
else
  python3 "$ROOT/scripts/hooks.py" uninstall "$TARGET" "$CONFIG" "$BIN"
  rm -rf "$GLOW_DIR"
  echo "Removed: $GLOW_DIR"
fi
