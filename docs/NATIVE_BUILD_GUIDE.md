# 🤖 Native Build Guide (Step-by-Step)

คู่มือการ build native libraries สำหรับ Haku LLM

## 📋 สิ่งที่ต้องมี

### 1. Android Studio & SDK
- [Download Android Studio](https://developer.android.com/studio)
- ติดตั้ง Android SDK (API 24+)

### 2. Android NDK
```bash
# ผ่าน Android Studio:
SDK Manager → SDK Tools → NDK (Side by side) → 25.2.9519653

# หรือผ่าน command line:
sdkmanager "ndk;25.2.9519653"
```

### 3. CMake
```bash
# ผ่าน Android Studio:
SDK Manager → SDK Tools → CMake → 3.22.1

# หรือดาวน์โหลดจาก:
# https://cmake.org/download/
```

### 4. ตั้งค่า Environment Variables

#### Windows (PowerShell - Run as Administrator):
```powershell
[Environment]::SetEnvironmentVariable("ANDROID_HOME", "$env:LOCALAPPDATA\Android\Sdk", "User")
# เพิ่มใน Path: %ANDROID_HOME%\platform-tools
```

#### macOS/Linux:
```bash
# ~/.bashrc หรือ ~/.zshrc
export ANDROID_HOME=$HOME/Library/Android/sdk  # macOS
# export ANDROID_HOME=$HOME/Android/Sdk        # Linux
export PATH=$PATH:$ANDROID_HOME/platform-tools
```

---

## 🚀 วิธี Build

### วิธีที่ 1: ใช้ Script (แนะนำ)

#### macOS/Linux:
```bash
cd scripts
chmod +x build_native.sh
./build_native.sh
```

#### Windows:
```powershell
cd scripts
.\build_native.ps1
```

### วิธีที่ 2: Build ด้วย Flutter (อัตโนมัติ)

```bash
# 1. Clone llama.cpp ก่อน
git clone --recursive https://github.com/ggerganov/llama.cpp.git android/app/src/main/cpp/llama.cpp

# 2. Flutter จะ build native ให้อัตโนมัติตอน run
flutter run
```

### วิธีที่ 3: Build ด้วย Android Gradle

```bash
# Build ผ่าน Gradle
cd android
.\gradlew assembleDebug  # Windows
./gradlew assembleDebug  # macOS/Linux

# หรือ build release
.\gradlew assembleRelease
```

### วิธีที่ 4: Build ผ่าน CI/CD (ไม่ต้องมี NDK)

ถ้าไม่ต้องการติดตั้ง NDK เอง ให้ใช้ GitHub Actions:

1. Push code ขึ้น GitHub
2. GitHub Actions จะ build native libraries ให้
3. ดาวน์โหลด artifacts จาก Actions tab
4. แตกไฟล์ไว้ที่ `android/app/src/main/jniLibs/`

---

## 🔧 Build Options

### Build แบบ Debug (สำหรับพัฒนา)
```bash
# Script
./build_native.sh --debug
# หรือ
.\build_native.ps1 -Debug

# Gradle
./gradlew assembleDebug
```

### Build เฉพาะบาง Architecture
```bash
# เฉพาะ arm64 (ส่วนใหญ่ใช้อันนี้)
./build_native.sh --abi arm64-v8a
# หรือ
.\build_native.ps1 -Abi "arm64-v8a"
```

### Build Stub Only (ไม่ต้องการ llama.cpp)
```bash
./build_native.sh --stub-only
# หรือ
.\build_native.ps1 -StubOnly
```

---

## 📁 Output Structure

หลัง build สำเร็จ:

```
android/app/src/main/jniLibs/
├── arm64-v8a/
│   ├── libhaku_llm.so
│   └── libc++_shared.so
├── armeabi-v7a/
│   ├── libhaku_llm.so
│   └── libc++_shared.so
└── x86_64/
    ├── libhaku_llm.so
    └── libc++_shared.so
```

---

## ⚠️ Troubleshooting

### 1. `ANDROID_HOME is not set`
**ปัญหา:** Environment variable ไม่ได้ตั้งค่า

**แก้ไข:**
```bash
# Windows (PowerShell)
[Environment]::SetEnvironmentVariable("ANDROID_HOME", "C:\Users\<username>\AppData\Local\Android\Sdk", "User")

# macOS/Linux
export ANDROID_HOME=$HOME/Library/Android/sdk
```

### 2. `CMake Error: Could not find toolchain file`
**ปัญหา:** NDK ไม่ถูกต้องหรือไม่มี

**แก้ไข:**
```bash
# ตรวจสอบ NDK path
ls $ANDROID_HOME/ndk/25.2.9519653

# ถ้าไม่มี ให้ติดตั้ง
sdkmanager "ndk;25.2.9519653"
```

### 3. `UnsatisfiedLinkError: dlopen failed`
**ปัญหา:** Native library ไม่ตรงกับ device architecture

**แก้ไข:**
```bash
# Build ทุก architecture
./build_native.sh

# หรือ build เฉพาะ architecture ของ device
# ดู architecture: adb shell getprop ro.product.cpu.abi
```

### 4. `ld: error: undefined reference to '...'`
**ปัญหา:** llama.cpp ไม่สมบูรณ์หรือ version ไม่ตรงกัน

**แก้ไข:**
```bash
# ลบแล้ว clone ใหม่
rm -rf android/app/src/main/cpp/llama.cpp
git clone --recursive https://github.com/ggerganov/llama.cpp.git android/app/src/main/cpp/llama.cpp
```

### 5. Build ช้ามาก / Out of memory
**ปัญหา:** llama.cpp มีไฟล์เยอะ ใช้ RAM/CPU สูง

**แก้ไข:**
```bash
# Build ทีละ architecture
./build_native.sh --abi arm64-v8a

# หรือลด parallel jobs
export CMAKE_BUILD_PARALLEL_LEVEL=2
```

---

## 🎯 Quick Start (สรุป)

```bash
# 1. ติดตั้ง NDK ผ่าน Android Studio
# SDK Manager > SDK Tools > NDK (Side by side) > 25.2.9519653

# 2. Clone llama.cpp
git clone --recursive https://github.com/ggerganov/llama.cpp.git android/app/src/main/cpp/llama.cpp

# 3. Build
cd scripts
chmod +x build_native.sh
./build_native.sh

# 4. Run
flutter run
```

---

## 📚 References

- [Android NDK Guide](https://developer.android.com/ndk/guides)
- [llama.cpp Build Guide](https://github.com/ggerganov/llama.cpp/blob/master/docs/build.md)
- [CMake Android Toolchain](https://developer.android.com/ndk/guides/cmake)
