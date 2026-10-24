#!/usr/bin/env bash
#
# build-xcframework.sh — cesium-native → CesiumNative.xcframework
#
# Builds cesium-native and every one of its vcpkg dependencies as static
# libraries for two iOS slices (arm64 device, arm64 simulator), merges each
# slice into a single archive, and wraps both in an xcframework with headers.
# Sources, build trees, and outputs live under $CESIUM_BUILD_ROOT
# (default ~/.cache/cesium-native-xcframework); nothing is written elsewhere.
#
# ── Pins ────────────────────────────────────────────────────────────────────
#   cesium-native   tag v0.64.0   commit 80a22ff4337c5b7057cff53d0055045c15c6d350
#   vcpkg           commit 56bb2411609227288b70117ead2c47585ba07713
#                   (the baseline cesium-native v0.64.0 declares in its own
#                    vcpkg-configuration.json / ezvcpkg_fetch call, so the port
#                    versions are exactly the ones cesium's CI builds)
#   CMake / Ninja   pinned in .mise.toml
#
# ── Triplets (triplets/) ────────────────────────────────────────────────────
#   device     arm64-ios-release            iphoneos,        min iOS 18.0, static, release-only
#   simulator  arm64-ios-simulator-release  iphonesimulator, min iOS 18.0, static, release-only
#   macos               arm64-osx-release             macosx,      min macOS 15.0, arm64 only
#   visionos            arm64-visionos-release            xros,        min visionOS 2.0
#   visionos-simulator  arm64-visionos-simulator-release  xrsimulator, min visionOS 2.0
#     vcpkg has no visionOS toolchain, so these chainload toolchains/visionos.cmake,
#     and ports/openssl overlays the stock port to build visionOS the way it
#     builds tvOS (iphoneos-cross, no-asm). cesium-native's "skip asmjit on
#     iOS" checks are patched to cover visionOS too (no JIT there either).
#
# ── cesium-native CMake options ─────────────────────────────────────────────
#   CMAKE_SYSTEM_NAME=iOS  CMAKE_OSX_ARCHITECTURES=arm64
#   CMAKE_OSX_SYSROOT=iphoneos|iphonesimulator  CMAKE_OSX_DEPLOYMENT_TARGET=18.0
#   CMAKE_BUILD_TYPE=Release  CESIUM_DISABLE_CURL=ON  CESIUM_TESTS_ENABLED=OFF
#   CESIUM_INSTALL_STATIC_LIBS=ON  CESIUM_ENABLE_CLANG_TIDY=OFF
#   VCPKG_MANIFEST_MODE=OFF (classic mode; see "Why classic mode" below)
#
# ── vcpkg packages (classic mode) ───────────────────────────────────────────
#   The list mirrors PACKAGES_PUBLIC + PACKAGES_PRIVATE + PACKAGES_TEST from
#   cesium-native's CMakeLists.txt for an iOS target with curl disabled:
#   curl and asmjit are dropped, blend2d/ktx/cpp-httplib are built with [core]
#   only. doctest is header-only but find_package'd unconditionally, so it
#   stays. cesium-native's own overlay port for ktx (extern/vcpkg/ports) is
#   applied, as its build does.
#
# ── Why classic mode ────────────────────────────────────────────────────────
#   cesium-native's vcpkg.json manifest lists curl unconditionally (it is
#   only excluded for wasm32). Manifest mode would therefore build curl and
#   its dependency tree for a library then configured with
#   CESIUM_DISABLE_CURL=ON. Classic mode with the explicit list is what
#   cesium's own ezvcpkg helper does; driving vcpkg directly keeps the
#   checkout and commit pinned here.
#
# ── Usage ───────────────────────────────────────────────────────────────────
#   mise exec -- ./build-xcframework.sh [--slices "device simulator visionos visionos-simulator macos"]
#                                      [--skip-deps] [--skip-build] [--clean]
#   Environment:
#     CESIUM_BUILD_ROOT   scratch root (default ~/.cache/cesium-native-xcframework)
#     CESIUM_JOBS         parallel jobs (default: hw.ncpu)
#
#   Outputs (all under $CESIUM_BUILD_ROOT/out):
#     CesiumNative.xcframework/         the framework
#     CesiumNative.xcframework.zip      zip (ditto) of the framework
#     CesiumNative.xcframework.sha256   SHA-256 of the zip
#     CesiumNative.manifest.txt         per-slice sizes and per-archive SHA-256s
#     ports.<slice>.log                 which ports built (or fell back)
#
set -euo pipefail

