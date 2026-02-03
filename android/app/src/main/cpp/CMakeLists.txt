# CMakeLists.txt for Haku LLM with Vulkan GPU Support
# ใช้สำหรับ compile llama.cpp ด้วย Vulkan backend

cmake_minimum_required(VERSION 3.10.2)
project("haku_llm")

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# =============================================================================
# Build mode selection
# =============================================================================

# Check if we want to build stub only (for quick testing)
option(BUILD_STUB_ONLY "Build stub library only (no llama.cpp)" OFF)

# Path to llama.cpp
set(LLAMA_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/llama.cpp")

# Check if llama.cpp exists
if(NOT EXISTS ${LLAMA_ROOT} OR BUILD_STUB_ONLY)
    if(BUILD_STUB_ONLY)
        message(STATUS "📝 Building STUB library only")
    else()
        message(WARNING "⚠️  llama.cpp not found at ${LLAMA_ROOT}")
        message(STATUS "   Building STUB library. To use llama.cpp:")
        message(STATUS "   git clone --recursive https://github.com/ggerganov/llama.cpp.git ${LLAMA_ROOT}")
    endif()
    
    # Build stub library
    add_library(haku_llm SHARED stub_llm.cpp)
    target_link_libraries(haku_llm log)
    
    # Export target
    install(TARGETS haku_llm DESTINATION lib/${ANDROID_ABI})
    return()
endif()

# =============================================================================
# Vulkan Setup for Android GPU
# =============================================================================

message(STATUS "🔧 Configuring llama.cpp with Vulkan GPU support...")

# Find Vulkan (สำหรับ Android ใช้จาก NDK)
find_package(Vulkan QUIET)

if(Vulkan_FOUND)
    message(STATUS "✅ Vulkan found: ${Vulkan_VERSION}")
    set(GGML_VULKAN ON CACHE BOOL "" FORCE)
    set(GGML_VULKAN_CHECK_RESULTS OFF CACHE BOOL "" FORCE)
else()
    message(WARNING "⚠️  Vulkan not found, falling back to CPU only")
    set(GGML_VULKAN OFF CACHE BOOL "" FORCE)
endif()

# =============================================================================
# llama.cpp Configuration
# =============================================================================

# Build options
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)

# Disable x86-specific optimizations
set(LLAMA_AVX OFF CACHE BOOL "" FORCE)
set(LLAMA_AVX2 OFF CACHE BOOL "" FORCE)
set(LLAMA_AVX512 OFF CACHE BOOL "" FORCE)
set(LLAMA_FMA OFF CACHE BOOL "" FORCE)
set(LLAMA_F16C OFF CACHE BOOL "" FORCE)

# Architecture-specific settings
if(ANDROID_ABI STREQUAL "arm64-v8a")
    set(LLAMA_ARM_FMA ON CACHE BOOL "" FORCE)
    set(LLAMA_NEON ON CACHE BOOL "" FORCE)
    message(STATUS "📱 ARM64 build - NEON enabled")
    
elseif(ANDROID_ABI STREQUAL "armeabi-v7a")
    set(LLAMA_ARM_FMA ON CACHE BOOL "" FORCE)
    set(LLAMA_NEON ON CACHE BOOL "" FORCE)
    # Disable FP16 for 32-bit ARM
    add_compile_definitions(GGML_NO_FP16=1)
    message(STATUS "📱 ARMv7 build - NEON only (no FP16)")
    
elseif(ANDROID_ABI STREQUAL "x86_64")
    set(LLAMA_ARM_FMA OFF CACHE BOOL "" FORCE)
    set(LLAMA_NEON OFF CACHE BOOL "" FORCE)
    message(STATUS "💻 x86_64 build (emulator)")
endif()

# Metal is iOS only
set(LLAMA_METAL OFF CACHE BOOL "" FORCE)

# CUDA is desktop only
set(LLAMA_CUDA OFF CACHE BOOL "" FORCE)

# OpenMP - disable for compatibility
set(LLAMA_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)

# Disable LLAMAFILE to avoid FP16 issues
set(GGML_USE_LLAMAFILE OFF CACHE BOOL "" FORCE)

# Quantization support
set(GGML_QKK_64 ON CACHE BOOL "" FORCE)

# =============================================================================
# Add llama.cpp subdirectory
# =============================================================================

# Include llama.cpp build
add_subdirectory(${LLAMA_ROOT} llama.cpp_build)

# =============================================================================
# JNI Bridge
# =============================================================================

add_library(
    haku_llm
    SHARED
    llama_jni.cpp
)

target_include_directories(
    haku_llm
    PRIVATE
    ${LLAMA_ROOT}
    ${LLAMA_ROOT}/include
    ${LLAMA_ROOT}/ggml/include
)

if(Vulkan_FOUND)
    target_include_directories(haku_llm PRIVATE ${Vulkan_INCLUDE_DIRS})
endif()

target_link_libraries(
    haku_llm
    llama
    ggml
    log
    android
)

if(Vulkan_FOUND)
    target_link_libraries(haku_llm ${Vulkan_LIBRARIES})
endif()

# =============================================================================
# Compiler Flags
# =============================================================================

if(CMAKE_BUILD_TYPE STREQUAL "Release")
    target_compile_options(haku_llm PRIVATE
        -O3
        -flto
        -ffunction-sections
        -fdata-sections
        -DNDEBUG
    )
    target_link_options(haku_llm PRIVATE
        -Wl,--gc-sections
        -flto
        -s
    )
else()
    target_compile_options(haku_llm PRIVATE
        -O0
        -g
        -DDEBUG
    )
endif()

set_target_properties(haku_llm PROPERTIES
    POSITION_INDEPENDENT_CODE ON
)

# =============================================================================
# Installation
# =============================================================================

install(TARGETS haku_llm DESTINATION lib/${ANDROID_ABI})

# Install libc++_shared if needed
if(ANDROID_STL STREQUAL "c++_shared")
    file(GLOB CXX_SHARED
        "${ANDROID_NDK}/toolchains/llvm/prebuilt/*/sysroot/usr/lib/${ANDROID_HOST_TAG}/libc++_shared.so"
    )
    if(CXX_SHARED)
        install(FILES ${CXX_SHARED} DESTINATION lib/${ANDROID_ABI})
    endif()
endif()

message(STATUS "✅ Configuration complete!")
if(GGML_VULKAN)
    message(STATUS "🎮 Vulkan GPU acceleration: ENABLED")
else()
    message(STATUS "⚠️  Vulkan GPU acceleration: DISABLED (CPU only)")
endif()
