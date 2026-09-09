# cesium-native-xcframework

[cesium-native](https://github.com/CesiumGS/cesium-native) built as an iOS xcframework.

Releases carry `CesiumNative.xcframework.zip`: cesium-native v0.64.0 (`80a22ff4`) and its vcpkg dependencies (vcpkg `56bb2411`), static, C++17, slices `ios-arm64` and `ios-arm64-simulator`, minimum iOS 18.0.

## Build

```
mise install && mise exec -- ./build-xcframework.sh
```

Output goes to `~/.cache/cesium-native-xcframework/out` (override with `CESIUM_BUILD_ROOT`).

## Use

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