CESIUM_TAG="v0.64.0"
CESIUM_COMMIT="80a22ff4337c5b7057cff53d0055045c15c6d350"
CESIUM_REPO="https://github.com/CesiumGS/cesium-native.git"
VCPKG_COMMIT="56bb2411609227288b70117ead2c47585ba07713"
VCPKG_REPO="https://github.com/microsoft/vcpkg.git"
DEPLOYMENT_TARGET="18.0"
VISIONOS_DEPLOYMENT_TARGET="2.0"
MACOS_DEPLOYMENT_TARGET="15.0"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRIPLETS_DIR="$SCRIPT_DIR/triplets"
PORTS_DIR="$SCRIPT_DIR/ports"
BUILD_ROOT_DIR="${CESIUM_BUILD_ROOT:-$HOME/.cache/cesium-native-xcframework}"
SRC_DIR="$BUILD_ROOT_DIR/cesium-native"
VCPKG_ROOT="$BUILD_ROOT_DIR/vcpkg"
BUILD_ROOT="$BUILD_ROOT_DIR/build"
OUT_DIR="$BUILD_ROOT_DIR/out"
JOBS="${CESIUM_JOBS:-$(sysctl -n hw.ncpu)}"

SLICES="device simulator"
SKIP_DEPS=0
SKIP_BUILD=0
CLEAN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --slices) SLICES="$2"; shift 2 ;;
    --skip-deps) SKIP_DEPS=1; shift ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    --clean) CLEAN=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

PACKAGES=(
  # public (headers ship in the xcframework)
  asyncplusplus expected-lite fmt glm rapidjson spdlog stb ada-url ms-gsl
  # private
  abseil draco "ktx[core]" modp-base64 meshoptimizer openssl s2geometry
  sqlite3 tinyxml2 libwebp zlib-ng picosha2 earcut-hpp libmorton zstd spz zlib
  "blend2d[core]" libjpeg-turbo "cpp-httplib[core]"
  # test-only but find_package'd unconditionally
  doctest
)

log() { printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }
die() { echo "error: $*" >&2; exit 1; }

require() { command -v "$1" >/dev/null 2>&1 || die "$1 not found on PATH (run via 'mise exec --')"; }
require cmake; require ninja; require git; require xcodebuild; require libtool; require ditto

CMAKE_VERSION="$(cmake --version | head -1 | awk '{print $3}')"
log "cmake $CMAKE_VERSION, ninja $(ninja --version), $(xcodebuild -version | tr '\n' ' ')"

# ── Sources ────────────────────────────────────────────────────────────────
mkdir -p "$BUILD_ROOT_DIR" "$OUT_DIR"

if [[ ! -d "$SRC_DIR/.git" ]]; then
  log "cloning cesium-native $CESIUM_TAG"
  git clone --branch "$CESIUM_TAG" --depth 1 --recurse-submodules --shallow-submodules "$CESIUM_REPO" "$SRC_DIR"
fi
ACTUAL="$(git -C "$SRC_DIR" rev-parse HEAD)"
[[ "$ACTUAL" == "$CESIUM_COMMIT" ]] || die "cesium-native at $ACTUAL, expected $CESIUM_COMMIT ($CESIUM_TAG)"

if [[ ! -d "$VCPKG_ROOT/.git" ]]; then
  log "cloning vcpkg"
  git clone "$VCPKG_REPO" "$VCPKG_ROOT"
fi
if [[ "$(git -C "$VCPKG_ROOT" rev-parse HEAD)" != "$VCPKG_COMMIT" ]]; then
  git -C "$VCPKG_ROOT" fetch --quiet origin "$VCPKG_COMMIT" || true
  git -C "$VCPKG_ROOT" checkout --quiet "$VCPKG_COMMIT"
