#!/bin/bash
set -euo pipefail
PROJECT="$(cd "$(dirname "$0")" && pwd)"
BUILD_ROOT="${COMPUTEDOCK_BUILD_ROOT:-$PROJECT/.build-local}"
mkdir -p "$BUILD_ROOT"
export CLANG_MODULE_CACHE_PATH="$BUILD_ROOT/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_ROOT/swift-cache"
FLAGS=(--package-path "$PROJECT" --build-system native --disable-sandbox --scratch-path "$BUILD_ROOT/swift" --cache-path "$BUILD_ROOT/pm-cache" --config-path "$BUILD_ROOT/pm-config" --security-path "$BUILD_ROOT/pm-security")
swift build "${FLAGS[@]}"
BIN="$(swift build "${FLAGS[@]}" --show-bin-path)"
python3 - "$PROJECT" "$BUILD_ROOT" <<'PY'
from pathlib import Path
import sys
project, build = map(Path, sys.argv[1:])
source = (project / "Tests/ComputeDockTests/ModelTests.swift").read_text()
source = source.replace("import XCTest\n", "import Foundation\n").replace("@testable import ComputeDock\n", "")
(build / "ModelTests.swift").write_text(source)
PY
swiftc -parse-as-library -module-cache-path "$BUILD_ROOT/swift-cache" \
    "$PROJECT/Sources/ComputeDock/Models.swift" \
    "$PROJECT/Sources/ComputeDock/PasswordBroker.swift" \
    "$BUILD_ROOT/ModelTests.swift" "$PROJECT/Tests/PortableTestSupport.swift" \
    -o "$BIN/ComputeDockChecks"
"$BIN/ComputeDockChecks"
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s "$PROJECT/Tests" -p 'test_*.py' -v
