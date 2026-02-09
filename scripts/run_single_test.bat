@echo off
chcp 65001 >nul
echo 🧪 Run Single Integration Test
echo ===============================
echo.

if "%~1"=="" (
    echo Usage: run_single_test.bat [test_name]
    echo.
    echo Available tests:
    echo   - chat        : Chat and Haku Engine tests
    echo   - map         : Map and Places tests
    echo   - battery     : Battery optimization tests
    echo   - ai_actions  : AI Actions and Web Search tests
    echo   - calendar    : Google Calendar tests
    echo   - llm         : MediaPipe LLM tests
    echo   - all         : Run all tests
    echo.
    exit /b 1
)

cd /d "%~dp0.."

set TEST_NAME=%~1
echo 🎯 Running: %TEST_NAME%
echo.

if "%TEST_NAME%"=="chat" (
    flutter test integration_test/tests/chat_test.dart
) else if "%TEST_NAME%"=="map" (
    flutter test integration_test/tests/map_test.dart
) else if "%TEST_NAME%"=="battery" (
    flutter test integration_test/tests/battery_test.dart
) else if "%TEST_NAME%"=="ai_actions" (
    flutter test integration_test/tests/ai_actions_test.dart
) else if "%TEST_NAME%"=="calendar" (
    flutter test integration_test/tests/calendar_test.dart
) else if "%TEST_NAME%"=="llm" (
    flutter test integration_test/tests/llm_test.dart
) else if "%TEST_NAME%"=="all" (
    flutter test integration_test/app_test.dart
) else (
    echo ❌ Unknown test: %TEST_NAME%
    exit /b 1
)

if %errorlevel% neq 0 (
    echo.
    echo ❌ Test failed
) else (
    echo.
    echo ✅ Test passed!
)

echo.
pause
