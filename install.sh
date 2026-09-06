#!/bin/bash
set -e

APP_NAME="Hidecons"
APP_DIR="$HOME/Applications/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "🔨 Compiling $APP_NAME..."
swiftc -O -o "/tmp/$APP_NAME" "$SCRIPT_DIR/Hidecons.swift" -framework Cocoa -framework ServiceManagement

echo "🎨 Generating app icon..."
swiftc -O -o /tmp/hidecons_icongen "$SCRIPT_DIR/generate_icon.swift" -framework Cocoa
/tmp/hidecons_icongen
iconutil -c icns /tmp/AppIcon.iconset -o /tmp/AppIcon.icns

echo "📦 Creating app bundle..."
mkdir -p "$MACOS"
mkdir -p "$RESOURCES"

cp "/tmp/$APP_NAME"     "$MACOS/$APP_NAME"
cp "/tmp/AppIcon.icns"  "$RESOURCES/AppIcon.icns"

cat > "$CONTENTS/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Hidecons</string>
    <key>CFBundleIdentifier</key>
    <string>com.hidecons.app</string>
    <key>CFBundleVersion</key>
    <string>1.6</string>
    <key>CFBundleExecutable</key>
    <string>Hidecons</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

echo "✅ Installed to $APP_DIR"
echo ""
echo "🚀 Launching..."
open "$APP_DIR"
echo ""
echo "Grid icon is now in your menu bar."
echo "  Left click  → toggle desktop icons instantly"
echo "  Right click → settings (Launch at Login, Quit)"
