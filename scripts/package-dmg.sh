#!/usr/bin/env bash
# Build a styled macOS DMG for Ink Paper (app + Applications shortcut + custom window).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIGURATION="${CONFIGURATION:-Release}"
SKIP_BUILD="${SKIP_BUILD:-0}"
DERIVED_DATA="${DERIVED_DATA:-.derivedData}"
# HiDPI multi-res TIFF (1x 660×400 + 2x 1320×800). Plain 2x PNG is treated as 1x and crops.
BACKGROUND_SRC="${BACKGROUND_SRC:-packaging/dmg/background.tiff}"
BACKGROUND_NAME="$(basename "$BACKGROUND_SRC")"

VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' InkPaper/Resources/Info.plist)"
TAG="v${VER}"
APP_NAME="InkPaper.app"
VOLUME_NAME="Ink Paper"
DMG_NAME="InkPaper-${TAG}-macos.dmg"

# Finder window layout (logical points; must match background 1x size)
WINDOW_WIDTH=660
WINDOW_HEIGHT=400
ICON_SIZE=128
APP_ICON_X=168
APP_ICON_Y=168
APPS_ICON_X=492
APPS_ICON_Y=168

if [[ "$SKIP_BUILD" != "1" ]]; then
  echo "==> Building ${CONFIGURATION}…"
  xcodebuild \
    -scheme InkPaper \
    -project InkPaper.xcodeproj \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA" \
    -destination 'generic/platform=macOS' \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGNING_REQUIRED=NO \
    build
fi

APP="${DERIVED_DATA}/Build/Products/${CONFIGURATION}/${APP_NAME}"
if [[ ! -d "$APP" ]]; then
  echo "error: app not found at $APP" >&2
  exit 1
fi
if [[ ! -f "$BACKGROUND_SRC" ]]; then
  echo "error: background not found at $BACKGROUND_SRC" >&2
  exit 1
fi

mkdir -p dist
WORK="$(mktemp -d "${TMPDIR:-/tmp}/inkpaper-dmg.XXXXXX")"
STAGE="${WORK}/stage"
RW_DMG="${WORK}/rw.dmg"
FINAL_DMG="dist/${DMG_NAME}"
MOUNTED=""

cleanup() {
  if [[ -n "$MOUNTED" ]]; then
    hdiutil detach "$MOUNTED" -quiet -force 2>/dev/null || true
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT

echo "==> Staging volume contents…"
mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp "$BACKGROUND_SRC" "$STAGE/.background/$BACKGROUND_NAME"
# Hide support folder from Finder icon view
if command -v SetFile >/dev/null 2>&1; then
  SetFile -a V "$STAGE/.background" || true
else
  chflags hidden "$STAGE/.background" || true
fi

echo "==> Creating read-write DMG…"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGE" \
  -fs HFS+ \
  -fsargs "-c c=64,a=16,e=16" \
  -format UDRW \
  -ov \
  "$RW_DMG" >/dev/null

echo "==> Mounting…"
MOUNTED="$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG" | awk '/\/Volumes\//{print $NF; exit}')"
VOL="/Volumes/${VOLUME_NAME}"
for _ in $(seq 1 50); do
  [[ -d "$VOL" ]] && break
  sleep 0.1
done
if [[ ! -d "$VOL" ]]; then
  echo "error: volume not mounted at $VOL" >&2
  exit 1
fi
MOUNTED="$VOL"

echo "==> Applying Finder layout…"
sleep 1
osascript <<EOF
tell application "Finder"
  tell disk "$VOLUME_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, $((200 + WINDOW_WIDTH)), $((120 + WINDOW_HEIGHT))}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to $ICON_SIZE
    set background picture of viewOptions to file ".background:$BACKGROUND_NAME"
    set position of item "$APP_NAME" of container window to {$APP_ICON_X, $APP_ICON_Y}
    set position of item "Applications" of container window to {$APPS_ICON_X, $APPS_ICON_Y}
    update without registering applications
    delay 1
    close
    open
    delay 1
    set the bounds of container window to {200, 120, $((200 + WINDOW_WIDTH)), $((120 + WINDOW_HEIGHT))}
    close
  end tell
end tell
EOF

sync
sleep 1

echo "==> Detaching…"
hdiutil detach "$VOL" -quiet
MOUNTED=""

echo "==> Compressing…"
rm -f "$FINAL_DMG"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$FINAL_DMG" >/dev/null
xattr -cr "$FINAL_DMG" 2>/dev/null || true

echo "==> Done: $ROOT/$FINAL_DMG"
ls -lh "$FINAL_DMG"
