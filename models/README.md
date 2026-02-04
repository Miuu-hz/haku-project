# Models Directory

โฟลเดอร์สำหรับเก็บไฟล์โมเดล AI (ไม่ถูก push ขึ้น git)

## ไฟล์ที่รองรับ

- `.task` - MediaPipe GenAI / LiteRT models (Gemma, Qwen, etc.)
- `.gguf` - GGUF format (สำหรับ llama.cpp)
- `.tflite` - TensorFlow Lite models
- `.onnx` - ONNX models

## วิธีใช้งาน

1. ดาวน์โหลดโมเดลจาก [Kaggle Models](https://www.kaggle.com/models) หรือ [Hugging Face](https://huggingface.co)
2. วางไฟล์ `.task` ในโฟลเดอร์นี้
3. เปิดแอพ → ไปที่ Settings → เลือกไฟล์โมเดล

## โมเดลที่แนะนำ

| โมเดล | ขนาด | ใช้งาน |
|-------|------|--------|
| `gemma-3-270m-it-int8.task` | ~270 MB | เร็ว ประหยัดแบต |
| `gemma-3-4b-it-int8.task` | ~4 GB | คุณภาพสูง |

> ⚠️ ไฟล์โมเดลขนาดใหญ่จะไม่ถูก push ขึ้น git (ดู `.gitignore`)
