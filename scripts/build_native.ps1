# =============================================================================
# 🤖 Build Native Libraries for Haku Android (Windows PowerShell)
# =============================================================================

param(
    [switch]$Debug,
    [string]$Abi = "arm64-v8a,armeabi-v7a,x86_64",
    [switch]$StubOnly
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$CppDir = "$ProjectRoot\android\app\src\main\cpp"
$JniLibsDir = "$ProjectRoot\android\app\src\main\jniLibs"

Write-Host "🎌 Haku Native Build Script (Windows)" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""



# =============================================================================
# Check prerequisites
# =============================================================================

function Test-Command {
    param([string]$Command)
    $null = Get-Command $Command -ErrorAction SilentlyContinue
    return $?
}

Write-Host "🔍 Checking prerequisites..." -ForegroundColor Yellow
Write-Host ""

# Check ANDROID_HOME
if (-not $env:ANDROID_HOME) {
    Write-Host "❌ ANDROID_HOME is not set" -ForegroundColor Red
    Write-Host "   Please set ANDROID_HOME to your Android SDK directory"
    Write-Host "   Example: [System.Environment]::SetEnvironmentVariable('ANDROID_HOME', 'C:\Users\<user>\AppData\Local\Android\Sdk', 'User')"
    exit 1
}

$NdkVersion = "25.2.9519653"
$NdkPath = "$env:ANDROID_HOME\ndk\$NdkVersion"

if (-not (Test-Path $NdkPath)) {
    Write-Host "⚠️  NDK $NdkVersion not found at $NdkPath" -ForegroundColor Yellow
    Write-Host "   Please install NDK through Android Studio:"
    Write-Host "   SDK Manager > SDK Tools > NDK (Side by side) > $NdkVersion"
    exit 1
}

Write-Host "✅ NDK found at $NdkPath" -ForegroundColor Green

# Check CMake
if (-not (Test-Command "cmake")) {
    Write-Host "⚠️  CMake not found in PATH" -ForegroundColor Yellow
    Write-Host "   Installing via SDK Manager..."
    & "$env:ANDROID_HOME\cmdline-tools\latest\bin\sdkmanager.bat" "cmake;3.22.1"
}

# Check llama.cpp
if (-not (Test-Path "$CppDir\llama.cpp")) {
    Write-Host "⚠️  llama.cpp not found" -ForegroundColor Yellow
    Write-Host "   Cloning llama.cpp..."
    git clone --recursive https://github.com/ggerganov/llama.cpp.git "$CppDir\llama.cpp"
}

Write-Host "✅ llama.cpp found" -ForegroundColor Green
Write-Host ""

# =============================================================================
# Build configuration
# =============================================================================

$BuildType = if ($Debug) { "Debug" } else { "Release" }
$BuildAbis = $Abi -split ","

if ($StubOnly) {
    Write-Host "📝 Building STUB library only" -ForegroundColor Yellow
}

Write-Host "🛠️  Build Configuration:" -ForegroundColor Yellow
Write-Host "   Type: $BuildType"
Write-Host "   ABIs: $Abi"
Write-Host ""

# =============================================================================
# Build for each ABI
# =============================================================================

New-Item -ItemType Directory -Force -Path $JniLibsDir | Out-Null

foreach ($CurrentAbi in $BuildAbis) {
    Write-Host "🔨 Building for $CurrentAbi..." -ForegroundColor Yellow
    
    $BuildDir = "$ProjectRoot\build-native\$CurrentAbi"
    New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
    
    $CMakeArgs = @(
        "$CppDir",
        "-DCMAKE_TOOLCHAIN_FILE=$NdkPath\build\cmake\android.toolchain.cmake",
        "-DANDROID_ABI=$CurrentAbi",
        "-DANDROID_PLATFORM=android-24",
        "-DCMAKE_BUILD_TYPE=$BuildType",
        "-DANDROID_STL=c++_shared"
    )
    
    if ($StubOnly) {
        $CMakeArgs += "-DBUILD_STUB_ONLY=ON"
    }
    
    # Configure with CMake
    Push-Location $BuildDir
    & cmake @CMakeArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ CMake configuration failed for $CurrentAbi" -ForegroundColor Red
        Pop-Location
        continue
    }
    
    # Build
    $CpuCount = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
    & cmake --build . --parallel $CpuCount
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Build failed for $CurrentAbi" -ForegroundColor Red
        Pop-Location
        continue
    }
    Pop-Location
    
    # Copy to jniLibs
    $AbiDir = "$JniLibsDir\$CurrentAbi"
    New-Item -ItemType Directory -Force -Path $AbiDir | Out-Null
    
    Get-ChildItem -Path $BuildDir -Recurse -Filter "*.so" | ForEach-Object {
        Copy-Item $_.FullName -Destination $AbiDir -Force
    }
    
    Write-Host "✅ Built for $CurrentAbi" -ForegroundColor Green
    Write-Host ""
}

# =============================================================================
# Summary
# =============================================================================

Write-Host "📦 Build Complete!" -ForegroundColor Green
Write-Host "=================="
Write-Host ""
Write-Host "Libraries built:"
Get-ChildItem -Path $JniLibsDir -Recurse -Filter "*.so" | ForEach-Object {
    Write-Host "   📄 $($_.FullName)"
}

Write-Host ""
Write-Host "✅ Native libraries are ready!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:"
Write-Host "   flutter clean"
Write-Host "   flutter run"
Write-Host ""
