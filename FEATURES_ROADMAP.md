# 🚀 Haku Features Roadmap - Proactive AI Assistant

> วางแผนฟีเจอร์ AI ตาม Phase พร้อมโมเดลที่ใช้

---

## ✅ Phase 1: MVP (เสร็จแล้ว)
พื้นฐานที่ต้องมีก่อน AI จะทำงานได้
- ✅ SQLite + SQLCipher Encryption
- ✅ Biometric Lock
- ✅ Basic Chat UI (Mock)
- ✅ Android Widgets

---

## 🔬 Phase 2: AI & Intelligence (Proactive Features)
**เป้าหมาย:** เปลี่ยนจาก "App" เป็น "Assistant" ที่ช่วยจัดการชีวิต

### 2.1 Smart Search / RAG 🔍
**ความสามารถ:** ค้นหาบันทึกจากความหมาย ไม่ใช่แค่ keyword

**Technical:**
- Vector DB: `sqlite-vec`
- Embedding: `multilingual-e5-small` (~100MB)
- LLM สำหรับสรุป: `Qwen 2.5 3B Q4` หรือ `Phi-4 Mini Q4`

**ตัวอย่าง:**
- "วันไหนที่ฉันมีความสุขที่สุด?" → หา mood=5
- "ฉันไปเที่ยวทะเลเมื่อไหร่?" → หาจาก location + context

**Complexity:** 🟢 ง่าย (มี library พร้อม)

---

### 2.2 Entry Summarization 📝
**ความสามารถ:** สรุปบันทึกยาว ๆ ให้สั้นลง

**Technical:**
- LLM: `Qwen 2.5 3B Instruct Q4` (~1.8GB) - ดีสุดสำหรับไทย
- หรือ `Phi-4 Mini Q4` (~2.2GB) - ฉลาดสุด แต่ไทยพอใช้

**ตัวอย่าง:**
- บันทึก 500 คำ → สรุปเป็น 3 ประโยค
- สรุป "วันนี้" จากหลาย ๆ entry

**Complexity:** 🟢 ง่าย (ใช้ LLM prompt เลย)

---

### 2.3 AI Book Calendar (Auto-Scheduling) 📅 ⭐
**ความสามารถ:** คุยกับ Haku แล้วให้ลงตารางงานใน Calendar เครื่องอัตโนมัติ

**Flow:**
1. User: "วันศุกร์หน้าต้องไปหาหมอฟันตอนบ่ายสอง"
2. AI Extraction (LLM) → JSON:
```json
{
  "intent": "create_event",
  "title": "หาหมอฟัน",
  "date": "2026-02-06",
  "time": "14:00",
  "duration_minutes": 60
}
```
3. System API: เขียนลง Calendar (Android Calendar API / iOS EventKit)
4. UI: Pop-up Confirm ก่อนเขียนจริง

**Technical:**
- LLM: `Qwen 2.5 3B` (เข้าใจไทยดี)
- Intent Classification: บนเครื่อง (Lightweight)
- Calendar API: Native Android/iOS

**Complexity:** 🟡 ปานกลาง (ต้อง integrate กับ OS)

**Model ที่ใช้:**
```yaml
# สำหรับดึง intent + entities
llm_main: Qwen2.5-3B-Instruct-Q4_K_M.gguf (~1.8GB)

# สำหรับ NER (Named Entity Recognition) ถ้าต้องการแยกโมเดล
# อาจใช้ WangchanBERTa ขนาดเล็ก (~100MB) แยก
```

---

### 2.4 Proactive Voice Alert 🗣️ ⭐
**ความสามารถ:** AI พูดเตือนเมื่อใกล้ถึงเวลา (ไม่ต้องเปิดแอป)

**Scenario:**
- 15 นาทีก่อนนัด → Haku พูด: "อีก 15 นาทีมีนัดหมอฟัน รถเริ่มติดแล้วควรออกเลย"

**Technical:**

**Android:**
- Foreground Service + Text-to-Speech (TTS)
- ใช้ Google TTS (มีบนเครื่องทุกเครื่องอยู่แล้ว)
- หรือ Piper TTS (On-device, ไม่ต้อง Cloud)

**iOS:**
- Rich Notification + Siri Announce
- จำกัด: ไม่สามารถพูดเองโดยไม่มีการกระทำจาก user

**Complexity:** 🟡 ปานกลาง (ต้องจัดการ Battery + Permission)

**Model ที่ใช้:**
```yaml
# TTS (Text-to-Speech)
tts_engine: 
  - android: Google TTS (pre-installed) หรือ Piper-TTS (~50MB)
  - ios: Siri Announce Notifications

# LLM สำหรับสร้างข้อความเตือน:
llm: Qwen2.5-3B-Instruct-Q4_K_M.gguf
```

