#!/usr/bin/env bash
# Builds and runs the macOS smoke test against CesiumNative.xcframework.
# Usage: smoke/build.sh [path/to/CesiumNative.xcframework]
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
xcf="${1:-${CESIUM_BUILD_ROOT:-$HOME/.cache/cesium-native-xcframework}/out/CesiumNative.xcframework}"
inc="$(ls -d "$xcf"/macos-arm64/Headers)"
lib="$(ls "$xcf"/macos-arm64/*.a)"
out="$here/build"; mkdir -p "$out"
xcrun clang++ -std=c++20 -arch arm64 -mmacosx-version-min=15.0 -fobjc-arc -O1 \
  -DGLM_FORCE_XYZW_ONLY -DGLM_FORCE_EXPLICIT_CTOR -DGLM_FORCE_INTRINSICS \
  -DGLM_ENABLE_EXPERIMENTAL -DLIBASYNC_STATIC -DSPDLOG_COMPILED_LIB -DSPDLOG_FMT_EXTERNAL \
  -I"$inc" "$here/main.mm" "$lib" -lsqlite3 -lc++ -framework Foundation -framework Security \
  -framework CoreFoundation -o "$out/smoke"
"$out/smoke"
