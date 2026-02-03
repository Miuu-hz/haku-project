#!/bin/bash

# 🔄 Script Convert PyTorch → GGUF (ถ้าไม่มีไฟล์สำเร็จรูป)
# ต้องติดตั้ง llama.cpp ก่อน

echo "🔄 Convert Qwen3-VL-4B-Thinking เป็น GGUF"
echo ""

# ตรวจสอบ llama.cpp
if ! command -v convert_hf_to_gguf.py &> /dev/null; then
    echo "❌ ไม่พบ convert_hf_to_gguf.py"
    echo ""
    echo "📥 กรุณาติดตั้ง llama.cpp ก่อน:"
    echo "   git clone https://github.com/ggerganov/llama.cpp"
    echo "   cd llama.cpp"
    echo "   pip install -r requirements.txt"
    exit 1
fi

MODEL_NAME="Qwen3-VL-4B-Thinking"
HF_REPO="Qwen/$MODEL_NAME"
OUTPUT_DIR="assets/models"

mkdir -p "$OUTPUT_DIR"

echo "📥 1. กำลังโหลดโมเดลจาก Hugging Face..."
huggingface-cli download "$HF_REPO" --local-dir "./tmp_$MODEL_NAME"

echo ""
echo "🔄 2. กำลัง convert เป็น GGUF..."

# Convert หลาย quantization level
for QUANT in Q4_K_M Q5_K_M Q6_K; do
    echo "   - สร้าง $QUANT..."
    convert_hf_to_gguf.py \
        "./tmp_$MODEL_NAME" \
        --outfile "$OUTPUT_DIR/qwen3-vl-4b-thinking-${QUANT,,}.gguf" \
        --outtype "$QUANT" || echo "     ⚠️  ข้าม $QUANT"
done

echo ""
echo "🧹 3. ลบไฟล์ชั่วคราว..."
rm -rf "./tmp_$MODEL_NAME"

echo ""
echo "✅ เสร็จแล้ว!"
echo "📁 ไฟล์อยู่ใน: $OUTPUT_DIR/"
ls -lh "$OUTPUT_DIR/"

# แนะนำ quantization
echo ""
echo "💡 แนะนำ:"
echo "   - Q4_K_M: เร็วสุด (~2.5GB) - เหมาะกับมือถือ RAM 6GB"
echo "   - Q5_K_M: สมดุล (~3GB) - แนะนำสำหรับ RAM 8GB"
echo "   - Q6_K: คุณภาพสูง (~3.5GB) - ถ้ามือถือแรงพอ"
