# 🤖 Haku LLM Setup Guide

คู่มือการตั้งค่า LLM (Local Language Model) สำหรับ Haku App บน Android

## ⚡ Quick Start

### 1. ติดตั้ง NDK
```bash
# ผ่าน Android Studio:
# SDK Manager → SDK Tools → NDK (Side by side) → 25.2.9519653
```

### 2. Clone llama.cpp
```bash
git clone --recursive https://github.com/ggerganov/llama.cpp.git android/app/src/main/cpp/llama.cpp
```

### 3. Build และ Run
```bash
flutter clean
flutter run
```

หรือใช้ build script:
```bash
cd scripts
./build_native.sh        # macOS/Linux
.\build_native.ps1       # Windows
```

---

## 📖 คู่มือละเอียด

- [Native Build Guide](./NATIVE_BUILD_GUIDE.md) - วิธี build native libraries
- [GitHub Actions CI/CD](../.github/workflows/build-native.yml) - Build ผ่าน CI

---

## 📁 Project Structure

```
android/app/src/main/
├── cpp/
│   ├── CMakeLists.txt          # CMake configuration
│   ├── llama_jni.cpp           # JNI bridge (llama.cpp interface)
│   ├── stub_llm.cpp            # Fallback stub (ถ้าไม่มี llama.cpp)
│   └── llama.cpp/              # llama.cpp source (clone from GitHub)
├── kotlin/com/example/haku/
│   ├── MainActivity.kt         # Flutter Activity + MethodChannel
│   └── LLMBridge.kt            # Kotlin wrapper สำหรับ JNI
└── jniLibs/                    # Prebuilt libraries (after build)
    ├── arm64-v8a/
    ├── armeabi-v7a/
    └── x86_64/
```

---

## 🔧 MethodChannel API

Channel: `com.example.haku/llm`

| Method | Parameters | Return | Description |
|--------|-----------|--------|-------------|
| `loadModel` | `modelPath`, `contextSize`, `gpuLayers` | `bool` | โหลดโมเดล GGUF |
| `generate` | `prompt`, `temperature`, `maxTokens` | `String` | สร้างข้อความ |
| `generateStream` | `prompt`, `temperature`, `maxTokens` | `String` | (TODO: Stream) |
| `unloadModel` | - | `null` | ปิดโมเดล |
| `isModelLoaded` | - | `bool` | ตรวจสอบสถานะ |
| `getModelInfo` | - | `String` | ข้อมูลโมเดล (JSON) |

---

## 📥 โมเดลที่รองรับ

### ที่แนะนำสำหรับมือถือ
| โมเดล | ขนาด | ภาษาไทย | ภาพ | ดาวน์โหลด |
|-------|------|---------|-----|-----------|
| Qwen3-VL-4B | ~2.4GB | ✅ | ✅ | [Hugging Face](https://huggingface.co/) |
| LLaMA-3-8B | ~4.5GB | ⚠️ | ❌ | [Meta](https://ai.meta.com/llama/) |
| Mistral-7B | ~4GB | ⚠️ | ❌ | [Hugging Face](https://huggingface.co/mistralai) |
| Phi-3-mini | ~2GB | ⚠️ | ❌ | [Microsoft](https://huggingface.co/microsoft) |
| Gemma-2B | ~1.5GB | ⚠️ | ❌ | [Google](https://huggingface.co/google) |

**หมายเหตุ:** ต้อง convert เป็น `.gguf` format ก่อนใช้งาน

---

## 🔧 การวางโมเดล

### วิธีที่ 1: External Storage (แนะนำ)
```bash
# Push ไฟล์ผ่าน ADB
adb push model.gguf /sdcard/Android/data/com.example.haku/files/models/
```

### วิธีที่ 2: App Documents (อัตโนมัติ)
```
# แอพจะ copy ไปยัง app storage อัตโนมัติตอน run
```

### วิธีที่ 3: Development Path
```
project_root/
├── models/
│   └── model.gguf          # แอพจะหาจากที่นี่ตอน dev
```

---

## ⚠️ Troubleshooting

### แอพ crash ตอน start (`UnsatisfiedLinkError`)
```bash
# Clean และ rebuild
flutter clean
cd android && ./gradlew clean && cd ..
flutter run
```

### `MissingPluginException` สำหรับ LLM
- ยังไม่ได้ build native libraries → [ดูคู่มือ build](./NATIVE_BUILD_GUIDE.md)
- หรือใช้ CI/CD artifacts จาก GitHub Actions

### Out of memory เวลา load โมเดล
- ลด `contextSize` (2048 แทน 4096)
- ใช้โมเดล quantize มากขึ้น (Q4_K_M → Q3_K_S)
- ปิดแอพอื่นก่อนรัน

### Slow inference
- เพิ่ม threads ใน `llama_jni.cpp`
- ลองใช้ GPU (เพิ่ม `gpuLayers`)
- ใช้โมเดลขนาดเล็กลง

---

## 🔬 Development Mode (ไม่มี LLM)

ถ้ายังไม่ต้องการ LLM:

```bash
# สร้าง stub library แทน
cd scripts
./build_native.sh --stub-only
```

หรือไม่ต้องทำอะไร - แอพจะแสดง error แล้ว fallback ไปใช้ mock/cloud API

---

## 📚 References

- [llama.cpp](https://github.com/ggerganov/llama.cpp)
- [GGUF Format](https://github.com/ggerganov/ggml/blob/master/docs/gguf.md)
- [Flutter MethodChannel](https://docs.flutter.dev/platform-integration/platform-channels)
- [Android NDK](https://developer.android.com/ndk)
