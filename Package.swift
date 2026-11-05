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

let release = "v0.66.0-1"
let checksum = "93341ccff222c78c5578cb52fe33883749c285994d494574fd8d46f80d51e5e6"

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
