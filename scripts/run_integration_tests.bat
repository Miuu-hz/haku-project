@echo off
chcp 65001 >nul
echo 🧪 Haku Integration Tests
echo =========================
echo.

REM Check if Flutter is installed
where flutter >nul 2>nul
if %errorlevel% neq 0 (
    echo ❌ Flutter not found in PATH
    exit /b 1
)

REM Check if device is connected
echo 📱 Checking connected devices...
flutter devices | findstr "mobile" >nul
if %errorlevel% neq 0 (
    echo ❌ No mobile device connected
    echo    Please connect an Android device or start an emulator
    exit /b 1
)

echo ✅ Device connected
echo.

REM Run tests
echo 🚀 Running integration tests...
echo.

cd /d "%~dp0.."

REM Option 1: Run all tests
echo [1/2] Running all tests...
flutter test integration_test/app_test.dart

if %errorlevel% neq 0 (
    echo.
    echo ❌ Some tests failed
) else (
    echo.
    echo ✅ All tests passed!
)

echo.
echo 📝 Test completed
echo.
pause
