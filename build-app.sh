#!/bin/zsh
# Compila y empaqueta "Firma Digital.app" (y la herramienta firmar-cli).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --arch arm64 --arch x86_64
BIN=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)

APP="dist/Firma Digital.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/FirmaDigital" "$APP/Contents/MacOS/FirmaDigital"
cp "$BIN/firmar-cli" dist/firmar-cli

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Firma Digital</string>
    <key>CFBundleDisplayName</key><string>Firma Digital</string>
    <key>CFBundleIdentifier</key><string>com.digisoft.firmadigital</string>
    <key>CFBundleExecutable</key><string>FirmaDigital</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>2.0</string>
    <key>CFBundleVersion</key><string>2</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.business</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict>
</plist>
EOF

codesign --force --deep --sign - "$APP"
codesign --force --sign - dist/firmar-cli
echo "Listo: $(pwd)/$APP"
