#!/bin/bash
# Builds AltTab.app (universal, ad-hoc signed) plus AltTab.zip and AltTab.dmg.
set -euo pipefail
cd "$(dirname "$0")"

SCRATCH="${ALTTAB_SCRATCH:-.build}"
DIST="dist"
APP="$DIST/AltTab.app"

echo "==> Compiling (release)"
if swift build -c release --arch arm64 --arch x86_64 --scratch-path "$SCRATCH" 2>/dev/null; then
  BIN="$SCRATCH/apple/Products/Release/AltTab"
  echo "    universal (arm64 + x86_64)"
else
  echo "    universal build unavailable, falling back to native arch"
  swift build -c release --scratch-path "$SCRATCH"
  BIN="$(swift build -c release --scratch-path "$SCRATCH" --show-bin-path)/AltTab"
fi

echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/AltTab"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Ad-hoc signing"
codesign --force --deep --sign - --timestamp=none "$APP"
codesign --verify --deep --strict "$APP" && echo "    signature ok"

echo "==> Packaging"
rm -f "$DIST/AltTab.zip" "$DIST/AltTab.dmg"
( cd "$DIST" && ditto -c -k --sequesterRsrc --keepParent AltTab.app AltTab.zip )

STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname AltTab -srcfolder "$STAGE" -ov -format UDZO "$DIST/AltTab.dmg" >/dev/null
rm -rf "$STAGE"

echo
echo "Built:"
ls -lh "$APP/Contents/MacOS/AltTab" "$DIST/AltTab.zip" "$DIST/AltTab.dmg" | awk '{print "  " $5 "\t" $9}'
lipo -archs "$APP/Contents/MacOS/AltTab" | sed 's/^/  archs: /'
