#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
BUILD_DIR="$ROOT_DIR/build"
RELEASE_DIR="$ROOT_DIR/release"
APP_NAME="NotchFuel"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DMG_PATH="$RELEASE_DIR/NotchFuel-1.3.0-arm64.dmg"
ASSET_CATALOG="$BUILD_DIR/Assets.xcassets"
STAGING="$BUILD_DIR/dmg"

cd "$ROOT_DIR"
export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_DIR/module-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH"
swift build --disable-sandbox -c release --arch arm64

rm -rf "$APP_BUNDLE" "$ASSET_CATALOG" "$STAGING"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" "$RELEASE_DIR" "$STAGING"

cp ".build/arm64-apple-macosx/release/NotchFuel" "$APP_BUNDLE/Contents/MacOS/NotchFuel"
cp "Packaging/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

mkdir -p "$ASSET_CATALOG/AppIcon.appiconset"
swift "scripts/generate-icon.swift" "$ASSET_CATALOG/AppIcon.appiconset"
cp "Packaging/AppIconContents.json" "$ASSET_CATALOG/AppIcon.appiconset/Contents.json"
cp "Packaging/AssetsContents.json" "$ASSET_CATALOG/Contents.json"
xcrun actool \
    --compile "$APP_BUNDLE/Contents/Resources" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$BUILD_DIR/asset-info.plist" \
    "$ASSET_CATALOG"

codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

cp -R "$APP_BUNDLE" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH"

echo "$APP_BUNDLE"
echo "$DMG_PATH"
