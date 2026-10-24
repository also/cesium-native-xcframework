# cesium-native-xcframework

[cesium-native](https://github.com/CesiumGS/cesium-native) built as an iOS xcframework.

Releases carry `CesiumNative.xcframework.zip`: cesium-native v0.64.0 (`80a22ff4`) and its vcpkg dependencies (vcpkg `56bb2411`), static, C++17, slices `ios-arm64` and `ios-arm64-simulator`, minimum iOS 18.0.

## Build

```
mise install && mise exec -- ./build-xcframework.sh
```

Output goes to `~/.cache/cesium-native-xcframework/out` (override with `CESIUM_BUILD_ROOT`).

### visionOS

```
mise exec -- ./build-xcframework.sh --slices "visionos visionos-simulator"
```

Builds `xros-arm64` and `xros-arm64-simulator` slices (minimum visionOS 2.0). vcpkg has no visionOS toolchain, so the visionOS triplets chainload `toolchains/visionos.cmake`; `ports/openssl` overlays the stock port so visionOS builds the way tvOS does; and the script patches cesium-native's iOS-only "skip asmjit" checks to cover visionOS. Slice names can be combined with `device simulator` to get all four in one xcframework.

### macOS

```
mise exec -- ./build-xcframework.sh --slices "macos"
```

Builds a `macos-arm64` slice (arm64 only, minimum macOS 15.0) using the `arm64-osx-release` triplet. vcpkg supports macOS natively, so no toolchain or port overlays are involved. Unlike the mobile slices, macOS builds blend2d with its JIT and therefore also bundles asmjit, as upstream does. Combine with other slices, e.g. `--slices "macos visionos visionos-simulator"`.

## Use

### Swift Package Manager

`Package.swift` exposes a `CesiumNative` library backed by the release zip (URL and checksum are set per release). Add this repo as a package dependency and link `libsqlite3` from your target.

To develop against a local build, symlink the xcframework next to `Package.swift` and depend on the directory (`.package(path:)`, or `packages: … path:` in XcodeGen). The symlink is gitignored; remove it to go back to the release.

```
ln -s ~/.cache/cesium-native-xcframework/out/CesiumNative.xcframework .
```

### Publishing a release

`scripts/publish-release.sh <tag>` checks the last build and prints the release it would create; add `--yes` to publish. Then update `release` and `checksum` in `Package.swift` and commit.

### Binary target by URL


```swift
.binaryTarget(
    name: "CesiumNative",
    url: "https://github.com/crookneck/cesium-native-xcframework/releases/download/<tag>/CesiumNative.xcframework.zip",
    checksum: "<sha256 from the release notes>"
)
```

The archive does not include SQLite. Link the system library from the target that depends on `CesiumNative`:

```swift
linkerSettings: [.linkedLibrary("sqlite3")]
```

## License

Scripts in this repository: Apache 2.0 (`LICENSE`). The xcframework contains cesium-native and its dependencies; their licenses are in `THIRD_PARTY_LICENSES`.