fi
[[ -x "$VCPKG_ROOT/vcpkg" ]] || { log "bootstrapping vcpkg"; "$VCPKG_ROOT/bootstrap-vcpkg.sh" -disableMetrics; }
# cesium-native skips asmjit (blend2d's JIT) only when it sees iOS; visionOS
# has no JIT either. Idempotent: the replacement no longer matches the pattern.
CESIUM_ASMJIT_GUARD='NOT IOS AND NOT VCPKG_CMAKE_SYSTEM_NAME MATCHES "iOS")'
for f in "$SRC_DIR/CMakeLists.txt" "$SRC_DIR/CesiumVectorData/CMakeLists.txt"; do
  if grep -qF "$CESIUM_ASMJIT_GUARD" "$f"; then
    log "patching asmjit guard for visionOS in ${f#$SRC_DIR/}"
    sed -i '' 's/NOT IOS AND NOT VCPKG_CMAKE_SYSTEM_NAME MATCHES "iOS")/NOT IOS AND NOT VCPKG_CMAKE_SYSTEM_NAME MATCHES "iOS|visionOS" AND NOT CMAKE_SYSTEM_NAME STREQUAL "visionOS")/' "$f"
  fi
done

export VCPKG_ROOT
export VCPKG_DISABLE_METRICS=1

if [[ $CLEAN -eq 1 ]]; then
  log "cleaning $BUILD_ROOT and $OUT_DIR"
  rm -rf "$BUILD_ROOT" "$OUT_DIR"; mkdir -p "$OUT_DIR"
fi

slice_triplet() {
  case "$1" in
    device) echo arm64-ios-release ;;
    simulator) echo arm64-ios-simulator-release ;;
    visionos) echo arm64-visionos-release ;;
    visionos-simulator) echo arm64-visionos-simulator-release ;;
    macos) echo arm64-osx-release ;;
    *) die "unknown slice $1" ;;
  esac
}
slice_sysroot() {
  case "$1" in
    device) echo iphoneos ;; simulator) echo iphonesimulator ;;
    visionos) echo xros ;; visionos-simulator) echo xrsimulator ;;
    macos) echo macosx ;;
  esac
}
slice_system() { case "$1" in visionos*) echo visionOS ;; macos) echo Darwin ;; *) echo iOS ;; esac; }
slice_min_os() { case "$1" in visionos*) echo "$VISIONOS_DEPLOYMENT_TARGET" ;; macos) echo "$MACOS_DEPLOYMENT_TARGET" ;; *) echo "$DEPLOYMENT_TARGET" ;; esac; }

