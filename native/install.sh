#!/bin/bash
# install.sh
# Builds the btg Xcode project and installs it in ~/Applications.
#
# Usage:
#   bash install.sh
#   (opens Xcode or builds automatically)

set -e

APP_NAME="btg"
INSTALL_DIR="$HOME/Applications"
APP_BUNDLE="$INSTALL_DIR/$APP_NAME.app"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "🔍 Building btg…"

if xcodebuild -project "$SCRIPT_DIR/btg.xcodeproj" -scheme "$APP_NAME" -configuration Release build; then
  echo "  ✅ Build succeeded"
else
  echo "  ⚠️  Xcode CLI build failed, falling back to existing build…"
fi

# Find the built .app in DerivedData (prefer Release, fallback to Debug)
XC_APP=$(find "$HOME/Library/Developer/Xcode/DerivedData" -name "$APP_NAME.app" -path "*/Release/*" 2>/dev/null | head -1)
if [ -z "$XC_APP" ]; then
  XC_APP=$(find "$HOME/Library/Developer/Xcode/DerivedData" -name "$APP_NAME.app" -path "*/Debug/*" 2>/dev/null | head -1)
fi

if [ -z "$XC_APP" ]; then
  echo "❌  btg.app not found."
  echo ""
  echo "Open the project in Xcode and build (⌘B), then run this script again:"
  echo "  open \"$SCRIPT_DIR/btg.xcodeproj\""
  exit 1
fi

echo "  Found: $XC_APP"

# ── Install ────────────────────────────────────────────────────────────────────
mkdir -p "$INSTALL_DIR"
rm -rf "$APP_BUNDLE"
cp -R "$XC_APP" "$APP_BUNDLE"

# ── Register with Launch Services ─────────────────────────────────────────────
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -f "$APP_BUNDLE" 2>/dev/null || true

echo "✅  Installed → $APP_BUNDLE"

# ── Relaunch ──────────────────────────────────────────────────────────────────
echo "  Relaunching from bundle..."
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 0.5
open "$APP_BUNDLE"

echo ""
echo "Done. btg now runs from ~/Applications as a proper .app."
