set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR AMD64)

set(CMAKE_BUILD_TYPE Release)
set(CMAKE_C_FLAGS "/O2")
set(CMAKE_CXX_FLAGS "/O2")

# MSVC compiler
set(CMAKE_C_COMPILER   "C:/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC/14.44.35207/bin/Hostx64/x64/cl.exe")
set(CMAKE_CXX_COMPILER "C:/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC/14.44.35207/bin/Hostx64/x64/cl.exe")

# MSVC linker and tools
set(CMAKE_LINKER "C:/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC/14.44.35207/bin/Hostx64/x64/link.exe")
set(CMAKE_MT     "C:/Program Files (x86)/Windows Kits/10/bin/10.0.26100.0/x64/mt.exe")
set(CMAKE_RC_COMPILER "C:/Program Files (x86)/Windows Kits/10/bin/10.0.26100.0/x64/rc.exe")

# Ninja build tool
set(CMAKE_MAKE_PROGRAM "F:/AndroidSDK/cmake/3.22.1/bin/ninja.exe")

# MSVC include paths
set(MSVC_ROOT "C:/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC/14.44.35207")
set(WINSDK_ROOT "C:/Program Files (x86)/Windows Kits/10")
set(WINSDK_VERSION "10.0.26100.0")

include_directories(SYSTEM
    "${MSVC_ROOT}/include"
    "${WINSDK_ROOT}/Include/${WINSDK_VERSION}/ucrt"
    "${WINSDK_ROOT}/Include/${WINSDK_VERSION}/um"
    "${WINSDK_ROOT}/Include/${WINSDK_VERSION}/shared"
)

link_directories(
    "${MSVC_ROOT}/lib/x64"
    "${WINSDK_ROOT}/Lib/${WINSDK_VERSION}/ucrt/x64"
    "${WINSDK_ROOT}/Lib/${WINSDK_VERSION}/um/x64"
)

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE NEVER)