# ── Per-slice: dependencies → configure → build → install → merge ──────────
for slice in $SLICES; do
  triplet="$(slice_triplet "$slice")"
  # macOS can JIT, so it takes the upstream blend2d + asmjit pair that
  # cesium-native's CMake requires there; every other slice uses blend2d[core].
  packages=("${PACKAGES[@]}")
  if [[ "$slice" == macos ]]; then
    packages=("${packages[@]/blend2d\[core\]/blend2d}" asmjit)
  fi
  sysroot="$(slice_sysroot "$slice")"
  system="$(slice_system "$slice")"
  min_os="$(slice_min_os "$slice")"
  build_dir="$BUILD_ROOT/$slice"
  install_dir="$build_dir/install"
  installed_dir="$VCPKG_ROOT/installed/$triplet"
  mkdir -p "$build_dir"

  if [[ $SKIP_DEPS -eq 0 ]]; then
    log "[$slice] vcpkg install ${#packages[@]} ports for $triplet"
    # Ports that fail on iOS can be retried standalone with the stock
    # arm64-ios(-simulator) community triplet (the community-thread fallback);
    # the log records which, if any, needed it.
    ports_log="$OUT_DIR/ports.$slice.log"
    : > "$ports_log"
    failed=()
    for pkg in "${packages[@]}"; do
      if "$VCPKG_ROOT/vcpkg" install "$pkg" \
           --triplet "$triplet" \
           --overlay-triplets="$TRIPLETS_DIR" \
           --overlay-ports="$PORTS_DIR" \
           --overlay-ports="$SRC_DIR/extern/vcpkg/ports" \
           --clean-buildtrees-after-build \
           >"$build_dir/vcpkg-$(echo "$pkg" | tr -c 'A-Za-z0-9' '_').log" 2>&1; then
        echo "$pkg ok $triplet" >> "$ports_log"
      else
        echo "$pkg FAILED $triplet (see $build_dir/vcpkg-*.log)" >> "$ports_log"
        failed+=("$pkg")
      fi
    done
    if [[ ${#failed[@]} -gt 0 && "$system" != iOS && "$system" != Darwin ]]; then
      die "[$slice] ports failed: ${failed[*]} (no stock $system triplet to fall back to); see $ports_log"
    fi
    if [[ ${#failed[@]} -gt 0 ]]; then
      log "[$slice] ports failed: ${failed[*]} — trying stock community triplet fallback"
      stock="${triplet%-release}"
      for pkg in "${failed[@]}"; do
        if "$VCPKG_ROOT/vcpkg" install "$pkg" --triplet "$stock" \
             --overlay-ports="$SRC_DIR/extern/vcpkg/ports" \
             >"$build_dir/vcpkg-fallback-$(echo "$pkg" | tr -c 'A-Za-z0-9' '_').log" 2>&1; then
          echo "$pkg FALLBACK ok via $stock; copying libs into $installed_dir" >> "$ports_log"
          base="${pkg%%\[*}"
          cp -R "$VCPKG_ROOT/packages/${base}_${stock}/lib/." "$installed_dir/lib/" 2>/dev/null || true
          cp -R "$VCPKG_ROOT/packages/${base}_${stock}/include/." "$installed_dir/include/" 2>/dev/null || true
        else
          echo "$pkg FALLBACK FAILED via $stock" >> "$ports_log"
          die "[$slice] port $pkg has no working iOS build; see $ports_log"
        fi
      done
    fi
  fi

  if [[ $SKIP_BUILD -eq 0 ]]; then
    log "[$slice] configure cesium-native ($sysroot, $triplet)"
    cmake -S "$SRC_DIR" -B "$build_dir/cmake" -G Ninja \
      -DCMAKE_TOOLCHAIN_FILE="$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" \
      -DVCPKG_TARGET_TRIPLET="$triplet" \
      -DVCPKG_OVERLAY_TRIPLETS="$TRIPLETS_DIR" \
      -DVCPKG_OVERLAY_PORTS="$PORTS_DIR;$SRC_DIR/extern/vcpkg/ports" \
      -DVCPKG_MANIFEST_MODE=OFF \
      -DCESIUM_USE_EZVCPKG=OFF \
      -DCMAKE_SYSTEM_NAME="$system" \
      -DCMAKE_OSX_ARCHITECTURES=arm64 \
      -DCMAKE_OSX_SYSROOT="$sysroot" \
      -DCMAKE_OSX_DEPLOYMENT_TARGET="$min_os" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX="$install_dir" \
      -DCESIUM_DISABLE_CURL=ON \
      -DCESIUM_TESTS_ENABLED=OFF \
      -DCESIUM_INSTALL_STATIC_LIBS=ON \
      -DCESIUM_INSTALL_HEADERS=ON \
      -DCESIUM_ENABLE_CLANG_TIDY=OFF \
      -DCESIUM_TRACING_ENABLED=OFF \
      -DCMAKE_C_COMPILER_LAUNCHER= -DCMAKE_CXX_COMPILER_LAUNCHER= \
      > "$build_dir/configure.log" 2>&1 || { tail -50 "$build_dir/configure.log"; die "[$slice] configure failed"; }

    log "[$slice] build (-j$JOBS)"
    cmake --build "$build_dir/cmake" --parallel "$JOBS" > "$build_dir/build.log" 2>&1 \
      || { tail -80 "$build_dir/build.log"; die "[$slice] build failed"; }

    log "[$slice] install → $install_dir"
    rm -rf "$install_dir"
    cmake --install "$build_dir/cmake" > "$build_dir/install.log" 2>&1 \
      || { tail -50 "$build_dir/install.log"; die "[$slice] install failed"; }
  fi

  # ── Merge every static library into one archive ─────────────────────────
  log "[$slice] merging static libraries"
  merged="$build_dir/CesiumNative.a"
  rm -f "$merged"
  # SQLite is deliberately left out: iOS ships libsqlite3, and a second copy
  # in the same process makes any other user of the system library mix
  # handles from two builds. Consumers link the system library instead.
  EXCLUDED_ARCHIVES="libsqlite3.a"
  excluded() { case " $EXCLUDED_ARCHIVES " in *" $(basename "$1") "*) return 0 ;; *) return 1 ;; esac; }
  libs=()
  while IFS= read -r -d '' f; do excluded "$f" || libs+=("$f"); done < <(find "$install_dir/lib" -maxdepth 1 -name '*.a' -print0 | sort -z)
  # cesium's install() only copies dependency libs in ezvcpkg mode; in classic
  # mode they are pulled straight from vcpkg's installed tree for the triplet.
  while IFS= read -r -d '' f; do
    name="$(basename "$f")"
    excluded "$f" && continue
    [[ -f "$install_dir/lib/$name" ]] || libs+=("$f")
  done < <(find "$installed_dir/lib" -maxdepth 1 -name '*.a' -print0 | sort -z)
  [[ ${#libs[@]} -gt 0 ]] || die "[$slice] no static libraries found"
  printf '%s\n' "${libs[@]}" > "$build_dir/merged-inputs.txt"
  # -D: deterministic (zeroed uid/gid/mtime) so identical inputs give identical bytes.
  libtool -static -D -o "$merged" "${libs[@]}" 2> "$build_dir/libtool.log" || { cat "$build_dir/libtool.log"; die "[$slice] libtool failed"; }
  log "[$slice] $(du -h "$merged" | cut -f1) merged from ${#libs[@]} archives"

  # ── Headers: cesium-native install/include + public vcpkg headers ─────────
  headers="$build_dir/headers"
  rm -rf "$headers"; mkdir -p "$headers"
  cp -R "$install_dir/include/." "$headers/"
  # vcpkg headers (all of them; excluding by name is fragile and headers cost
  # nothing at link).
  cp -R "$installed_dir/include/." "$headers/"
done

# ── xcframework ────────────────────────────────────────────────────────────
log "creating xcframework"
XCF="$OUT_DIR/CesiumNative.xcframework"
rm -rf "$XCF" "$XCF.zip"
args=()
for slice in $SLICES; do
  args+=(-library "$BUILD_ROOT/$slice/CesiumNative.a" -headers "$BUILD_ROOT/$slice/headers")
done
xcodebuild -create-xcframework "${args[@]}" -output "$XCF" > "$OUT_DIR/create-xcframework.log" 2>&1 \
  || { cat "$OUT_DIR/create-xcframework.log"; die "create-xcframework failed"; }

# Normalise mtimes so the zip is reproducible for identical contents.
find "$XCF" -exec touch -t 200001010000 {} +
( cd "$OUT_DIR" && ditto -c -k --keepParent --norsrc --noextattr --noqtn "CesiumNative.xcframework" "CesiumNative.xcframework.zip" )
SHA="$(shasum -a 256 "$XCF.zip" | awk '{print $1}')"
echo "$SHA" > "$OUT_DIR/CesiumNative.xcframework.sha256"

# ── Report ─────────────────────────────────────────────────────────────────
{
  echo "cesium-native $CESIUM_TAG $CESIUM_COMMIT"
  echo "vcpkg $VCPKG_COMMIT tool $("$VCPKG_ROOT/vcpkg" version | head -1 | awk '{print $NF}')"
  echo "xcode $(xcodebuild -version | tr '\n' ' ')"
  echo "cmake $CMAKE_VERSION ninja $(ninja --version)"
  echo
  for slice in $SLICES; do
    a="$BUILD_ROOT/$slice/CesiumNative.a"
    echo "$slice $(slice_triplet "$slice") $(stat -f %z "$a") bytes  sha256 $(shasum -a 256 "$a" | awk '{print $1}')"
    echo "  archives merged: $(wc -l < "$BUILD_ROOT/$slice/merged-inputs.txt")"
    echo "  build version: $(xcrun otool -l "$a" 2>/dev/null | grep -m1 -A5 LC_BUILD_VERSION | grep -E 'platform|minos' | tr -s ' ' | tr '\n' ' ')"
  done
  echo
  echo "xcframework $(du -sh "$XCF" | cut -f1)"
  echo "zip $(stat -f %z "$XCF.zip") bytes sha256 $SHA"
} | tee "$OUT_DIR/CesiumNative.manifest.txt"

log "done: $XCF"
