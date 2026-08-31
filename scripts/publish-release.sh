#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Packaging/Info.plist")}"
RELEASE_DIR="$ROOT_DIR/release"
UPDATES_DIR="$RELEASE_DIR/updates"
DMG_NAME="NotchFuel-$VERSION-arm64.dmg"
DMG_PATH="$RELEASE_DIR/$DMG_NAME"
NOTES_PATH="$ROOT_DIR/Packaging/ReleaseNotes/$VERSION.md"
SPARKLE_TOOLS="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin"
TAG="v$VERSION"

cd "$ROOT_DIR"

if [[ -n "$(git status --porcelain)" ]]; then
    print -u2 "Commit and push source changes before publishing a release."
    exit 1
fi

if [[ ! -f "$NOTES_PATH" ]]; then
    print -u2 "Missing release notes: $NOTES_PATH"
    exit 1
fi

gh auth status >/dev/null
./scripts/build-release.sh

mkdir -p "$UPDATES_DIR"
cp "$DMG_PATH" "$UPDATES_DIR/$DMG_NAME"
cp "$NOTES_PATH" "$UPDATES_DIR/NotchFuel-$VERSION-arm64.md"

"$SPARKLE_TOOLS/generate_appcast" \
    --download-url-prefix "https://github.com/bhzdcz/notchfuel/releases/download/$TAG/" \
    --embed-release-notes \
    --link "https://github.com/bhzdcz/notchfuel" \
    --versions "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ROOT_DIR/Packaging/Info.plist")" \
    "$UPDATES_DIR"

cp "$UPDATES_DIR/appcast.xml" "$ROOT_DIR/appcast.xml"

gh release create "$TAG" "$DMG_PATH" \
    --repo bhzdcz/notchfuel \
    --title "NotchFuel $VERSION" \
    --notes-file "$NOTES_PATH" \
    --target main

git add appcast.xml
git commit -m "Publish appcast for $TAG"
git push origin main

print "Published https://github.com/bhzdcz/notchfuel/releases/tag/$TAG"
