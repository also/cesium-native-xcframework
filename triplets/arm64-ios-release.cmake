# Overlay vcpkg triplet for the device slice.
#
# Modelled on vcpkg's community `arm64-ios.cmake`, with two additions the
# stock triplet lacks:
#   - VCPKG_OSX_DEPLOYMENT_TARGET 18.0 so every dependency carries the same
#     minimum OS (the stock triplet leaves it to the SDK default).
#   - VCPKG_BUILD_TYPE release so vcpkg does not also build a Debug flavour of
#     every port; the xcframework only ever carries Release objects.
#
# The iOS toolchain (`scripts/toolchains/ios.cmake`) is chain-loaded by
# vcpkg automatically because VCPKG_CMAKE_SYSTEM_NAME is iOS; it maps
# VCPKG_TARGET_ARCHITECTURE arm64 to CMAKE_OSX_ARCHITECTURES=arm64 and
# leaves the sysroot at the iphoneos default.

set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME iOS)
set(VCPKG_OSX_DEPLOYMENT_TARGET 18.0)
set(VCPKG_BUILD_TYPE release)
