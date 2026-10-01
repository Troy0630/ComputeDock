#!/bin/bash
set -euo pipefail
PROJECT="$(cd "$(dirname "$0")" && pwd)"
BUILD_ROOT="${COMPUTEDOCK_BUILD_ROOT:-$PROJECT/.build-local}"
APP="${1:-$PROJECT/../ComputeDock.app}"
mkdir -p "$BUILD_ROOT"
export CLANG_MODULE_CACHE_PATH="$BUILD_ROOT/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_ROOT/swift-cache"
FLAGS=(--package-path "$PROJECT" --build-system native --disable-sandbox --scratch-path "$BUILD_ROOT/swift" --cache-path "$BUILD_ROOT/pm-cache" --config-path "$BUILD_ROOT/pm-config" --security-path "$BUILD_ROOT/pm-security" -c release)
swift build "${FLAGS[@]}"
BIN="$(swift build "${FLAGS[@]}" --show-bin-path)"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/ComputeDock" "$APP/Contents/MacOS/ComputeDock"
cp "$BIN/ComputeDockAskPass" "$APP/Contents/MacOS/ComputeDockAskPass"
ditto "$BIN/ComputeDock_ComputeDock.bundle" "$APP/Contents/Resources/ComputeDock_ComputeDock.bundle"
cp "$PROJECT/Build/Info.plist" "$APP/Contents/Info.plist"
swift "$PROJECT/Build/Icon.swift" "$BUILD_ROOT/AppIcon.png"
ICONSET="$BUILD_ROOT/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$BUILD_ROOT/AppIcon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$BUILD_ROOT/AppIcon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
python3 - "$ICONSET" "$APP/Contents/Resources/AppIcon.icns" <<'PY'
from pathlib import Path
import struct
import sys
folder, output = map(Path, sys.argv[1:])
chunks = []
for kind, file in [(b'icp4', 'icon_16x16.png'), (b'icp5', 'icon_32x32.png'), (b'icp6', 'icon_32x32@2x.png'), (b'ic07', 'icon_128x128.png'), (b'ic08', 'icon_256x256.png'), (b'ic09', 'icon_512x512.png'), (b'ic10', 'icon_512x512@2x.png'), (b'ic11', 'icon_16x16@2x.png'), (b'ic12', 'icon_32x32@2x.png'), (b'ic13', 'icon_128x128@2x.png'), (b'ic14', 'icon_256x256@2x.png')]:
    data = (folder / file).read_bytes()
    chunks.append(kind + struct.pack('>I', len(data) + 8) + data)
body = b''.join(chunks)
output.write_bytes(b'icns' + struct.pack('>I', len(body) + 8) + body)
PY
codesign --force --sign - "$APP/Contents/MacOS/ComputeDockAskPass"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "Built: $APP"