**Note:** ใช้ LLM สร้างข้อความเตือนแบบ personalized (ไม่ใช่แค่ "ถึงเวลานัด") แต่เป็น "รถติดแล้วนะ ควรออกเลย"

---

## 🧪 Phase 3: Beta Testing (Insights & Analytics)
**เป้าหมาย:** วิเคราะห์ pattern ชีวิตและให้ insights

### 3.1 The Hidden Correlation 🔮 ⭐⭐
**ความสามารถ:** หาความเชื่อมโยงที่ซ่อนอยู่ในชีวิต (เหมือนนักสืบ)

**Wow Moment:**
> "คุณรู้ไหม? 80% ของวันที่คุณปวดหัวไมเกรน คือวันที่คุณดื่มกาแฟร้าน A และนอนน้อยกว่า 6 ชม. ...วันนี้เลี่ยงร้าน A ดีไหม?"

**Technical:**
- Correlation Analysis (สถิติพื้นฐาน ไม่ต้องใช้ AI หนัก)
- Pattern Matching: [Food] + [Sleep] + [Mood] + [Health]
- ใช้ Python (via Chaquopy บน Android) หรือ Dart native

**Model ที่ใช้:**
```yaml
# ไม่ต้องใช้ LLM ใหญ่ ใช้สถิติ + ML เบา ๆ
ml_model: 
  - scikit-learn บน device (via chaquopy)
  - หรือ simple rule-based + correlation matrix

# สำหรับ generate insight message:
llm: Qwen2.5-3B (สรุป correlation ให้เป็นภาษาธรรมชาติ)
```

**Complexity:** 🟡 ปานกลาง (ต้องเก็บ data อย่างน้อย 1 เดือนก่อนมี pattern)

---

### 3.2 Social Battery Forecast 🔋
**ความสามารถ:** พยากรณ์ "พลังงานสังคม" และเตือนก่อน burn out

**Wow Moment:**
> กำลังจะกดรับนัดปาร์ตี้ → Haku เตือน: "แบตเตอรี่สังคมเหลือ 15% (สัปดาห์นี้ประชุม 12 ชม. แล้ว) ถ้าไปงานนี้ พรุ่งนี้คุณจะ Burnout แน่นอน"

**Technical:**
- Energy Cost Scoring: ให้ LLM ให้คะแนนแต่ละกิจกรรม
  - ประชุมลูกค้า = -20 Energy
  - กินข้าวเพื่อน = +10 Energy
  - อยู่คนเดียว = +5 Energy (สำหรับ Introvert)
- Calculate cumulative score
- Visual: Health Bar บนหน้า Home

**Model ที่ใช้:**
```yaml
llm: Qwen2.5-3B (ให้คะแนน energy cost ของกิจกรรม)
# หรือใช้ simple classification ถ้าต้องการเร็วขึ้น
```

**Complexity:** 🟡 ปานกลาง

---

### 3.3 Music & News Context (Mood Tracking) 🎵📰
**ความสามารถ:** รู้ว่าคุณฟังเพลงอะไร/อ่านข่าวอะไร เพื่อ context ที่ลึกขึ้น

**Music:**
- Android: Notification Listener → ดึงชื่อเพลงจาก Spotify/YT Music
- iOS: Apple Music API / Spotify API
- บันทึก: [Location: Gym] + [Music: Rock เร็ว] + [Mood: กระปรี้กระเปร่า]

**News (Smart Briefing):**
- RSS Feed จากสำนักข่าวที่เลือก
- LLM สรุป 10 ข่าว → เหลือ 3 ข่าวที่น่าสนใจ
- TTS อ่านตอนเช้า (Morning Routine)

**Model ที่ใช้:**
```yaml
# Music: ไม่ต้องใช้ model ดึงจาก notification ตรง ๆ
# News Summarization:
llm: Qwen2.5-3B (สรุปข่าว)
# หรือใช้ seq2seq ขนาดเล็ก (~200MB) ถ้าต้องการเร็ว
```

**Complexity:** 🟢 ง่าย ( mostly data fetching + summarization)

---

## 🎖️ Phase 4: Production (Advanced Personalization)
**เป้าหมาย:** AI ที่เข้าใจคุณในระดับลึก

### 4.1 Shadow Mode (AI Writing Style) 👤
**ความสามารถ:** AI เรียนรู้สไตล์การเขียนของคุณ และ Draft คำตอบให้เหมือนคุณพิมพ์เอง

