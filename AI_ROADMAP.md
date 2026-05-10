# 🤖 Haku AI Roadmap

> อัพเดทล่าสุด: 2026-05-11
> สถาปัตยกรรมจริงที่ใช้อยู่ปัจจุบัน + แผนต่อไป

---

## ✅ Architecture ที่ Implement แล้ว

### 🧠 On-Device LLM — LiteRT-LM

| ส่วน | รายละเอียด |
|------|------------|
| **Models** | Gemma 3 1B (`.litertlm`) / Gemma 4 E2B (`.litertlm`) / Gemma 4 E4B (`.litertlm`) |
| **Context window** | Gemma 3: ~1K tokens · Gemma 4 E2B: 4K · Gemma 4 E4B: 8K |
| **Runtime** | LiteRT-LM (Google, แทน MediaPipe ที่ deprecated) |
| **Bridge** | `LiteRTLMBridge.kt` → MethodChannel `com.example.haku/llm` |
| **Dart side** | `LLMService` → `LiteRTLLMProvider` → `LLMProviderManager` |
| **Conversation** | Stateful — `Conversation` มีชีวิตข้าม request (KV cache) |
| **Auto-detect** | `LLMModelConfig.detect(filename)` — รู้ config จากชื่อไฟล์อัตโนมัติ |
| **Model gallery** | Settings screen: ดาวน์โหลด 3 โมเดลจาก HuggingFace พร้อม progress bar |

MethodChannel ที่รองรับ:
```
loadModel(modelPath, maxTokens, systemInstruction?) → bool
generate(prompt)                                    → String  [stateless, one-shot]
generateTurn(prompt)                                → String  [stateful, KV cache]
resetConversation()                                 → null
setSystemInstruction(instruction?)                  → null
unloadModel()                                       → null
isModelLoaded()                                     → bool
getModelInfo()                                      → Map
```

### ☁️ Cloud Providers (fallback / dev mode)

| Provider | Model | Key format |
|----------|-------|------------|
| Gemini | Flash (Google) | `AIza...` |
| Claude | Haiku (Anthropic) | `sk-ant-...` |
| OpenAI | GPT-4o-mini | `sk-...` |
| OpenRouter | `google/gemini-2.0-flash-001` (ปรับได้) | `sk-or-v1-...` |

Provider switching: `LLMProviderManager` + SharedPreferences → Settings Screen

---

### 🏗️ Chat Flow (ปัจจุบัน)

```
User พิมพ์
  │
  ▼
0. QuickAction (rule-based, 0 LLM) — greetings, quick summaries
  │
  ▼
1. SmartPreprocessor workers (rule-based, 0 LLM)
   └─ CalendarWorker / ReminderWorker / WebSearchWorker
   └─ ถ้า match → dispatch ทันที (PATH A)
  │
  ▼ (ถ้าไม่ match → PATH B: general message)
  │
1.5 TagContextService (0 LLM) — keyword search past entries
1.6 Calendar Context (0 LLM) — inject ถ้าเป็น schedule query
  │
  ▼
2. Face LLM
   ├─ Cloud: generate(fullPrompt) — stateless
   └─ On-device: generateTurn(userTurn) — stateful KV cache
       system instruction ตั้งครั้งเดียวต่อ session
  │
  └─ [async] SecretChatService.logExchange()
       │
       ▼
       LLM extract → EnglishLogEntry {summaryEn, intent, tags, location, mood}
       │
       ├─ persist → SharedPreferences (50 entries)
       │
       └─ ManagerDispatchService.dispatchFromLog()
            ├─ intent=schedule → SchedulerService → Android Calendar
            ├─ intent=log      → WorkerService → UserProfile + RAG
            ├─ intent=query    → WebSearchService
            └─ intent=chat     → log only
```

**สิ่งที่ถูกลบออก (เทียบกับ roadmap เก่า)**:
- ~~PreClassify LLM call~~ → ลบออก (Gemma 4 เข้าใจ intent เองได้)
- ~~LeanContextService~~ → ลบออก (context window ใหญ่พอแล้ว)
- ~~TfliteLLMService~~ → ลบออก (ไม่ทำงานกับ Gemma ได้จริง)
- ~~MediaPipeLLMBridge~~ → แทนที่ด้วย LiteRTLMBridge

---

### 📝 Prompt System

ทุก prompt อยู่ใน `lib/services/prompt_builder.dart`

| Method | หน้าที่ |
|--------|---------|
| `hakuFacePrompt` | Face LLM system prompt (language-agnostic) |
| `buildSystemInstruction()` | System instruction สำหรับ Stateful LiteRT session |
| `buildUserTurn(msg, context?)` | User turn สำหรับ Stateful conversation (ไม่มี history ใน string) |
| `buildGemmaPrompt(msg, context?)` | Full prompt สำหรับ Stateless/legacy calls |
| `buildCloudPrompt(msg, context?)` | Cloud LLM full prompt |
| `buildWorkerExtractPrompt` | Secret Chat → EnglishLogEntry JSON |
| `buildSchedulerPrompt` | Thai text → EventInfo JSON |
| `buildManagerPrompt` | Big Manager intent classification |
| `hakuManagerPrompt` | Manager system prompt constant |

---

### 🔍 Vector Search / RAG

| ส่วน | รายละเอียด |
|------|------------|
| **Embedding** | Hash-based TF-IDF (2000-dim) — ไม่ใช้ embedding model จริง |
| **Storage** | `haku_hybrid_vectors.db` (SQLite BLOB via sqflite) |
| **Search** | BM25 + cosine hybrid (`hybrid_vector_search.dart`) |
| **Fast Path** | SQL LIKE search ก่อน (0 LLM) |
| **TagContextService** | Keyword search past entries → inject เป็น context ก่อน Face LLM |
| **UnifiedVectorService** | In-memory + SharedPreferences สำหรับ health/fact data |

