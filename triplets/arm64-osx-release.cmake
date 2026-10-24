# Overlay vcpkg triplet for the macOS slice.
#
# vcpkg ships a community `arm64-osx.cmake`; this overlay reproduces it with
# the deployment target pinned and a release-only build type (see
# arm64-ios-release.cmake for why). No chainloaded toolchain or port overlays
# are needed: vcpkg's stock Darwin support covers every port.

set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME Darwin)
set(VCPKG_OSX_ARCHITECTURES arm64)
set(VCPKG_OSX_SYSROOT macosx)
set(VCPKG_OSX_DEPLOYMENT_TARGET 15.0)
set(VCPKG_BUILD_TYPE release)