**Wow Moment:**
> มีคนทัก Line มาเรื่องงานยาวเหยียด → กดปุ่ม Haku → AI ร่างคำตอบ 3 ย่อหน้า โดยใช้ "คำติดปาก" ของคุณ, สไตล์การเว้นวรรค, Emoji ที่ชอบใช้

**Technical:**
- Fine-tune small LLM บน device (LoRA) ด้วยข้อความของ user
- หรือใช้ Few-shot prompting (ให้ตัวอย่างข้อความเก่า ๆ ใน prompt)
- Privacy: ย้ำว่า train บนเครื่องนี้เท่านั้น

**Model ที่ใช้:**
```yaml
# วิธีที่ 1: LoRA Fine-tuning (ยาก แต่ดีสุด)
base_model: Gemma-2-2B (เล็กพอที่จะ fine-tune บนมือถือได้)
lora_adapter: ~100MB (เทรนเองบนเครื่อง)

# วิธีที่ 2: Few-shot Prompting (ง่ายกว่า)
llm: Qwen2.5-3B
context: เอาข้อความเก่าของ user 5-10 ข้อความใส่เป็น example
```

**Complexity:** 🔴 ยาก (ต้อง fine-tune หรือ context window ใหญ่)

---

### 4.2 AR Memory Anchor (Future Concept)
**ความสามารถ:** ชี้กล้องไปที่สถานที่ → Haku บอกว่าเคยมีความทรงจำอะไรที่นี่

**Status:** 🔴 ยังไม่แน่ใจ technical feasibility บน Flutter + On-device

**อาจเลื่อนไป Phase 5 หรือทำเป็น Prototype only**

---

## 📊 สรุปโมเดลที่ต้องใช้ทั้งหมด

```yaml
# Core LLM (ใช้ทุกฟีเจอร์)
primary_llm:
  model: Qwen2.5-3B-Instruct-Q4_K_M.gguf
  size: ~1.8 GB
  reason: ดีสุดสำหรับภาษาไทย รองรับ Multilingual
  alternative: Phi-4-Mini-Q4_K_M.gguf (~2.2GB, ฉลาดกว่าแต่ไทยอ่อน)

# Embedding (สำหรับ RAG)
embedding_model:
  model: multilingual-e5-small
  size: ~100 MB
  format: ONNX

# TTS (Text-to-Speech)
tts_engine:
  android: 
    - Google TTS (pre-installed) - ฟรี แต่ต้องออนไลน์บางครั้ง
    - Piper-TTS (~50MB) - ฟรี On-device 100%
  ios:
    - Siri Announce Notifications

# STT (Speech-to-Text) - Optional Phase 2
stt_engine:
  on_device:
    model: Whisper-Tiny (~75MB)
    quality: พอใช้สำหรับอังกฤษ ไทยไม่แม่น
  cloud_fallback:
    service: Google Speech-to-Text API
    note: ต้องขอ permission user ก่อนใช้

# สำหรับ Phase 3 (Correlation/Social Battery)
# ไม่ต้องใช้โมเดลใหม่ ใช้สถิติ + LLM ที่มีอยู่

# สำหรับ Phase 4 (Shadow Mode)
lora_finetune:
  base: Gemma-2-2B
  adapter_size: ~100MB
  training: On-device (ต้องมีข้อความ user อย่างน้อย 100 ข้อความ)
```

---

## 🎯 สรุป Recommendation

### ถ้าเริ่ม Phase 2 ตอนนี้:
1. **โหลดโมเดลหลักก่อน:** `Qwen2.5-3B-Instruct-Q4_K_M.gguf` (~1.8GB)
2. **ทำ RAG ก่อน:** ง่ายสุด มี impact สูง (ค้นหาบันทึกเก่า)
3. **ทำ Auto-Scheduling ต่อ:** ผู้ใช้จะรู้สึก "ว้าว" ทันที
4. **Proactive Voice ทำคู่กัน:** ใช้ TTS ฟรีที่มีใน Android ก่อน

### งบประมาณพื้นที่:
- App ตอน Phase 1: ~30MB
- + LLM (Qwen): ~1.8GB
- + Embedding: ~100MB
- **รวม:** ~2GB (รับได้สำหรับมือถือยุค 2024-2026)

### งบประมาณ RAM:
- Qwen 3B Q4 ใช้ RAM ~3-4GB เวลาทำงาน
- มือถือ RAM 6GB+ รับได้สบาย
- มือถือ RAM 4GB อาจช้า/ติดบ้าง

---

**ต้องการให้เริ่ม implement ฟีเจอร์ไหนก่อนครับ?** 🎌
