# the minimum version of CMake.
cmake_minimum_required(VERSION 3.5.0)
project(siyuan-harmony)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

include_directories(${NATIVERENDER_ROOT_PATH}
                    ${NATIVERENDER_ROOT_PATH}/include)

add_library(libkernel SHARED IMPORTED)
set_target_properties(libkernel
    PROPERTIES
    IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/../../../libs/${OHOS_ARCH}/libkernel.so)

add_library(entry SHARED napi_init.cpp)
target_link_libraries(entry PUBLIC libace_napi.z.so ${CMAKE_CURRENT_SOURCE_DIR}/../../../libs/${OHOS_ARCH}/libkernel.so)
