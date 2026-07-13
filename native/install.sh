#!/bin/bash
# install.sh
# Builds the BlameTheGuilty Xcode project and installs it in ~/Applications.
#
# Usage:
#   bash install.sh
#   (opens Xcode or builds automatically)

set -e

APP_NAME="BlameTheGuilty"
INSTALL_DIR="$HOME/Applications"
APP_BUNDLE="$INSTALL_DIR/$APP_NAME.app"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "🔍 Building BlameTheGuilty…"

if ! xcodebuild -project "$SCRIPT_DIR/btg.xcodeproj" -scheme "$APP_NAME" -configuration Release build; then
  echo "  ⚠️  Xcode CLI build failed, falling back to existing build…"
fi

# Find the most recently built .app in DerivedData
XC_APP=$(find "$HOME/Library/Developer/Xcode/DerivedData" \
    -name "$APP_NAME.app" -path "*/Release/*" \
    2>/dev/null | while IFS= read -r app; do
    echo "$(stat -f%m "$app/Contents/MacOS/$APP_NAME" 2>/dev/null) $app"
done | sort -rn | head -1 | cut -d' ' -f2-)

if [ -z "$XC_APP" ]; then
  echo "❌  BlameTheGuilty.app not found. Open the project in Xcode and run Product → Archive or build Release first."
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
echo "Done. BlameTheGuilty now runs from ~/Applications as a proper .app."
