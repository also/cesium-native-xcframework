// swift-tools-version:5.9
import Foundation
import PackageDescription

// Consumers get the released binary. To develop against a local build instead,
// put (or symlink) the xcframework next to this file:
//
//   ln -s ~/.cache/cesium-native-xcframework/out/CesiumNative.xcframework .
//
// then depend on this directory as a local package (.package(path:)). The
// link is gitignored; remove it to go back to the release.
let localFramework = "CesiumNative.xcframework"
let hasLocalFramework = FileManager.default.fileExists(
    atPath: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent(localFramework).path)

let release = "v0.64.0-1"
let checksum = "9cbc7e65db2e712aaf2bef6dac337865bd4362507cca367e7bb1a1c99d09c78e"

let cesiumNative: Target = hasLocalFramework
    ? .binaryTarget(name: "CesiumNative", path: localFramework)
    : .binaryTarget(
        name: "CesiumNative",
        url: "https://github.com/also/cesium-native-xcframework/releases/download/\(release)/CesiumNative.xcframework.zip",
        checksum: checksum)

// The archive doesn't include SQLite; link the system library from the
// target that uses this one (-lsqlite3).
let package = Package(
    name: "CesiumNative",
    products: [
        .library(name: "CesiumNative", targets: ["CesiumNative"]),
    ],
    targets: [cesiumNative]
)
