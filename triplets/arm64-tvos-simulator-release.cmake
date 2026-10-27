# tvOS simulator: static arm64 libraries, release only.
# Use an explicit target for make-based ports, as in the visionOS triplets.
set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME tvOS)
set(VCPKG_OSX_SYSROOT appletvsimulator)
set(VCPKG_C_FLAGS "--target=arm64-apple-tvos18.0-simulator")
set(VCPKG_CXX_FLAGS "--target=arm64-apple-tvos18.0-simulator")
set(VCPKG_BUILD_TYPE release)
set(VCPKG_CHAINLOAD_TOOLCHAIN_FILE "${CMAKE_CURRENT_LIST_DIR}/../toolchains/tvos.cmake")
