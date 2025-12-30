#!/bin/bash
set -e

APP_NAME="PRReviewManager"
BUNDLE_ID="com.seg4lt.prmaster"
BUILD_DIR=".build/release"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
ASSETS_DIR="Sources/PRReviewManager/Resources/Assets.xcassets"

echo "Building release..."
swift build -c release

echo "Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy executable
cp "$BUILD_DIR/PRReviewManager" "$APP_DIR/Contents/MacOS/"

# Compile asset catalog (includes app icon)
echo "Compiling assets..."
xcrun actool "$ASSETS_DIR" \
    --compile "$APP_DIR/Contents/Resources" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$BUILD_DIR/assets-info.plist" \
    2>/dev/null || echo "Warning: actool failed, icon may not work"

# Create Info.plist
cat > "$APP_DIR/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>PRReviewManager</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSUserNotificationAlertStyle</key>
    <string>banner</string>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
</dict>
</plist>
EOF

# Ad-hoc sign the app (required for notifications)
echo "Signing app..."
codesign --force --deep --sign - "$APP_DIR"

echo "Done! App bundle created at: $APP_DIR"
echo ""
echo "To run: open \"$APP_DIR\""
echo "To install: cp -r \"$APP_DIR\" /Applications/"
