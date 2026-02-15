#!/bin/bash
set -euo pipefail

# ============================================================
# ClawDeck — Build & Package for macOS Distribution
# ============================================================
#
# Usage:
#   ./scripts/build-app.sh              # Build unsigned .app
#   ./scripts/build-app.sh --sign       # Build + ad-hoc code sign
#   ./scripts/build-app.sh --sign-id    # Build + sign with Developer ID
#
# Output: dist/ClawDeck.app and dist/ClawDeck.zip
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build/release"
DIST_DIR="$PROJECT_DIR/dist"
APP_NAME="ClawDeck"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
BUNDLE_ID="com.1devstudio.clawdeck"
VERSION="0.1.0"
BUILD_NUMBER="1"

SIGN_MODE="none"
if [[ "${1:-}" == "--sign" ]]; then
    SIGN_MODE="adhoc"
elif [[ "${1:-}" == "--sign-id" ]]; then
    SIGN_MODE="developer-id"
fi

echo "🔨 Building ClawDeck (release)..."
cd "$PROJECT_DIR"
swift build -c release 2>&1 | tail -5

# Verify the binary exists
BINARY="$BUILD_DIR/clawdeck"
if [[ ! -f "$BINARY" ]]; then
    echo "❌ Build failed — binary not found at $BINARY"
    exit 1
fi
echo "✅ Binary built: $(du -h "$BINARY" | cut -f1)"

# ---- Create .app bundle structure ----
echo "📦 Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy app icon (if available)
ICON_SRC="$PROJECT_DIR/icons/app-icon-2.png"
if [[ -f "$ICON_SRC" ]]; then
    # Convert PNG to icns using sips + iconutil
    ICONSET_DIR=$(mktemp -d)/ClawDeck.iconset
    mkdir -p "$ICONSET_DIR"
    
    sips -z 16 16     "$ICON_SRC" --out "$ICONSET_DIR/icon_16x16.png"    > /dev/null 2>&1
    sips -z 32 32     "$ICON_SRC" --out "$ICONSET_DIR/icon_16x16@2x.png" > /dev/null 2>&1
    sips -z 32 32     "$ICON_SRC" --out "$ICONSET_DIR/icon_32x32.png"    > /dev/null 2>&1
    sips -z 64 64     "$ICON_SRC" --out "$ICONSET_DIR/icon_32x32@2x.png" > /dev/null 2>&1
    sips -z 128 128   "$ICON_SRC" --out "$ICONSET_DIR/icon_128x128.png"  > /dev/null 2>&1
    sips -z 256 256   "$ICON_SRC" --out "$ICONSET_DIR/icon_128x128@2x.png" > /dev/null 2>&1
    sips -z 256 256   "$ICON_SRC" --out "$ICONSET_DIR/icon_256x256.png"  > /dev/null 2>&1
    sips -z 512 512   "$ICON_SRC" --out "$ICONSET_DIR/icon_256x256@2x.png" > /dev/null 2>&1
    sips -z 512 512   "$ICON_SRC" --out "$ICONSET_DIR/icon_512x512.png"  > /dev/null 2>&1
    sips -z 1024 1024 "$ICON_SRC" --out "$ICONSET_DIR/icon_512x512@2x.png" > /dev/null 2>&1
    
    iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns" 2>/dev/null && \
        echo "✅ App icon created" || \
        echo "⚠️  Could not create .icns (iconutil not available)"
    
    rm -rf "$(dirname "$ICONSET_DIR")"
fi

# Copy SPM resources bundle (contains assets catalog, etc.)
RESOURCE_BUNDLE="$BUILD_DIR/clawdeck_clawdeck.bundle"
if [[ -d "$RESOURCE_BUNDLE" ]]; then
    cp -R "$RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
    echo "✅ Resources bundle copied"
fi

# ---- Create Info.plist ----
cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>ClawDeck</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
</dict>
</plist>
EOF
echo "✅ Info.plist created"

# ---- Code Signing ----
case "$SIGN_MODE" in
    adhoc)
        echo "🔏 Ad-hoc signing..."
        codesign --force --deep --sign - "$APP_BUNDLE"
        echo "✅ Ad-hoc signed (testers: right-click → Open)"
        ;;
    developer-id)
        echo "🔏 Signing with Developer ID..."
        # Find the first Developer ID Application identity
        IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/')
        if [[ -z "$IDENTITY" ]]; then
            echo "❌ No Developer ID Application certificate found in keychain"
            echo "   Falling back to ad-hoc signing"
            codesign --force --deep --sign - "$APP_BUNDLE"
        else
            echo "   Using: $IDENTITY"
            codesign --force --deep --options runtime --sign "$IDENTITY" "$APP_BUNDLE"
            echo "✅ Signed with Developer ID"
            echo ""
            echo "📋 To notarize (optional, removes Gatekeeper warnings):"
            echo "   xcrun notarytool submit dist/ClawDeck.zip --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID --password APP_SPECIFIC_PASSWORD --wait"
            echo "   xcrun stapler staple dist/ClawDeck.app"
        fi
        ;;
    *)
        echo "⚠️  Unsigned build (testers: right-click → Open to launch)"
        ;;
esac

# ---- Package as .zip ----
echo "📦 Creating zip..."
cd "$DIST_DIR"
rm -f "$APP_NAME.zip"
ditto -c -k --keepParent "$APP_NAME.app" "$APP_NAME.zip"
ZIP_SIZE=$(du -h "$APP_NAME.zip" | cut -f1)
echo "✅ dist/$APP_NAME.zip ($ZIP_SIZE)"

echo ""
echo "============================================"
echo "  🎉 Build complete!"
echo "  App:  dist/$APP_NAME.app"
echo "  Zip:  dist/$APP_NAME.zip"
echo "============================================"
echo ""
echo "To test locally:  open dist/$APP_NAME.app"
echo "To distribute:    share dist/$APP_NAME.zip"
if [[ "$SIGN_MODE" == "none" ]]; then
    echo ""
    echo "⚠️  Unsigned — tell testers to:"
    echo "    1. Unzip ClawDeck.zip"
    echo "    2. Right-click ClawDeck.app → Open"
    echo "    3. Click 'Open' in the security dialog"
fi
