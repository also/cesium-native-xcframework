# vcpkg chainload toolchain for visionOS (device and simulator).
#
# vcpkg recognises VCPKG_CMAKE_SYSTEM_NAME visionOS (VCPKG_TARGET_IS_VISIONOS)
# but ships no toolchain for it, so the visionOS triplets point
# VCPKG_CHAINLOAD_TOOLCHAIN_FILE here. Modelled on vcpkg's
# scripts/toolchains/ios.cmake; CMake (>= 3.28) knows the visionOS platform
# natively, so this only needs to pick the system name, arch and sysroot and
# forward the triplet's flags. The sysroot (xros / xrsimulator) and deployment
# target arrive from the triplet via VCPKG_OSX_SYSROOT and
# VCPKG_OSX_DEPLOYMENT_TARGET, which vcpkg maps to CMAKE_OSX_*.
if(NOT _VCPKG_VISIONOS_TOOLCHAIN)
    set(_VCPKG_VISIONOS_TOOLCHAIN 1)

    foreach(_policy CMP0056 CMP0066 CMP0067 CMP0137)
        if(POLICY ${_policy})
            cmake_policy(SET ${_policy} NEW)
        endif()
    endforeach()
    list(APPEND CMAKE_TRY_COMPILE_PLATFORM_VARIABLES
        VCPKG_CRT_LINKAGE VCPKG_TARGET_ARCHITECTURE
        VCPKG_C_FLAGS VCPKG_CXX_FLAGS
        VCPKG_C_FLAGS_DEBUG VCPKG_CXX_FLAGS_DEBUG
        VCPKG_C_FLAGS_RELEASE VCPKG_CXX_FLAGS_RELEASE
        VCPKG_LINKER_FLAGS VCPKG_LINKER_FLAGS_RELEASE VCPKG_LINKER_FLAGS_DEBUG
    )

    set(CMAKE_SYSTEM_NAME visionOS CACHE STRING "")
    if(NOT VCPKG_TARGET_ARCHITECTURE STREQUAL "arm64")
        message(FATAL_ERROR "visionOS triplets must be arm64, got ${VCPKG_TARGET_ARCHITECTURE}")
    endif()
    if(NOT CMAKE_SYSTEM_PROCESSOR)
        set(CMAKE_SYSTEM_PROCESSOR aarch64)
    endif()
    set(CMAKE_OSX_ARCHITECTURES arm64 CACHE STRING "Build architectures for visionOS")

    string(APPEND CMAKE_C_FLAGS_INIT " -fPIC ${VCPKG_C_FLAGS} ")
    string(APPEND CMAKE_CXX_FLAGS_INIT " -fPIC ${VCPKG_CXX_FLAGS} ")
    string(APPEND CMAKE_C_FLAGS_DEBUG_INIT " ${VCPKG_C_FLAGS_DEBUG} ")
    string(APPEND CMAKE_CXX_FLAGS_DEBUG_INIT " ${VCPKG_CXX_FLAGS_DEBUG} ")
    string(APPEND CMAKE_C_FLAGS_RELEASE_INIT " ${VCPKG_C_FLAGS_RELEASE} ")
    string(APPEND CMAKE_CXX_FLAGS_RELEASE_INIT " ${VCPKG_CXX_FLAGS_RELEASE} ")

    string(APPEND CMAKE_MODULE_LINKER_FLAGS_INIT " ${VCPKG_LINKER_FLAGS} ")
    string(APPEND CMAKE_SHARED_LINKER_FLAGS_INIT " ${VCPKG_LINKER_FLAGS} ")
    string(APPEND CMAKE_EXE_LINKER_FLAGS_INIT " ${VCPKG_LINKER_FLAGS} ")
    string(APPEND CMAKE_MODULE_LINKER_FLAGS_DEBUG_INIT " ${VCPKG_LINKER_FLAGS_DEBUG} ")
    string(APPEND CMAKE_SHARED_LINKER_FLAGS_DEBUG_INIT " ${VCPKG_LINKER_FLAGS_DEBUG} ")
    string(APPEND CMAKE_EXE_LINKER_FLAGS_DEBUG_INIT " ${VCPKG_LINKER_FLAGS_DEBUG} ")
    string(APPEND CMAKE_MODULE_LINKER_FLAGS_RELEASE_INIT " ${VCPKG_LINKER_FLAGS_RELEASE} ")
    string(APPEND CMAKE_SHARED_LINKER_FLAGS_RELEASE_INIT " ${VCPKG_LINKER_FLAGS_RELEASE} ")
    string(APPEND CMAKE_EXE_LINKER_FLAGS_RELEASE_INIT " ${VCPKG_LINKER_FLAGS_RELEASE} ")
endif()
