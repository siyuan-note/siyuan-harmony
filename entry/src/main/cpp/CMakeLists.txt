cmake_minimum_required(VERSION 3.5.0)
project(siyuan-harmony)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

include_directories(${NATIVERENDER_ROOT_PATH}
                    ${NATIVERENDER_ROOT_PATH}/include)

add_library(libkernel SHARED IMPORTED)
# Go 生成的共享库不含 SONAME，按库名链接，避免将构建机绝对路径写入运行时依赖。
set_target_properties(libkernel
    PROPERTIES
    IMPORTED_NO_SONAME TRUE
    IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/../../../libs/${OHOS_ARCH}/libkernel.so)

add_library(entry SHARED napi_init.cpp)
# 鸿蒙从应用原生库目录解析依赖，无需携带构建机的库搜索路径。
set_target_properties(entry PROPERTIES SKIP_BUILD_RPATH TRUE)
set(OCR_RUNTIME ${CMAKE_CURRENT_SOURCE_DIR}/../../../libs/${OHOS_ARCH}/libonnxruntime.so)
if(NOT EXISTS ${OCR_RUNTIME})
    message(FATAL_ERROR "Missing Harmony OCR runtime: run siyuan/scripts/build-ocr-harmony.py for ${OHOS_ARCH}")
endif()
add_library(onnxruntime SHARED IMPORTED)
set_target_properties(onnxruntime PROPERTIES IMPORTED_LOCATION ${OCR_RUNTIME})
target_link_libraries(entry PUBLIC libace_napi.z.so libkernel onnxruntime)
