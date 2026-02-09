@echo off
chcp 65001 >nul
echo 🧹 Clean Build for Haku
echo =======================
echo.

cd /d "%~dp0.."

echo [1/8] Cleaning Flutter build...
if exist build rmdir /s /q build 2>nul
if exist .dart_tool rmdir /s /q .dart_tool 2>nul
if exist .flutter-plugins rmdir /s /q .flutter-plugins 2>nul
if exist .flutter-plugins-dependencies rmdir /s /q .flutter-plugins-dependencies 2>nul

echo [2/8] Cleaning Android build...
cd android
if exist build rmdir /s /q build 2>nul
if exist .gradle rmdir /s /q .gradle 2>nul
if exist app\build rmdir /s /q app\build 2>nul
cd ..

echo [3/8] Finding Flutter SDK...
for /f "tokens=2 delims==" %%a in ('type android\local.properties ^| findstr "flutter.sdk"') do set FLUTTER_SDK=%%a
set FLUTTER_SDK=%FLUTTER_SDK: =%
echo Flutter SDK: %FLUTTER_SDK%

echo [4/8] Running flutter pub get...
"%FLUTTER_SDK%\bin\flutter.bat" pub get
if %errorlevel% neq 0 (
    echo ❌ flutter pub get failed
    pause
    exit /b 1
)

echo [5/8] Cleaning Android gradle...
cd android
call .\gradlew clean
if %errorlevel% neq 0 (
    echo ⚠️ gradlew clean failed (may be OK for first run)
)
cd ..

echo [6/8] Building debug APK...
"%FLUTTER_SDK%\bin\flutter.bat" build apk --debug
if %errorlevel% neq 0 (
    echo ❌ Build failed
    pause
    exit /b 1
)

echo [7/8] ✅ Build complete!
echo.
echo APK location: build\app\outputs\flutter-apk\app-debug.apk
echo.
echo Next step: flutter run
echo.
pause
