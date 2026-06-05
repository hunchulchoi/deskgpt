#!/bin/bash
set -e

# Reset build folder directory
rm -rf build
mkdir -p build/DeskGPT.app/Contents/MacOS
mkdir -p build/DeskGPT.app/Contents/Resources

# 1. Automate macOS ICNS App Icon bundle generation from flat high-res PNG
echo "🎨 플랫 앱 아이콘 생성 중..."
ICON_SRC=".github/assets/icon.png"
ICONSET_DIR=$(mktemp -d /private/tmp/deskgpt-icon.XXXXXX.iconset)
NORMALIZED_DIR=$(mktemp -d /private/tmp/deskgpt-icon-src.XXXXXX)
SWIFT_MODULE_CACHE_DIR=$(mktemp -d /private/tmp/deskgpt-swift-module-cache.XXXXXX)
trap 'rm -rf "$ICONSET_DIR" "$NORMALIZED_DIR" "$SWIFT_MODULE_CACHE_DIR"' EXIT

# Normalize the source image first so iconutil does not choke on metadata or
# unexpected source formats masquerading as PNGs.
NORMALIZED_ICON="$NORMALIZED_DIR/source.png"
sips -s format png "$ICON_SRC" --out "$NORMALIZED_ICON" >/dev/null

sips -s format png -z 16 16     "$NORMALIZED_ICON" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -s format png -z 32 32     "$NORMALIZED_ICON" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -s format png -z 32 32     "$NORMALIZED_ICON" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -s format png -z 64 64     "$NORMALIZED_ICON" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -s format png -z 128 128   "$NORMALIZED_ICON" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -s format png -z 256 256   "$NORMALIZED_ICON" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -s format png -z 256 256   "$NORMALIZED_ICON" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -s format png -z 512 512   "$NORMALIZED_ICON" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -s format png -z 512 512   "$NORMALIZED_ICON" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
sips -s format png -z 1024 1024 "$NORMALIZED_ICON" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null

if ! iconutil -c icns "$ICONSET_DIR" -o build/DeskGPT.app/Contents/Resources/AppIcon.icns; then
    echo "⚠️  iconutil failed; falling back to the system generic application icon."
    cp /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns \
       build/DeskGPT.app/Contents/Resources/AppIcon.icns
fi

# 2. Copy metadata settings plist file
cp src/Info.plist build/DeskGPT.app/Contents/Info.plist
plutil -replace CFBundleVersion -string "$(date +%Y%m%d%H%M%S)" build/DeskGPT.app/Contents/Info.plist

# 3. Swift high-performance compile & pack
echo "🚀 Swift 파일 고속 컴파일 및 패키징..."
swiftc src/DeskGPTViewController.swift \
       src/DeskGPTPDFViewController.swift \
       src/UpdateInstaller.swift \
       src/UpdateManager.swift \
       src/PreferencesWindowController.swift \
       src/AppDelegate.swift \
       src/main.swift \
       -module-cache-path "$SWIFT_MODULE_CACHE_DIR" \
       -o build/DeskGPT.app/Contents/MacOS/DeskGPT \
       -framework Cocoa -framework WebKit -framework PDFKit

# 4. Install into /Applications so Finder/LaunchServices can pick up the latest build
echo "📦 /Applications/DeskGPT.app 으로 복사 중..."
ditto build/DeskGPT.app /Applications/DeskGPT.app

echo "🔧 LaunchServices에 DeskGPT 등록 중..."
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f /Applications/DeskGPT.app

echo "🧹 Dock 캐시 갱신 중..."
touch /Applications/DeskGPT.app
touch /Applications/DeskGPT.app/Contents/Info.plist
killall Dock >/dev/null 2>&1 || true

echo "🎉 DeskGPT.app 빌드 및 설치 성공! 경로: /Applications/DeskGPT.app"
