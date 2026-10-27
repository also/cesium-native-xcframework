# header-only library
vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO doctest/doctest
    REF "v${VERSION}"
    SHA512 9105552d3e6a1e21f6342cf3a3ed4521d1535336fbbd2243515092206746aa1da90a2e0df8043079b181114b63bac1f3f414e34e391a6815eba09e28802342de
    HEAD_REF master
)

# Cesium only needs the header-only target. The optional runner calls
# sigaltstack, which is unavailable on tvOS.
set(tvos_options)
if(VCPKG_TARGET_IS_TVOS)
    list(APPEND tvos_options -DDOCTEST_WITH_MAIN_IN_STATIC_LIB=OFF)
endif()

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    DISABLE_PARALLEL_CONFIGURE
    OPTIONS
        -DDOCTEST_WITH_TESTS=OFF
        ${tvos_options}
)

vcpkg_cmake_install()

vcpkg_cmake_config_fixup(CONFIG_PATH lib/cmake/${PORT})

file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug" "${CURRENT_PACKAGES_DIR}/lib")

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE.txt")
