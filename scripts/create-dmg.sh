#!/bin/bash
set -euo pipefail

# ============================================================
# ClawDeck — Create DMG for Distribution
# ============================================================
#
# Usage:
#   ./scripts/create-dmg.sh <version> [path/to/ClawDeck.app]
#
# Examples:
#   ./scripts/create-dmg.sh 0.1.0
#   ./scripts/create-dmg.sh 0.1.0 ~/Desktop/ClawDeck.app
#   ./scripts/create-dmg.sh 0.2.0 ~/Library/Developer/Xcode/Archives/...
#
# The script expects a signed, notarized, and stapled ClawDeck.app.
# If no path is given, it looks in the current directory.
#
# Output: dist/ClawDeck-<version>.dmg
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DIST_DIR="$PROJECT_DIR/dist"
APP_NAME="ClawDeck"

# ---- Parse arguments ----

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <version> [path/to/ClawDeck.app]"
    echo ""
    echo "Examples:"
    echo "  $0 0.1.0"
    echo "  $0 0.1.0 ~/Desktop/ClawDeck.app"
    exit 1
fi

VERSION="$1"
APP_PATH="${2:-$PROJECT_DIR/$APP_NAME.app}"

# ---- Validate .app ----

if [[ ! -d "$APP_PATH" ]]; then
    echo "❌ ClawDeck.app not found at: $APP_PATH"
    echo ""
    echo "Export it from Xcode Organizer:"
    echo "  Window → Organizer → Distribute App → Developer ID → Export"
    echo ""
    echo "Then pass the path:"
    echo "  $0 $VERSION /path/to/ClawDeck.app"
    exit 1
fi

echo "📦 Creating DMG for ClawDeck v${VERSION}"
echo "   App: $APP_PATH"

# ---- Verify code signing ----

echo ""
echo "🔍 Verifying code signature..."
if codesign --verify --deep --strict "$APP_PATH" 2>/dev/null; then
    SIGN_INFO=$(codesign -dvv "$APP_PATH" 2>&1 | grep "Authority=" | head -1 || true)
    echo "   ✅ Signed: ${SIGN_INFO:-OK}"
else
    echo "   ⚠️  Warning: app is not properly signed"
    echo "   Distribution may trigger Gatekeeper warnings"
    read -p "   Continue anyway? [y/N] " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] || exit 1
fi

# ---- Check notarization staple ----

if xcrun stapler validate "$APP_PATH" 2>/dev/null; then
    echo "   ✅ Notarization ticket stapled"
else
    echo "   ⚠️  Warning: no notarization ticket found"
    echo "   Users may see Gatekeeper warnings on first launch"
fi

# ---- Create staging directory ----

STAGING_DIR=$(mktemp -d)
trap 'rm -rf "$STAGING_DIR"' EXIT

echo ""
echo "🔨 Staging DMG contents..."

# Copy the app
cp -R "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"

# Create Applications symlink (drag-to-install)
ln -s /Applications "$STAGING_DIR/Applications"

# ---- Create DMG ----

DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"

echo "💿 Creating $DMG_NAME..."

hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH" \
    2>/dev/null

DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)

# ---- Generate checksum ----

echo "🔐 Generating checksum..."
CHECKSUM=$(shasum -a 256 "$DMG_PATH" | cut -d ' ' -f 1)

# ---- Summary ----

echo ""
echo "============================================"
echo "  🎉 DMG created successfully!"
echo "============================================"
echo ""
echo "  File:     dist/$DMG_NAME"
echo "  Size:     $DMG_SIZE"
echo "  SHA-256:  $CHECKSUM"
echo ""
echo "  Upload to GitHub Releases:"
echo "    gh release create v${VERSION} \\"
echo "      --title \"ClawDeck v${VERSION}\" \\"
echo "      --notes \"...\" \\"
echo "      \"$DMG_PATH\""
echo ""
echo "  Add to release notes:"
echo "    **SHA-256:** \`$CHECKSUM\`"
echo ""
