#!/bin/bash

# 🎌 Setup Script สำหรับ LLM in Haku
# รัน script นี้ครั้งเดียวตอนเริ่ม project

echo "🎌 Setting up LLM for Haku..."
echo ""

# สร้างโฟลเดอร์
mkdir -p assets/models
mkdir -p android/app/src/main/jniLibs/arm64-v8a

echo "📁 โฟลเดอร์พร้อมแล้ว"
echo ""

# ตรวจสอบว่ามีไฟล์โมเดลหรือยัง
if [ -f "assets/models/qwen3-vl-4b-thinking-q4.gguf" ]; then
    echo "✅ พบโมเดลแล้ว"
    ls -lh assets/models/
else
    echo "⚠️  ยังไม่มีโมเดล"
    echo ""
    echo "เลือกวิธีโหลด:"
    echo "1. รัน: ./scripts/download_qwen3.sh (โหลดสำเร็จรูป)"
    echo "2. หรือโหลด manual จาก: https://huggingface.co/Qwen/Qwen3-VL-4B-Thinking"
    echo ""
fi

# ตรวจสอบ dependencies
echo "🔍 ตรวจสอบ dependencies..."

# Check flutter
if command -v flutter &> /dev/null; then
    FLUTTER_VERSION=$(flutter --version | head -1)
    echo "✅ Flutter: $FLUTTER_VERSION"
else
    echo "❌ ไม่พบ Flutter"
fi

# Check Dart
if command -v dart &> /dev/null; then
    DART_VERSION=$(dart --version)
    echo "✅ Dart: $DART_VERSION"
fi

echo ""
echo "🚀 พร้อมเริ่ม develop แล้ว!"
echo ""
echo "ขั้นตอนต่อไป:"
echo "1. flutter pub get"
echo "2. โหลดโมเดล (ถ้ายังไม่มี)"
echo "3. flutter run"
