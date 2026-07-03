#!/bin/bash
# install.sh
# Packages the built executable into a proper .app bundle and installs it
# in ~/Applications. After running this, clicking notifications opens the browser.
#
# Usage:
#   1. swift build -c release
#   2. bash install.sh
#   3. Done — the app runs from ~/Applications/BlameTheGuilty.app

set -euo pipefail

APP_NAME="BlameTheGuilty"
INSTALL_DIR="$HOME/Applications"
APP_BUNDLE="$INSTALL_DIR/$APP_NAME.app"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INFO_PLIST="$SCRIPT_DIR/Sources/$APP_NAME/Info.plist"

echo "🔍 Searching for the latest build..."

# Prefer swift build output, fall back to Xcode DerivedData
EXECUTABLE=""
if [ -f ".build/release/$APP_NAME" ]; then
  EXECUTABLE="$(pwd)/.build/release/$APP_NAME"
  echo "  → swift build -c release: $EXECUTABLE"
elif [ -f ".build/debug/$APP_NAME" ]; then
  EXECUTABLE="$(pwd)/.build/debug/$APP_NAME"
  echo "  → swift build (debug): $EXECUTABLE"
else
  EXECUTABLE=$(
    find "$HOME/Library/Developer/Xcode/DerivedData" \
         -name "$APP_NAME" \
         -path "*/Release/$APP_NAME" \
         ! -name "*.app" \
         2>/dev/null \
    | xargs ls -t 2>/dev/null \
    | head -1
  )
  if [ -z "$EXECUTABLE" ]; then
    EXECUTABLE=$(
      find "$HOME/Library/Developer/Xcode/DerivedData" \
           -name "$APP_NAME" \
           -path "*/Debug/$APP_NAME" \
           ! -name "*.app" \
           2>/dev/null \
      | xargs ls -t 2>/dev/null \
      | head -1
    )
  fi
  if [ -n "$EXECUTABLE" ]; then
    echo "  → Xcode: $EXECUTABLE"
  fi
fi

if [ -z "$EXECUTABLE" ]; then
  echo "❌  Executable not found. Run 'swift build -c release' or build in Xcode first."
  exit 1
fi

echo "📦  Found: $EXECUTABLE"

# ── Create .app bundle structure ──────────────────────────────────────────────
mkdir -p "$INSTALL_DIR"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$EXECUTABLE"  "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$INFO_PLIST"  "$APP_BUNDLE/Contents/Info.plist"

chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# ── Register with Launch Services ─────────────────────────────────────────────
# This is what makes UNUserNotificationCenter work and notification clicks
# route back to our app instead of Script Editor.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -f "$APP_BUNDLE" 2>/dev/null || true

echo "✅  Installed → $APP_BUNDLE"

# ── Relaunch ──────────────────────────────────────────────────────────────────
echo "🚀  Relaunching from bundle..."
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 0.5
open "$APP_BUNDLE"

echo ""
echo "Done. From now on BlameTheGuilty runs as a proper .app."
echo "Notification clicks will open the workflow in your browser."