---

### 👷 Workers

| Worker | ประเภท | หน้าที่ |
|--------|--------|---------|
| `CalendarWorker` | Rule-based | detect นัดหมาย, date/time parsing |
| `FactWorker` | Rule-based | ชื่อ, งาน, ชอบ/ไม่ชอบ → User Profile |
| `GoalWorker` | Rule-based | เป้าหมาย, ความตั้งใจ |
| `HealthDoctor` | Rule-based | ยา, อาการ, period, โรค |
| `ReminderWorker` | Rule-based | คำขอแจ้งเตือน |
| `WorkerService._handleHealthAnalysis()` | Pattern-match | scan SecretChat log → addFact() ใน UnifiedVectorService |
| `WorkerService._extractFactsWithLLM()` | LLM (batch) | JSON extract → PendingFact queue → UserProfileService |

---

### 🔋 Charging-time Tasks

เมื่อ device ชาร์จ → `ChargingTrigger` fire → `ManagerSummaryStrategy`:
1. `_analyzeHealth()` — อ่าน `vectorService.getByCategory('health_log')` → วิเคราะห์ pattern
2. `_extractFactsWithLLM()` — สรุป recent chat log → extract user facts
3. Manager summary report → แสดงให้ user เห็นเป็น proactive message

---

### 📅 Calendar / Scheduling

```
SchedulerService.createCalendarEvent()
  └─ Thai text → EventInfo JSON (via LLM)
  └─ MethodChannel('com.example.haku/scheduler') → MainActivity.kt
       └─ SchedulerBridge.kt → CalendarContract → Android Calendar
       └─ addReminder() → 15 นาทีก่อนนัด
```

---

### 🔍 Web Search

- **Provider**: DuckDuckGo HTML scraping (ไม่ต้อง API key)
- **Fallback**: Google HTML scraping
- **Cache**: 6 ชั่วโมง, rate limit 2s ระหว่าง requests
- **Output**: 5 results → Face LLM follow-up generation

---

### 📱 Components อื่นๆ

| ส่วน | สถานะ |
|------|--------|
| **Database** | SQLite (`haku_encrypted.db`) + SQLCipher — ตาราง `entries` |
| **Android Widget** | ✅ Home screen widget 4x2 / 4x3 |
| **Settings Screen** | ✅ LLM provider + API key + model gallery (HuggingFace download) |
| **Context Builder** | ✅ `[Day HH:MM\|📍Zone\|🔋80%]` status bar |
| **Geofence / Place Learning** | ✅ DwellTracker + PlaceFeedbackService |
| **STT** | ❌ ยังไม่มี |
| **Google Calendar Sync** | ✅ GoogleAuthService (Demo Mode toggle) |

---

## 🗺️ Feature Roadmap

### Feature 3 — ผู้ช่วยจัดตารางอัจฉริยะ 🟡 ~65% done

| Sub-feature | สถานะ | หมายเหตุ |
|-------------|--------|---------|
| Natural language → schedule intent | ✅ | CalendarWorker regex + SecretChat |
| สร้าง event ใน Android Calendar | ✅ | SchedulerService |
| Reminder 15 นาทีก่อน | ✅ | SchedulerBridge.addReminder |
| อ่าน calendar slot ว่าง | ❌ | ต้องเพิ่ม `getEvents()` ก่อน create |
| Calendar context inject ใน chat | ✅ | `_isScheduleQuery()` + `_buildCalendarContext()` |
| Time block อัตโนมัติ | ❌ | จัด slot ว่างในวัน |
| Task conflict detection | ❌ | warn ถ้าชนกัน |

---

### Feature 1 — ผู้ช่วยวางแผนวันทำงาน 🟡 ~50% done

| Sub-feature | สถานะ | หมายเหตุ |
|-------------|--------|---------|
| ช่วยวางแผนวัน | ✅ | ผ่าน Feature 3 |
| เตือนงานสำคัญ | ✅ | scheduleReminder |
| จัดลำดับ priority | ✅ | GoalWorker |
| Morning check-in | ❌ | ต้องใช้ WorkManager trigger |
| Evening summary | ❌ | ต้องใช้ WorkManager trigger |

---

### Feature 2 — บอทช่วยเลิกผัดวันประกันพรุ่ง ❌ ~0% done

| Sub-feature | สิ่งที่ต้องสร้าง |
|-------------|----------------|
| Focus timer (Pomodoro) | FocusTimerService + UI widget |
| Deep Work session | Session state + notification |
| Break reminder | ScheduledNotification |
| Streak system | StreakService + persist |

---

**ลำดับแนะนำ: 3 → 1 → 2**

- **3**: เพิ่ม `getEvents()` อ่าน calendar ก่อน create — conflict detection
- **1**: WorkManager job สำหรับ morning/evening trigger
- **2**: FocusTimerService + StreakService ใหม่ทั้งหมด

---

## ❓ สิ่งที่ยังไม่มี (พิจารณาอนาคต)

| Feature | ความยาก | หมายเหตุ |
|---------|---------|---------|
| STT ภาษาไทย | กลาง | Cloud (Google Speech) หรือ Whisper on-device |
| Real Embedding Model | สูง | multilingual-e5 ~100MB — improve RAG แต่เพิ่ม RAM |
| Image Caption | สูง | ต้องการ vision model on-device |
| Voice Conversation | สูง | ต้องการ model >3B — แบตหมดเร็ว |
| True Streaming (token-by-token) | กลาง | `generateStream()` ใน LiteRTLMBridge พร้อมแล้ว ต้องเชื่อม Dart side |
