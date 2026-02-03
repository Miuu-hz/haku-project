# 🎌 Scripts สำหรับ Haku LLM Setup

## วิธีโหลด Qwen3-VL-4B-Thinking

### วิธีที่ 1: โหลดสำเร็จรูป (แนะนำ)
```bash
# รัน script นี้
./scripts/download_qwen3.sh
```

Script จะลองโหลดจากแหล่งต่าง ๆ:
- bartowski (แนะนำ)
- lmstudio-community

### วิธีที่ 2: โหลด Manual
```bash
# 1. ไปที่ Hugging Face
open https://huggingface.co/Qwen/Qwen3-VL-4B-Thinking

# 2. หาไฟล์ GGUF (ถ้ามีคน convert ไว้)
# หรือโหลด PyTorch แล้ว convert เอง
```

### วิธีที่ 3: Convert เอง (ถ้าไม่มี GGUF)
```bash
# ติดตั้ง llama.cpp ก่อน
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp
pip install -r requirements.txt

# รัน convert
./scripts/convert_to_gguf.sh
```

## 📁 โครงสร้างไฟล์ที่ควรมี

```
assets/models/
├── qwen3-vl-4b-thinking-q4.gguf    # ไฟล์หลัก (~2.5-3GB)
└── (optional) embedding model
```

## 🔧 ถ้าโหลดไม่ได้

อาจเป็นเพราะ:
1. ยังไม่มีคน convert Qwen3-VL เป็น GGUF (เพิ่ง release ใหม่)
2. ต้องรอ community สัก 1-2 สัปดาห์

**ทางเลือก:**
- ใช้ `Qwen2.5-3B-Instruct` ก่อน (มี GGUF พร้อมใช้แน่นอน)
- หรือรอแล้วค่อย upgrade

## 📊 Quantization Levels

| Level | ขนาด | ความเร็ว | คุณภาพ | เหมาะกับ |
|-------|------|----------|--------|----------|
| Q4_K_M | ~2.5GB | เร็วสุด | ดี | RAM 6GB |
| Q5_K_M | ~3GB | เร็ว | ดีมาก | RAM 8GB |
| Q6_K | ~3.5GB | ปานกลาง | ดีที่สุด | RAM 12GB+ |

## 🚀 หลังโหลดเสร็จ

```bash
# ตรวจสอบขนาดไฟล์
ls -lh assets/models/

# รันแอพ
flutter run
```
