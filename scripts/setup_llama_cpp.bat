@echo off
chcp 65001 >nul
REM =============================================================================
REM 🤖 Setup llama.cpp for Haku Android (Windows)
REM =============================================================================

set "SCRIPT_DIR=%~dp0"
set "PROJECT_ROOT=%SCRIPT_DIR%.."
set "LLAMA_CPP_DIR=%PROJECT_ROOT%\android\app\src\main\cpp\llama.cpp"

echo 🎌 Haku LLM Setup Script (Windows)
echo =================================
echo.

REM Check if llama.cpp already exists
if exist "%LLAMA_CPP_DIR%\.git" (
    echo 📁 llama.cpp already exists at:
    echo    %LLAMA_CPP_DIR%
    echo.
    set /p UPDATE="🔄 Do you want to update it? (y/n): "
    if /i "%UPDATE%"=="y" (
        echo 🔄 Updating llama.cpp...
        cd /d "%LLAMA_CPP_DIR%"
        git pull origin master
        git submodule update --init --recursive
        echo ✅ llama.cpp updated!
    ) else (
        echo ⏩ Skipping update
    )
) else (
    echo 📥 Cloning llama.cpp...
    echo    Target: %LLAMA_CPP_DIR%
    echo.
    
    REM Clone llama.cpp repository
    git clone --recursive https://github.com/ggerganov/llama.cpp.git "%LLAMA_CPP_DIR%"
    
    echo.
    echo ✅ llama.cpp cloned successfully!
)

echo.
echo 📋 Next Steps:
echo ==============
echo.
echo 1. 🛠️  Install Android NDK:
echo    - Open Android Studio
echo    - SDK Manager ^> SDK Tools ^> NDK (Side by side) ^> 25.2.9519653
echo.
echo 2. 🛠️  Build the native libraries:
echo    cd android
echo    .\gradlew assembleDebug
echo.
echo 3. 🚀 Run the app:
echo    flutter run
echo.
echo 4. 📱 Place your .gguf model file at:
echo    /sdcard/Android/data/com.example.haku/files/models/
echo.
echo ⚠️  Requirements:
echo    - Android NDK (version 25.2.9519653 or later)
echo    - CMake (version 3.22.1 or later)
echo    - Minimum Android SDK 24
echo.

pause
