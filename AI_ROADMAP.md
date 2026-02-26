# 🤖 Haku AI Roadmap

> อัพเดทล่าสุด: 2026-02-26
> สถาปัตยกรรมจริงที่ใช้อยู่ปัจจุบัน + แผนต่อไป

---

## ✅ Architecture ที่ Implement แล้ว

### 🧠 On-Device LLM

| ส่วน | รายละเอียด |
|------|------------|
| **Model** | Gemma 3 1B (`.task` format, LiteRT) |
| **Runtime** | MediaPipe Tasks GenAI (Google AAR) |
| **Bridge** | `MediaPipeLLMBridge.kt` → MethodChannel `com.example.haku/llm` |
| **Dart side** | `mediapipe_llm_provider.dart` → `LLMProviderManager` |
| **llama.cpp / Vulkan** | ❌ ลบออกแล้ว (`llm_native_bridge.dart` เหลือแต่ stub deprecated) |

### ☁️ Cloud Providers (fallback / dev mode)

| Provider | Model | Key format |
|----------|-------|------------|
| Gemini | Flash (Google) | `AIza...` |
| Claude | Haiku (Anthropic) | `sk-ant-...` |
| OpenAI | GPT-4o-mini | `sk-...` |
| **OpenRouter** 🆕 | ปรับได้ (default: `google/gemini-2.0-flash-001`) | `sk-or-v1-...` |

Provider switching: `LLMProviderManager` + บันทึกใน SharedPreferences
ตั้งค่าได้จาก Settings Screen (`settings_screen.dart`)

---

### 🏗️ Secret Chat Architecture (Core)

```
User พิมพ์ภาษาไทย
  │
  ▼
Face LLM (Gemma 3 1B / Cloud)
  └─ ตอบ user เป็นภาษาไทย  [Stage 1 — ต่อหน้า]
  │
  └─ [async, ไม่ block UI] SecretChatService.logExchange()
       │
       ▼
       LLM extract → EnglishLogEntry {
         summaryEn, intent, tags, location, mood
       }
       │
       ├─ persist → SharedPreferences (50 entries)
       │
       └─ ManagerDispatchService.dispatchFromLog()
            │
            ├─ intent=schedule → SchedulerService → Android Calendar API
            ├─ intent=log      → FactWorker → User Profile + RAG
            ├─ intent=query    → WebSearchService (DuckDuckGo)
            └─ intent=chat     → log only, no action
```

**Status**: ✅ DONE — CLI tested 6/6 intent accuracy

---

### 📝 Prompt System

ทุก prompt อยู่ใน `lib/services/prompt_builder.dart` — ใช้ Gemma turn format สำหรับ on-device, ตัด tags อัตโนมัติเมื่อส่ง Cloud

| Method | หน้าที่ |
|--------|---------|
| `hakuFacePrompt` | Face LLM system prompt (Thai chat) |
| `buildWorkerExtractPrompt` | Secret Chat → EnglishLogEntry JSON |
| `buildSchedulerPrompt` | Thai text → EventInfo JSON (date/time parsing) |
| `buildTranslateEntryPrompt` | Thai diary → English (สำหรับ RAG) |
| `buildWorkerSummarizePrompt` | สรุป chat session |
| `buildWorkerFacePrompt` | Face prompt + context injection |

---

### 🔍 Vector Search / RAG

| ส่วน | รายละเอียด |
|------|------------|
| **Embedding** | Hash-based TF-IDF (ไม่ใช้ embedding model จริง) — 2000-dim |
| **Storage** | `haku_hybrid_vectors.db` (SQLite BLOB via sqflite) |
| **Search** | BM25 + cosine hybrid (`hybrid_vector_search.dart`) |
| **Fast Path** | SQL LIKE search ก่อน ถ้า user ถามเรื่องอดีต (0 LLM calls) |
| **Context assembly** | `smart_preprocessor.dart` รวม lean context ก่อนส่ง Face LLM |

> หมายเหตุ: ไม่มี embedding model จริง (multilingual-e5 ฯลฯ) — ใช้ hash แทนเพื่อประหยัด RAM

---

### 👷 Workers (Rule-based, 0 LLM cost)

Workers ทุกตัวทำงานแบบ rule-based regex — ไม่เรียก LLM เพิ่ม

| Worker | ตรวจจับ | Output format |
|--------|---------|---------------|
| `fact_worker.dart` | ชื่อ, งาน, ชอบ/ไม่ชอบ, สถานที่ | User profile + RAG |
| `calendar_worker.dart` | นัดหมาย, ประชุม, กิจกรรม (regex) | SharedPreferences |
| `goal_worker.dart` | เป้าหมาย, ความตั้งใจ | `[Goal:ออกกำลัง,0/3d/w]` |
| `health_doctor.dart` | ยา, อาการ, period, โรค | `[Health:...]` |
| `reminder_worker.dart` | คำขอแจ้งเตือน | SharedPreferences |
| `translator_worker.dart` | Thai diary → English (batch, background) | RAG vector DB |

---

### 📅 Calendar / Scheduling

