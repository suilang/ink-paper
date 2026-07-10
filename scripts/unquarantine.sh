#!/usr/bin/env bash
# Clear macOS Gatekeeper quarantine on Ink Paper (unsigned builds).
# Usage:
#   ./scripts/unquarantine.sh
#   ./scripts/unquarantine.sh /Applications/InkPaper.app
#   ./scripts/unquarantine.sh ~/Downloads/InkPaper-v0.2.0-macos.dmg
set -euo pipefail

TARGET="${1:-/Applications/InkPaper.app}"

if [[ ! -e "$TARGET" ]]; then
  echo "error: not found: $TARGET" >&2
  echo "先把 InkPaper.app 拖到「应用程序」，或传入 App / DMG 路径。" >&2
  exit 1
fi

echo "==> Clearing quarantine: $TARGET"
xattr -cr "$TARGET"

if [[ -d "$TARGET" && "$TARGET" == *.app ]]; then
  echo "==> Opening…"
  open "$TARGET"
fi

echo "Done. If macOS still blocks the app: right-click → Open, or"
echo "System Settings → Privacy & Security → Open Anyway."
