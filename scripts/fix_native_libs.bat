@echo off
chcp 65001 >nul
echo 🔧 Fix MediaPipe Native Libraries
echo ==================================
echo.

cd /d "%~dp0.."

echo [1/6] Deep clean...
if exist build rmdir /s /q build 2>nul
if exist .dart_tool rmdir /s /q .dart_tool 2>nul
cd android
if exist build rmdir /s /q build 2>nul
if exist .gradle rmdir /s /q .gradle 2>nul
if exist app\build rmdir /s /q app\build 2>nul
if exist app\.cxx rmdir /s /q app\.cxx 2>nul
cd ..

echo [2/6] Stopping Gradle daemon...
cd android
.\gradlew --stop 2>nul
cd ..

echo [3/6] Getting Flutter packages...
for /f "tokens=2 delims==" %%a in ('type android\local.properties ^| findstr "flutter.sdk"') do set FLUTTER_SDK=%%a
set FLUTTER_SDK=%FLUTTER_SDK: =%
"%FLUTTER_SDK%\bin\flutter.bat" pub get

echo [4/6] Building APK with native libs...
cd android
call .\gradlew clean
rem Build with explicit ABI settings
call .\gradlew assembleDebug -Pandroid.injected.build.abi=arm64-v8a,armeabi-v7a
cd ..

echo [5/6] Installing to device...
"%FLUTTER_SDK%\bin\flutter.bat" install

echo [6/6] Done!
echo.
echo Check if libllm_inference_engine_jni.so is in APK:
echo   unzip -l build\app\outputs\flutter-apk\app-debug.apk ^| findstr libllm
pause