```
SchedulerService.createCalendarEvent()
  └─ แปลง date(String) + time(String) → Long milliseconds  ← fixed (ก่อนหน้า bug)
  └─ MethodChannel('com.example.haku/scheduler') → MainActivity.kt
       └─ SchedulerBridge.kt → CalendarContract → Android Calendar จริง
       └─ addReminder() → 15 นาทีก่อนนัด
```

Permission: `WRITE_CALENDAR` (popup ครั้งแรก)

---

### 🔍 Web Search

- **Provider**: DuckDuckGo HTML scraping (ไม่ต้อง API key)
- **Fallback**: Google HTML scraping
- **Cache**: 6 ชั่วโมง, rate limit 2s ระหว่าง requests
- **Output**: 5 results → format text ส่งให้ Face LLM

---

### 📱 อื่นๆ

| ส่วน | สถานะ |
|------|--------|
| **Database** | SQLite (`haku_encrypted.db`) + SQLCipher encryption — ตาราง `entries` |
| **Android Widget** | ✅ Home screen widget 4x2 / 4x3 (quick action buttons) |
| **Settings Screen** | ✅ เลือก LLM provider + API key + model path |
| **STT (Speech-to-Text)** | ❌ ยังไม่มี |
| **Google Calendar Sync** | ✅ ผ่าน `GoogleAuthService` (Demo Mode toggle) |

---

### 🧪 CLI Test Tool

```bash
dart run bin/test_cli.dart
```

| Command | หน้าที่ |
|---------|---------|
| `/batch` | 6 intent scenarios อัตโนมัติ — ผล: 6/6 ✅ |
| `/schedule <text>` | ทดสอบ date/time parsing → milliseconds |
| `/translate <text>` | ทดสอบ Thai→English สำหรับ RAG |
| *(พิมพ์ปกติ)* | Full flow: Face + SecretChat + Dispatch |

---

## 🗺️ Feature Roadmap

### Feature 3 — ผู้ช่วยจัดตารางอัจฉริยะ 🟡 ~60% done

> "แค่พิมพ์ว่าวันนี้งานเยอะ นัดประชุม 3 โมง"

| Sub-feature | สถานะ | หมายเหตุ |
|-------------|--------|---------|
| Natural language → schedule intent | ✅ | SecretChat + PromptBuilder |
| สร้าง event ใน Android Calendar | ✅ | SchedulerService (fixed) |
| Reminder 15 นาทีก่อน | ✅ | SchedulerBridge.addReminder |
| อ่าน calendar ว่า slot ว่างไหม | ❌ | ต้องเพิ่ม `getEvents()` call ก่อน create |
| Time block อัตโนมัติ | ❌ | จัด slot ว่างในวัน |
| Task conflict detection | ❌ | ถ้าชนกันให้ warn user |

---

### Feature 1 — ผู้ช่วยวางแผนวันทำงาน 🟡 ~50% done

| Sub-feature | สถานะ | หมายเหตุ |
|-------------|--------|---------|
| ช่วยวางแผนวัน (สร้างนัด) | ✅ | ผ่าน Feature 3 |
| เตือนงานสำคัญ | ✅ | scheduleReminder |
| จัดลำดับ priority | ✅ | `goal_worker.dart` มีอยู่ |
| Morning check-in (agenda ตอนเช้า) | ❌ | ต้องใช้ WorkManager (Android background) |
| Evening summary (สรุปวัน) | ❌ | ต้องใช้ WorkManager |

---

### Feature 2 — บอทช่วยเลิกผัดวันประกันพรุ่ง ❌ ~0% done

> ต้องสร้าง infrastructure ใหม่ทั้งหมด

| Sub-feature | สิ่งที่ต้องสร้าง |
|-------------|----------------|
| Focus timer (Pomodoro) | FocusTimerService + UI timer widget |
| Deep Work session | Session state tracking + notification |
| Break reminder | ScheduledNotification ตาม interval |
| Streak system | StreakService: นับ streak, milestone, persist |

---

**ลำดับแนะนำ: 3 → 1 → 2**

- **3**: ต่อยอด pipeline เดิม — เพิ่ม `getEvents()` อ่าน calendar ก่อน create
- **1**: เพิ่ม WorkManager job สำหรับ morning/evening trigger
- **2**: สร้าง FocusTimerService + StreakService ใหม่ทั้งหมด

---

## ❓ สิ่งที่ยังไม่มี (อาจพิจารณาในอนาคต)

| Feature | ความยาก | หมายเหตุ |
|---------|---------|---------|
| STT ภาษาไทย | กลาง | ต้องใช้ Cloud (Google Speech) หรือ Whisper on-device (ไทยพอใช้) |
| Real Embedding Model | สูง | multilingual-e5 ~100MB — อาจ improve RAG แต่เพิ่ม RAM |
| Image Caption | สูง | ต้องการ vision model — ยังไม่มี on-device ที่เบาพอ |
| Voice Conversation | สูง | ต้องใช้ model >3B ถึงจะ smooth — แบตหมดเร็ว |
