#!/bin/zsh
# Builds "Time Zones.app" (universal: Apple silicon + Intel) with only the Xcode Command Line Tools.
#   ./build.sh            build into build/
#   ./build.sh install    build, copy to /Applications and open it
set -euo pipefail
cd "${0:A:h}"

NAME="Time Zones"
EXE="TimeZones"
VERSION="1.0"
BUILD_NUMBER="1"
MIN_OS="13.0"
APP="build/$NAME.app"

rm -rf build && mkdir -p build
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -parse-as-library -target "$arch-apple-macos$MIN_OS" \
    Sources/*.swift -o "build/$EXE-$arch"
done

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "build/$EXE-arm64" "build/$EXE-x86_64" -output "$APP/Contents/MacOS/$EXE"
cp Resources/cities.txt Resources/AppIcon.icns "$APP/Contents/Resources/"
cp -R Resources/flags "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>io.github.danpune.timezones</string>
  <key>CFBundleExecutable</key><string>$EXE</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_OS</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT licensed. City data GeoNames, CC BY 4.0.</string>
</dict></plist>
PLIST

# Ad-hoc signature: runs on this Mac. Sharing it with others needs a Developer ID + notarization.
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
  pkill -x "$EXE" 2>/dev/null || true
  rm -rf "/Applications/$NAME.app"
  cp -R "$APP" /Applications/
  open "/Applications/$NAME.app"
  echo "Installed to /Applications and opened"
fi
