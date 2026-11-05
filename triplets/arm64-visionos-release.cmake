# Overlay vcpkg triplet for the visionOS device slice.
#
# vcpkg has no stock visionOS triplet or toolchain; VCPKG_CMAKE_SYSTEM_NAME
# visionOS sets VCPKG_TARGET_IS_VISIONOS for portfiles, and the chainloaded
# toolchains/visionos.cmake does what scripts/toolchains/ios.cmake does for iOS.
# Minimum visionOS 2.0 matches what RealityKit's LowLevelMesh requires.

set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME visionOS)
set(VCPKG_OSX_SYSROOT xros)
# The minimum OS rides in an explicit --target instead of
# VCPKG_OSX_DEPLOYMENT_TARGET: CMake's visionOS deployment flag is a template
# ("--target=<ARCH>-apple-xros<VERSION_MIN>[-simulator]") that vcpkg's
# get_cmake_vars pastes into make-based ports (openssl) without filling in.
set(VCPKG_C_FLAGS "--target=arm64-apple-xros2.0")
set(VCPKG_CXX_FLAGS "--target=arm64-apple-xros2.0")
set(VCPKG_BUILD_TYPE release)
set(VCPKG_CHAINLOAD_TOOLCHAIN_FILE "${CMAKE_CURRENT_LIST_DIR}/../toolchains/visionos.cmake")
