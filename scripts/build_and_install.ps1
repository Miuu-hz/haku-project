# Build and Install Script for Haku
# แก้ปัญหา APK อยู่ผิดที่หลัง flutter clean

Write-Host "🔨 Building Haku..." -ForegroundColor Cyan

# Build
flutter build apk --debug

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Build failed!" -ForegroundColor Red
    exit 1
}

# สร้าง directory ถ้ายังไม่มี
$flutterApkDir = "build\app\outputs\flutter-apk"
$androidApk = "android\app\build\outputs\flutter-apk\app-debug.apk"
$targetApk = "$flutterApkDir\app-debug.apk"

if (!(Test-Path $flutterApkDir)) {
    New-Item -ItemType Directory -Path $flutterApkDir -Force | Out-Null
}

# Copy APK ไปที่ Flutter คาดหวัง
if (Test-Path $androidApk) {
    Copy-Item $androidApk $targetApk -Force
    Write-Host "✅ APK copied to $targetApk" -ForegroundColor Green
} else {
    Write-Host "❌ APK not found at $androidApk" -ForegroundColor Red
    exit 1
}

# Install
Write-Host "📱 Installing..." -ForegroundColor Cyan
flutter install --debug

Write-Host "🎉 Done!" -ForegroundColor Green
