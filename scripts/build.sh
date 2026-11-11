#!/bin/bash
# Build a background-only macOS executable, without changing user settings.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:-}"
case "$TARGET" in
  claude) SOURCE=ClaudeGlow.swift ;;
  codex) SOURCE=CodexGlow.swift ;;
  *) echo "Usage: $0 <claude|codex> [output-directory]" >&2; exit 2 ;;
esac
[ "$(uname -s)" = Darwin ] || { echo 'Glow requires macOS.' >&2; exit 1; }
command -v swiftc >/dev/null || { echo 'Install Xcode Command Line Tools: xcode-select --install' >&2; exit 1; }
OUTPUT="${2:-$ROOT/build}"
mkdir -p "$OUTPUT"
WORK=$(mktemp -d "$OUTPUT/.build.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.$TARGET-glow</string>
<key>CFBundleName</key><string>$TARGET-glow</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
swiftc -O "$ROOT/$SOURCE" -o "$WORK/$TARGET-glow" \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$WORK/Info.plist"
chmod 700 "$WORK/$TARGET-glow"
mv "$WORK/$TARGET-glow" "$OUTPUT/$TARGET-glow"
echo "Built: $OUTPUT/$TARGET-glow"
