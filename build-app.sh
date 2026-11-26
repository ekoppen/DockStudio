#!/bin/bash
# Bouwt DockStudio.app (menubalk-app zonder eigen Dock-icoon)
set -e
cd "$(dirname "$0")"

swift build -c release

APP="DockStudio.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/DockStudio "$APP/Contents/MacOS/DockStudio"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>DockStudio</string>
  <key>CFBundleIdentifier</key><string>nl.doorkoppen.dockstudio</string>
  <key>CFBundleExecutable</key><string>DockStudio</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/></dict>
  <key>NSLocalNetworkUsageDescription</key><string>DockStudio verbindt met je Home Assistant op het lokale netwerk.</string>
</dict>
</plist>
EOF

codesign --force --sign - "$APP" 2>/dev/null || true
echo "Klaar: $(pwd)/$APP"
