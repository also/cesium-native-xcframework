# Overlay vcpkg triplet for the simulator slice.
#
# vcpkg does ship a community `arm64-ios-simulator.cmake`; this overlay
# reproduces it and adds the deployment target and release-only build type
# (see arm64-ios-release.cmake for why). VCPKG_OSX_SYSROOT iphonesimulator is
# what actually switches the SDK: `scripts/toolchains/ios.cmake` only sets
# the simulator sysroot on its own for x64/x86, so arm64 needs it spelled out.

set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME iOS)
set(VCPKG_OSX_SYSROOT iphonesimulator)
set(VCPKG_OSX_DEPLOYMENT_TARGET 18.0)
set(VCPKG_BUILD_TYPE release)
