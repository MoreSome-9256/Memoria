cmake_minimum_required(VERSION 3.22.1)

project(memoria_ncnn_bridge)

set(MEMORIA_THIRD_PARTY_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../third_party")

set(MEMORIA_ANDROID_ABI "${ANDROID_ABI}")
if(NOT MEMORIA_ANDROID_ABI)
    set(MEMORIA_ANDROID_ABI "${CMAKE_ANDROID_ARCH_ABI}")
endif()

set(MEMORIA_NCNN_SDK_CANDIDATES
    "${MEMORIA_THIRD_PARTY_DIR}/ncnn-android-vulkan"
    "${MEMORIA_THIRD_PARTY_DIR}/ncnn-20260113-android-vulkan")

set(MEMORIA_NCNN_SDK_DIR "")
foreach(MEMORIA_NCNN_SDK_CANDIDATE IN LISTS MEMORIA_NCNN_SDK_CANDIDATES)
    if(EXISTS "${MEMORIA_NCNN_SDK_CANDIDATE}/${MEMORIA_ANDROID_ABI}/include/ncnn/net.h"
       OR EXISTS "${MEMORIA_NCNN_SDK_CANDIDATE}/${MEMORIA_ANDROID_ABI}/include/net.h")
        set(MEMORIA_NCNN_SDK_DIR "${MEMORIA_NCNN_SDK_CANDIDATE}")
        break()
    endif()
endforeach()

if(NOT MEMORIA_NCNN_SDK_DIR)
    list(GET MEMORIA_NCNN_SDK_CANDIDATES 0 MEMORIA_NCNN_SDK_DIR)
endif()

add_library(memoria_ncnn SHARED
    memoria_ncnn_bridge.cpp)

target_compile_features(memoria_ncnn PRIVATE cxx_std_17)

find_library(log-lib log)

set(CMAKE_THREAD_PREFER_PTHREAD TRUE)
set(THREADS_PREFER_PTHREAD_FLAG TRUE)
find_package(Threads REQUIRED)

unset(MEMORIA_NCNN_INCLUDE_DIR CACHE)
unset(MEMORIA_NCNN_LIBRARY CACHE)

set(MEMORIA_NCNN_INCLUDE_DIR "")
if(EXISTS "${MEMORIA_NCNN_SDK_DIR}/${MEMORIA_ANDROID_ABI}/include/ncnn/net.h"
   OR EXISTS "${MEMORIA_NCNN_SDK_DIR}/${MEMORIA_ANDROID_ABI}/include/net.h")
    set(MEMORIA_NCNN_INCLUDE_DIR "${MEMORIA_NCNN_SDK_DIR}/${MEMORIA_ANDROID_ABI}/include")
elseif(EXISTS "${MEMORIA_NCNN_SDK_DIR}/include/ncnn/net.h")
    set(MEMORIA_NCNN_INCLUDE_DIR "${MEMORIA_NCNN_SDK_DIR}/include")
elseif(EXISTS "${MEMORIA_NCNN_SDK_DIR}/include/net.h")
    set(MEMORIA_NCNN_INCLUDE_DIR "${MEMORIA_NCNN_SDK_DIR}/include")
endif()

set(MEMORIA_NCNN_LIBRARY "")
if(EXISTS "${MEMORIA_NCNN_SDK_DIR}/${MEMORIA_ANDROID_ABI}/lib/libncnn.a")
    set(MEMORIA_NCNN_LIBRARY "${MEMORIA_NCNN_SDK_DIR}/${MEMORIA_ANDROID_ABI}/lib/libncnn.a")
elseif(EXISTS "${MEMORIA_NCNN_SDK_DIR}/${MEMORIA_ANDROID_ABI}/lib/libncnn.so")
    set(MEMORIA_NCNN_LIBRARY "${MEMORIA_NCNN_SDK_DIR}/${MEMORIA_ANDROID_ABI}/lib/libncnn.so")
elseif(EXISTS "${MEMORIA_NCNN_SDK_DIR}/${MEMORIA_ANDROID_ABI}/libncnn.a")
    set(MEMORIA_NCNN_LIBRARY "${MEMORIA_NCNN_SDK_DIR}/${MEMORIA_ANDROID_ABI}/libncnn.a")
elseif(EXISTS "${MEMORIA_NCNN_SDK_DIR}/${MEMORIA_ANDROID_ABI}/libncnn.so")
    set(MEMORIA_NCNN_LIBRARY "${MEMORIA_NCNN_SDK_DIR}/${MEMORIA_ANDROID_ABI}/libncnn.so")
endif()

set(MEMORIA_GLSLANG_DIR "${MEMORIA_NCNN_SDK_DIR}/${MEMORIA_ANDROID_ABI}/lib/cmake/glslang")
if(EXISTS "${MEMORIA_GLSLANG_DIR}/glslang-config.cmake")
    include("${MEMORIA_GLSLANG_DIR}/glslang-config.cmake")
endif()

if (MEMORIA_NCNN_INCLUDE_DIR AND MEMORIA_NCNN_LIBRARY)
    message(STATUS "Memoria NCNN SDK found for ${MEMORIA_ANDROID_ABI}: ${MEMORIA_NCNN_LIBRARY}")
    target_sources(memoria_ncnn PRIVATE
        vendored_mobileclip_image_encoder.cpp)
    target_compile_definitions(memoria_ncnn PRIVATE MEMORIA_NCNN_RUNTIME_ENABLED=1)
    target_sources(memoria_ncnn PRIVATE
        vendored_mobileclip_image_encoder.cpp)
    target_include_directories(memoria_ncnn PRIVATE
        "${MEMORIA_NCNN_INCLUDE_DIR}"
        "${CMAKE_CURRENT_SOURCE_DIR}")
    target_compile_options(memoria_ncnn PRIVATE -fno-rtti -fno-exceptions)
    target_link_options(memoria_ncnn PRIVATE -fopenmp -static-openmp)
    target_link_libraries(memoria_ncnn
        Threads::Threads
        dl
        android
        jnigraphics
        ${log-lib}
        ${MEMORIA_NCNN_LIBRARY})
    if(TARGET glslang::glslang)
        target_link_libraries(memoria_ncnn
            glslang::glslang
            glslang::MachineIndependent
            glslang::OSDependent
            glslang::GenericCodeGen
            glslang::SPIRV
            glslang::glslang-default-resource-limits)
    endif()
else()
    string(JOIN ", " MEMORIA_NCNN_SDK_CANDIDATES_DISPLAY ${MEMORIA_NCNN_SDK_CANDIDATES})
    message(WARNING "Memoria NCNN SDK not found under any of: ${MEMORIA_NCNN_SDK_CANDIDATES_DISPLAY}; building bridge without linked ncnn runtime.")
    target_compile_definitions(memoria_ncnn PRIVATE MEMORIA_NCNN_RUNTIME_ENABLED=0)
    target_link_libraries(memoria_ncnn
        ${log-lib})
endif()