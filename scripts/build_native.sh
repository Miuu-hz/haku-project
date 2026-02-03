#!/bin/bash

# =============================================================================
# 🤖 Build Native Libraries for Haku Android
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CPP_DIR="$PROJECT_ROOT/android/app/src/main/cpp"
JNILIBS_DIR="$PROJECT_ROOT/android/app/src/main/jniLibs"

echo "🎌 Haku Native Build Script"
echo "============================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# =============================================================================
# Check prerequisites
# =============================================================================

check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${RED}❌ $1 is not installed${NC}"
        return 1
    fi
    echo -e "${GREEN}✅ $1 found${NC}"
    return 0
}

echo "🔍 Checking prerequisites..."
echo ""

# Check Android NDK
if [ -z "$ANDROID_HOME" ]; then
    echo -e "${RED}❌ ANDROID_HOME is not set${NC}"
    echo "   Please set ANDROID_HOME to your Android SDK directory"
    exit 1
fi

NDK_VERSION="25.2.9519653"
NDK_PATH="$ANDROID_HOME/ndk/$NDK_VERSION"

if [ ! -d "$NDK_PATH" ]; then
    echo -e "${YELLOW}⚠️  NDK $NDK_VERSION not found at $NDK_PATH${NC}"
    echo "   Installing NDK..."
    sdkmanager "ndk;$NDK_VERSION"
fi

echo -e "${GREEN}✅ NDK found at $NDK_PATH${NC}"

# Check CMake
if ! check_command cmake; then
    echo "   Installing CMake..."
    sdkmanager "cmake;3.22.1"
fi

# Check llama.cpp
if [ ! -d "$CPP_DIR/llama.cpp" ]; then
    echo -e "${YELLOW}⚠️  llama.cpp not found${NC}"
    echo "   Cloning llama.cpp..."
    git clone --recursive https://github.com/ggerganov/llama.cpp.git "$CPP_DIR/llama.cpp"
fi

echo -e "${GREEN}✅ llama.cpp found${NC}"
echo ""

# =============================================================================
# Build configuration
# =============================================================================

BUILD_TYPE="Release"
BUILD_ABIS="arm64-v8a armeabi-v7a x86_64"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --debug)
            BUILD_TYPE="Debug"
            shift
            ;;
        --abi)
            BUILD_ABIS="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "🛠️  Build Configuration:"
echo "   Type: $BUILD_TYPE"
echo "   ABIs: $BUILD_ABIS"
echo ""

# =============================================================================
# Build for each ABI
# =============================================================================

mkdir -p "$JNILIBS_DIR"

for ABI in $BUILD_ABIS; do
    echo "🔨 Building for $ABI..."
    
    BUILD_DIR="$PROJECT_ROOT/build-native/$ABI"
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    
    # Configure with CMake
    cmake "$CPP_DIR" \
        -DCMAKE_TOOLCHAIN_FILE="$NDK_PATH/build/cmake/android.toolchain.cmake" \
        -DANDROID_ABI="$ABI" \
        -DANDROID_PLATFORM=android-24 \
        -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
        -DANDROID_STL=c++_shared \
        -DCMAKE_INSTALL_PREFIX="$BUILD_DIR/install"
    
    # Build
    cmake --build . --parallel $(nproc 2>/dev/null || echo 4)
    
    # Copy to jniLibs
    mkdir -p "$JNILIBS_DIR/$ABI"
    
    # Find and copy all .so files
    find . -name "*.so" -type f -exec cp {} "$JNILIBS_DIR/$ABI/" \;
    
    echo -e "${GREEN}✅ Built for $ABI${NC}"
    echo ""
done

# =============================================================================
# Summary
# =============================================================================

echo "📦 Build Complete!"
echo "=================="
echo ""
echo "Libraries built:"
find "$JNILIBS_DIR" -name "*.so" -type f | while read f; do
    echo "   📄 $f"
done

echo ""
echo -e "${GREEN}✅ Native libraries are ready!${NC}"
echo ""
echo "Next steps:"
echo "   flutter clean"
echo "   flutter run"
echo ""
