cmake_minimum_required(VERSION 3.22.1)
project(llama_jni LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(LLAMA_CPP_DIR "${CMAKE_CURRENT_SOURCE_DIR}/llama.cpp")

if(NOT EXISTS "${LLAMA_CPP_DIR}/CMakeLists.txt")
    message(STATUS "llama.cpp not found at ${LLAMA_CPP_DIR}, cloning b5046...")
    execute_process(
        COMMAND git clone --depth 1 --branch b5046 https://github.com/ggml-org/llama.cpp.git "${LLAMA_CPP_DIR}"
        RESULT_VARIABLE GIT_CLONE_RES
    )
    if(NOT GIT_CLONE_RES EQUAL 0)
        message(FATAL_ERROR "Failed to clone llama.cpp b5046 into ${LLAMA_CPP_DIR}")
    endif()
endif()

set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_COMMON OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(LLAMA_CURL OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_LLAMAFILE OFF CACHE BOOL "" FORCE)

add_subdirectory("${LLAMA_CPP_DIR}" llama_build EXCLUDE_FROM_ALL)

add_library(llama_jni SHARED llama_jni.cpp)

target_include_directories(llama_jni PRIVATE
    "${LLAMA_CPP_DIR}/include"
    "${LLAMA_CPP_DIR}/ggml/include"
)

target_link_libraries(llama_jni
    llama
    android
    log
)
