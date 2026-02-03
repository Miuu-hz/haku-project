#!/bin/bash

# 📥 Script โหลด Qwen3-VL-4B-Thinking สำหรับ Haku
# รองรับ: macOS, Linux, Windows (via Git Bash)

set -e

MODEL_DIR="assets/models"
mkdir -p "$MODEL_DIR"

echo "🎌 กำลังโหลด Qwen3-VL-4B-Thinking..."
echo ""

# ตัวเลือกที่ 1: bartowski (แนะนำ - มี GGUF หลายเวอร์ชัน)
echo "🔍 ตรวจสอบแหล่งโหลด..."

# ลองโหลดจาก bartowski ก่อน (ถ้ามี)
BARTOWSKI_URL="https://huggingface.co/bartowski/Qwen3-VL-4B-Thinking-GGUF"

echo "📥 กำลังโหลดจาก bartowski..."
echo "URL: $BARTOWSKI_URL"

# โหลดไฟล์ GGUF (Q4_K_M = ความเร็ว/คุณภาพ balance ดี)
curl -L --progress-bar \
  "https://huggingface.co/bartowski/Qwen3-VL-4B-Thinking-GGUF/resolve/main/Qwen3-VL-4B-Thinking-Q4_K_M.gguf" \
  -o "$MODEL_DIR/qwen3-vl-4b-thinking-q4.gguf" || {
    echo "❌ ไม่พบไฟล์จาก bartowski"
    echo "🔄 ลองแหล่งอื่น..."
  }

# ถ้า bartowski ไม่มี ลอง lmstudio-community
if [ ! -f "$MODEL_DIR/qwen3-vl-4b-thinking-q4.gguf" ]; then
  echo "📥 ลองโหลดจาก lmstudio-community..."
  curl -L --progress-bar \
    "https://huggingface.co/lmstudio-community/Qwen3-VL-4B-Thinking-GGUF/resolve/main/Qwen3-VL-4B-Thinking-Q4_K_M.gguf" \
    -o "$MODEL_DIR/qwen3-vl-4b-thinking-q4.gguf" || {
      echo "❌ ไม่พบไฟล์ GGUF สำเร็จรูป"
      echo ""
      echo "⚠️  ต้อง convert จาก PyTorch เอง (ดูคำสั่งด้านล่าง)"
      exit 1
    }
fi

echo ""
echo "✅ โหลดเสร็จแล้ว!"
echo "📁 ไฟล์อยู่ที่: $MODEL_DIR/qwen3-vl-4b-thinking-q4.gguf"
echo ""

# ตรวจสอบขนาดไฟล์
if command -v du &> /dev/null; then
  SIZE=$(du -h "$MODEL_DIR/qwen3-vl-4b-thinking-q4.gguf" | cut -f1)
  echo "📊 ขนาดไฟล์: $SIZE"
fi

echo ""
echo "📝 ขั้นตอนต่อไป:"
echo "1. ตรวจสอบว่าไฟล์โหลดครบ (ควรมีขนาด ~2.5-3GB)"
echo "2. รัน: flutter pub get"
echo "3. เริ่ม integrate ใน lib/services/llm_service.dart"
echo ""
echo "🔧 ถ้าโหลดไม่สำเร็จ ให้โหลด manual จาก:"
echo "   https://huggingface.co/Qwen/Qwen3-VL-4B-Thinking"
echo "   แล้ว convert เป็น GGUF ด้วย llama.cpp"
