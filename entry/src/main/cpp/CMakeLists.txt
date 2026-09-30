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
set(OCR_RUNTIME ${CMAKE_CURRENT_SOURCE_DIR}/../../../libs/${OHOS_ARCH}/libonnxruntime.so)
if(NOT EXISTS ${OCR_RUNTIME})
    message(FATAL_ERROR "Missing Harmony OCR runtime: run siyuan/scripts/build-ocr-harmony.py for ${OHOS_ARCH}")
endif()
add_library(onnxruntime SHARED IMPORTED)
set_target_properties(onnxruntime PROPERTIES IMPORTED_LOCATION ${OCR_RUNTIME})
target_link_libraries(entry PUBLIC libace_napi.z.so libkernel onnxruntime)
