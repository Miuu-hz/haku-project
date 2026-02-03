#!/bin/bash

# =============================================================================
# 🤖 Setup llama.cpp for Haku Android
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LLAMA_CPP_DIR="$PROJECT_ROOT/android/app/src/main/cpp/llama.cpp"

echo "🎌 Haku LLM Setup Script"
echo "========================"
echo ""

# Check if llama.cpp already exists
if [ -d "$LLAMA_CPP_DIR" ]; then
    echo "📁 llama.cpp already exists at:"
    echo "   $LLAMA_CPP_DIR"
    echo ""
    read -p "🔄 Do you want to update it? (y/n): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "🔄 Updating llama.cpp..."
        cd "$LLAMA_CPP_DIR"
        git pull origin master
        git submodule update --init --recursive
        echo "✅ llama.cpp updated!"
    else
        echo "⏩ Skipping update"
    fi
else
    echo "📥 Cloning llama.cpp..."
    echo "   Target: $LLAMA_CPP_DIR"
    echo ""
    
    # Clone llama.cpp repository
    git clone --recursive https://github.com/ggerganov/llama.cpp.git "$LLAMA_CPP_DIR"
    
    echo ""
    echo "✅ llama.cpp cloned successfully!"
fi

echo ""
echo "📋 Next Steps:"
echo "=============="
echo ""
echo "1. 🛠️  Build the native libraries:"
echo "   cd android"
echo "   ./gradlew assembleDebug"
echo ""
echo "2. 🚀 Run the app:"
echo "   flutter run"
echo ""
echo "3. 📱 Place your .gguf model file at:"
echo "   /sdcard/Android/data/com.example.haku/files/models/"
echo ""
echo "⚠️  Requirements:"
echo "   - Android NDK (version 25.2.9519653 or later)"
echo "   - CMake (version 3.22.1 or later)"
echo "   - Minimum Android SDK 24"
echo ""
