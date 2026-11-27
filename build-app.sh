#!/bin/bash
# Bouwt Dokko.app (menubalk-app zonder eigen Dock-icoon)
# Gebruik: ./build-app.sh [versie]   (standaard 0.9)
set -e
VERSION="${1:-0.9}"
cd "$(dirname "$0")"

swift build -c release

APP="Dokko.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Dokko "$APP/Contents/MacOS/Dokko"

# App-icoon: Resources/AppIcon.png (1024x1024) -> AppIcon.icns
mkdir -p "$APP/Contents/Resources"
if [ -f Resources/AppIcon.png ]; then
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Dokko</string>
  <key>CFBundleIdentifier</key><string>nl.doorkoppen.dockstudio</string>
  <key>CFBundleExecutable</key><string>Dokko</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSUIElement</key><true/>
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/></dict>
  <key>NSLocalNetworkUsageDescription</key><string>Dokko verbindt met je Home Assistant op het lokale netwerk.</string>
</dict>
</plist>
EOF

codesign --force --sign - "$APP" 2>/dev/null || true
echo "Klaar: $(pwd)/$APP"
