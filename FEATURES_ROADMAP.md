# Haku Features Roadmap - Proactive AI Assistant

> วางแผนฟีเจอร์ AI ตาม Phase พร้อมโมเดลที่ใช้
> อัปเดตล่าสุด: 2026-04-11

---

## 🔄 Infrastructure: LiteRT-LM Migration (main branch) — กำลังทำ

> เปลี่ยน on-device runtime จาก MediaPipe (deprecated) → **LiteRT-LM v0.10.0**
> เหตุผล: MediaPipe LLM Inference API ถูก Google deprecate แล้ว, LiteRT-LM คือ successor ที่มี true streaming + function calling built-in + รองรับ Gemma 4

### สิ่งที่ทำ
- [x] ลบ `MediaPipeLLMBridge.kt` (deprecated, reflection-based)
- [x] สร้าง `LiteRTLMBridge.kt` — clean API ไม่มี reflection
- [x] อัพเดท `build.gradle` — swap `mediapipe:tasks-genai` → `litertlm-android:0.10.0`
- [x] อัพเดท `MainActivity.kt` — ใช้ `LiteRTLMBridge` + เพิ่ม `setSystemInstruction` channel
- [ ] ทดสอบ build + รันบน device จริง
- [ ] Download `.litertlm` model format จาก HuggingFace (Gemma 3 1B)

### Key Files
| ไฟล์ | หน้าที่ |
|---|---|
| `android/app/src/main/kotlin/.../LiteRTLMBridge.kt` | Engine + Conversation + true streaming |
| `android/app/build.gradle` | LiteRT-LM + TFLite GPU dependencies |

### Architecture
```
Flutter Dart
  └── MediaPipeLLMService (mediapipe_llm_service.dart)  ← ไม่เปลี่ยน
        └── MethodChannel (com.example.haku/llm)
              └── LiteRTLMBridge.kt  ← ใหม่
                    └── LiteRT-LM Engine (Google)
                          └── GPU/CPU Backend (auto-fallback)
```

### Model Support
```yaml
current:
  model: Gemma 3 1B (.task legacy format ยังใช้ได้)
  format: .task (MediaPipe legacy) หรือ .litertlm (native)
  context: 4096 tokens (เพิ่มขึ้นจาก 2048)

future_gemma4:
  model: Gemma 4 E2B (2-bit ~1.5GB) หรือ E4B (4-bit ~4GB)
  context: 128K tokens
  new_features: Thinking Mode, multimodal (image+audio), function calling native
  migration_path: เพิ่ม systemInstruction ผ่าน setSystemInstruction() — API พร้อมแล้ว
```

---

## 🧠 Future: FunctionGemma 270M as PreClassify Dispatcher (roadmap)

> แทนที่ PreClassify LLM (Gemma 3 1B) ด้วย FunctionGemma 270M ที่เล็กกว่าและ specialized กว่า
> **สถานะ:** วางแผนไว้ — ต้องทำ LiteRT-LM migration เสร็จก่อน

### แนวคิด
```
User Message
  ↓
SmartPreprocessor (rule-based, 0 LLM) — เหมือนเดิม
  ↓ (intent=general)
FunctionGemma 270M (~288 MB)  ← แทน PreClassify ปัจจุบัน
  → function call: log_mood / create_event / search / ...
  → เร็วกว่า (270M vs 1B) + แม่นยำกว่า (specialized for function calling)
  → โหลดค้างไว้ใน RAM ได้ตลอด (เล็กมาก)
  ↓
Gemma 3 1B (Face) — ตอบภาษาไทยธรรมชาติ เหมือนเดิม
```

### ข้อดี
- FunctionGemma 270M = 288 MB เท่านั้น โหลดค้างได้ตลอด ไม่ต้อง unload
- Specialized สำหรับ function calling → แม่นยำกว่า Gemma 3 1B ทำ JSON parsing
- ลด latency: 270M inference เร็วกว่า 1B มาก
- เปิดประตูสู่ Skill System แบบ Gallery (loadSkill/runJs/runIntent)

### งานที่ต้องทำ (อนาคต)
- [ ] Download FunctionGemma 270M `.litertlm` จาก HuggingFace
- [ ] สร้าง `FunctionLLMBridge.kt` — Engine แยกสำหรับ FunctionGemma
- [ ] ย้าย `preClassify()` ใน `secret_chat_service.dart` ไปใช้ FunctionGemma แทน
- [ ] ออกแบบ ToolSet สำหรับ Haku (log_entry, create_event, set_reminder, search_rag, ...)
- [ ] Skill system: SKILL.md format + JavaScript execution

---

## 🦙 Infrastructure: llama.cpp + OpenCL (branch: feat/llama-cpp-opencl)

> เปลี่ยน on-device runtime จาก MediaPipe → llama.cpp + OpenCL (Adreno GPU)
> เหตุผล: รองรับ GGUF โดยตรง, context window ใหญ่กว่า (4096+ vs 2048), GPU เร็วกว่าบน Snapdragon 8 Gen 2

### สิ่งที่ทำ
- [x] สร้าง branch `feat/llama-cpp-opencl`
- [x] ดาวน์โหลด prebuilt `.so` จาก llama.rn v0.11.3 (OpenCL + Adreno + Hexagon NPU)
  - `librnllama_v8_2_dotprod_i8mm_hexagon_opencl.so` — llama.cpp core
  - `libOpenCL.so` — OpenCL ICD loader
  - `libggml-htp-v73.so` — Hexagon HTP (SM8550 = Z Fold 5)
- [x] เขียน `android/app/src/main/cpp/llama_flutter.cpp` — JNI glue layer (C++)
- [x] เขียน `android/app/src/main/cpp/CMakeLists.txt` — native build config
- [x] อัพเดท `android/app/build.gradle` — เพิ่ม externalNativeBuild
- [x] เขียน `LlamaChannel.kt` — Kotlin Platform Channel (loadModel / completion streaming / freeModel)
- [x] เขียน `lib/services/llama_service.dart` — Dart layer แทน MediaPipe service
- [ ] ทดสอบ build + รันบน Z Fold 5

### Key Files
| ไฟล์ | หน้าที่ |
|---|---|
| `android/app/src/main/cpp/llama_flutter.cpp` | JNI wrapper → เรียก llama.cpp C API |
| `android/app/src/main/cpp/CMakeLists.txt` | build config, link กับ prebuilt .so |
| `android/app/src/main/kotlin/.../LlamaChannel.kt` | Flutter ↔ native bridge |
| `lib/services/llama_service.dart` | Dart API (loadModel, completionStream, generate) |

### Architecture
```
Flutter Dart
  └── LlamaService (llama_service.dart)
        └── Platform Channel (com.example.haku/llama)
              └── LlamaChannel.kt (Kotlin)
                    └── llama_flutter.cpp (JNI C++)
                          └── librnllama_*_opencl.so (llama.cpp + OpenCL + Hexagon)
```

---



[Project Context: Haku - Private Life OS]

You are now acting as a strategic consultant and creative director for a deep-tech startup project named "Haku". Here is the comprehensive project DNA you need to understand:

1. THE CORE IDENTITY:
"Haku" is a "Private Life OS"—a proactive AI assistant that runs 100% on-device (offline). unlike ChatGPT or Gemini, Haku does NOT send user data to the cloud. It is designed for the "Post-Cloud Era" where privacy and data sovereignty are the ultimate luxuries.

2. THE KEY PROBLEM IT SOLVES:
Users want an AI that truly knows them (memories, secrets, habits) but are terrified of data leaks and corporate surveillance. Haku solves this by processing everything locally on the phone's NPU. "What happens on your phone, stays on your phone."

3. KILLER FEATURES (USPs):
- 100% On-Device Processing: Zero latency, works offline, absolute privacy.
- Hybrid Context Technology: A proprietary method that mixes raw local data (Thai/English) with compressed vector memories, allowing the AI to recall complex past events accurately without consuming massive storage.
- Proactive Intelligence: Instead of waiting for prompts, Haku nudges the user (e.g., "You seem stressed, here's a summary of your day," or "Leave now to beat traffic").
- Secure Team Delegation (B2B): A protocol allowing one user's Haku to talk to another user's Haku to schedule meetings or assign tasks without exposing sensitive calendar details to a central server.

4. BUSINESS MODEL (Razor & Blades):
- Freemium Entry: The core app is free to acquire a massive user base (The Razor).
- B2C Monetization: Users buy "AI Personas" (e.g., Strict Coach, Empathetic Friend) and Skill Modules via In-App Purchase (The Blades).
- B2B Monetization: Enterprises pay a subscription for the "Team Delegation Protocol" to boost productivity. Use Agent to Agent protocal.

5. FUTURE ROADMAP:
- Phase 1 (Now): A mobile app (iOS/Android) acting as a smart journal and assistant.
- Phase 2: An Ecosystem with B2B integration.
- Phase 3 (Vision): A full "Haku OS" or Launcher that replaces the standard Android interface, becoming the primary layer between the human and the digital world.

Please use this context for all further tasks, ensuring the tone is innovative, trustworthy, and user-centric.
---

## Phase 1: MVP ✅

พื้นฐานที่ต้องมีก่อน AI จะทำงานได้

- [x] SQLite + SQLCipher Encryption
- [x] Biometric Lock (Auto-lock 1-10 min)
- [x] Basic Chat UI
- [x] Android Widgets
- [x] Data Export (JSON, Markdown, CSV, Backup)
- [x] Profile Editor

---

## Phase 2: AI & Intelligence (Proactive Features)

**เป้าหมาย:** เปลี่ยนจาก "App" เป็น "Assistant" ที่ช่วยจัดการชีวิต

### 2.1 On-Device LLM ✅
**สถานะ:** เสร็จแล้ว

- [x] Gemma 3 1B ผ่าน MediaPipe GenAI (LiteRT `.task` format)
- [x] Auto-unload หลัง 5 นาทีไม่ใช้งาน (ประหยัดแบต)
- [x] Lazy loading — โหลดเมื่อเรียก generate() ครั้งแรก
- [x] Custom model path support
- [x] Two-Stage Architecture:
  - Stage 1 (The Face): ตอบสนทนาไทยธรรมชาติ
  - Stage 2 (Big Manager): classify intent + dispatch งาน

**Model:**
```yaml
primary_slm:
  model: Gemma 3 1B (LiteRT .task format)
  size: ~600 MB
  runtime: MediaPipe GenAI
  context: ~2048 tokens
  note: เล็กกว่า Qwen 2.5 3B (1.8GB) มาก ลื่นบนมือถือ
```

---

### 2.2 Cloud LLM Fallback (MCP Provider) ✅
**สถานะ:** เสร็จแล้ว + ThaiLLM (2026-03-06)

- [x] Gemini Flash (Google) — free tier
- [x] Claude Haiku (Anthropic)
- [x] GPT-4o-mini (OpenAI)
- [x] **OpenRouter** 🆕 — key เดียวเข้าถึงทุก model (Gemini, Claude, Llama ฯลฯ), default model: `google/gemini-2.0-flash-001`
- [x] **ThaiLLM (THaLLE-0.2-8B)** 🆕 — LLM ภาษาไทยโดย KBTG, 200 req/min ฟรี
  - Endpoint: `http://thaillm.or.th/api/kbtg/v1/chat/completions`
  - Auth: `apikey:` header (ไม่ใช่ `Authorization: Bearer`)
  - OpenAI-compatible chat completions format
- [x] MCP Client (Model Context Protocol) สำหรับ tunnel mode
- [x] Direct API mode สำหรับ dev
- [x] Settings UI: เลือก provider + กรอก API Key + Test Connection
- [x] Fallback chain: Cloud → On-device → Mock

**เข้าถึงผ่าน:** Settings > LLM Provider

---

### 2.3 Smart Search / RAG ✅
**สถานะ:** เสร็จแล้ว

- [x] Hybrid Vector Search (TF-IDF embedding + Cosine Similarity ใน Dart)
- [x] Unified Vector Service — รวม Entry, Facts, Knowledge
- [x] Context Retriever — ดึง context ที่เกี่ยวข้องให้ LLM
- [x] Index entries จาก database

**Technical:**
```yaml
vector_search:
  method: TF-IDF like embedding + Cosine Similarity
  storage: SQLite BLOB (ไม่ใช้ sqlite-vec เพราะ Flutter ไม่รองรับ)
  fallback: Keyword search
  note: ไม่ต้องโหลด embedding model แยก
```

**ตัวอย่าง:**
- "วันไหนที่ฉันมีความสุขที่สุด?" → ค้นจาก mood + context
- "ฉันไปเที่ยวทะเลเมื่อไหร่?" → ค้นจาก location + content

---

### 2.4 SmartPreprocessor + Workers ✅
**สถานะ:** เสร็จแล้ว (6 workers) + Bug fixes + Conditional RAG (2026-03-05)

ใช้ rule-based (0 LLM tokens) ก่อนส่งเข้า LLM:

- [x] **FactWorker** — จดจำชื่อ, ชอบ/ไม่ชอบ, อาชีพ, เป้าหมาย, สถานที่
  - [x] Fixed: require subject pronoun in `_likePatterns`/`_rolePatterns` (ลด false positive)
  - [x] Fixed: `_cleanValue` ใช้ whole-word replacement (ไม่ตัด "ร" ออกจาก "อะไร")
  - [x] Fixed: `_isValidPreference` + `_isValidGoal` มี question-word exclusion
- [x] **CalendarWorker** — ตรวจจับนัดหมายจากข้อความไทย (regex) + SharedPreferences
  - [x] Fixed: เพิ่ม day-first patterns → `"พรุ้งนี้มีนัดที่ศาลากลาง 9โมงเช้า"` ✓
  - [x] Fixed: เพิ่ม `มีนัด-first` patterns → `"มีนัดที่โรงพยาบาล พรุ่งนี้ 10 โมง"` ✓
  - [x] Fixed: เพิ่ม `"พรุ้งนี้"` (typo ของ "พรุ่งนี้") ใน `_dayOffsets`
  - [x] Fixed: เพิ่ม `(?:เช้า|เย็น|กลางคืน)?` suffix สำหรับ "9โมงเช้า" / "6โมงเย็น"
- [x] **ReminderWorker** — ตรวจจับการเตือน + frequency (once/daily/weekly/monthly)
- [x] **GoalWorker** — ตรวจจับเป้าหมาย + ติดตาม progress → lean format `[Goal:ออกกำลัง,0/3d/w]`
- [x] **HealthDoctor** — ตรวจจับ period, อาการปวด, แพ้, ยา
- [x] **TranslatorWorker** — batch Thai→English แบบ background (ตอนชาร์จ) สำหรับ RAG
- [x] Search intent detection (keyword-based) — fixed weather pattern (no capture groups)
- [x] Quick action detection (ทักทาย, ถามชื่อ) — fixed: wired into sendToAI() before LLM
- [x] `updateLeanContextWithEnglish()` — expose Secret Chat English result to lean context
- [x] **WeatherWorker** 🆕 — detect weather keywords → fetch Open-Meteo API → inject `[Weather]` context → `DetectedIntent.weather` (bypass web search + PreClassify)
  - patterns: อากาศ, ฝนตก, ฟ้า, ร้อน/หนาว วันนี้, พยากรณ์, forecast, พายุ, ลมแรง ฯลฯ
- [x] **English Past-Data Patterns** 🆕 — `_extractPastDataKeyword()` รองรับ English:
  - `did/have i ever ...`, `when/where/what did i ...`, `last time i ...`
  - `do you remember when/what i ...`, `have i been to/visited ...`
- [x] **Conditional RAG Fallback** 🆕 — Fast Path SQL (section 2.5) → RAG ถ้า SQL miss
  - SQL miss → `RAGService().search()` (semantic, language-agnostic)
  - `_extractPastFilters()` — detect date range + mood filters จากข้อความ
    - Thai: ปีที่แล้ว/เดือนที่แล้ว/ปีนี้/เดือนนี้/ช่วงนี้, ความสุข(minMood=4), เครียด(maxMood=2)
    - English: last year/month/week, this year/month, recently, happy/stressed
  - `_matchFilters()` + `_filterEntries()` — filter ตาม date range + mood ก่อนส่ง LLM
  - `_buildEntrySnippets()` — สร้าง "Related entries:\n..." สำหรับ LLM context
  - `_PastDataFilters` class — dateFrom/dateTo/minMood/maxMood
  - **LLM usage:** 0 extra (rule-based detection, enriches Face LLM context only)

**Enhancement: Brain-Dump Auto-Sorter** 🆕 (ตู้ไปรษณีย์คัดแยกความคิดอัตโนมัติ)

> พิมพ์ประโยคเดียวมั่วๆ เช่น "พรุ่งนี้บ่ายโมงประชุมเซลส์ อ้อ เตือนโอนค่าไฟด้วย แล้วตอนเย็นไปรับลูก"
> → Workers แยก 3 items อัตโนมัติ: 📅 ประชุมเซลส์ + ⏰ เตือนค่าไฟ + 📅 รับลูก

- [x] **CalendarWorker** — แก้ regex `allMatches` return `List<Event>` (หลาย events/message) + English patterns
- [x] **ReminderWorker** — แก้ regex `allMatches` return `List<Reminder>` (หลาย reminders/message) + English patterns
- [x] **SmartPreprocessor** — `buildBrainDumpSummary()` รวม results จากทุก worker เป็น summary string
- [x] **Brain-Dump Summary Card** — UI card ใน Chat แสดงรายการที่จับได้ เช่น "✅ จดได้ 3 รายการ: 📅 ประชุมเซลส์ 13:00 | ⏰ โอนค่าไฟ | 📅 รับลูกเย็นนี้"
- **LLM usage:** 0 (rule-based ล้วน — ใช้ regex เดิมที่มีอยู่ ไม่ต้องเปลือง token)

---

### 2.5 Lean Context Service ✅
**สถานะ:** เสร็จแล้ว + English compression upgrade + Token overflow fix (2026-03-05)

บีบ chat history ให้พอดี context window ของ Gemma 3 1B (~2048 tokens):

- [x] Chat 1-3: Full Thai (ไม่บีบ)
- [x] Chat 4+: Lean Syntax (ตัดคำลงท้าย, ย่อคำ, max 50 chars)
- [x] Session summaries (English, 1-line)
- [x] ผลลัพธ์: 25 คู่แชทใน ~330 tokens (เดิม 5 คู่ใน ~750 tokens)
- [x] **`updateLastPairWithEnglish()`** 🆕 — หลัง Secret Chat แปลเสร็จ → แทน Thai leanContent ด้วย English summary
  - English ประหยัด ~3-5x tokens เทียบกับ Thai ในทุก tokenizer
  - เรียกจาก SmartPreprocessor.updateLeanContextWithEnglish() หลัง Secret Chat dispatch
- [x] **Session summary 120-char cap** 🆕 — ป้องกัน token overflow จาก summaries สะสม
  - summaryEn > 120 chars → truncate + "..."
  - แก้ปัญหา: session summaries หลายรอบสะสมกันจน context เกิน 2048 tokens

---

### 2.5b PreClassify + Secret Chat First Architecture ✅ 🆕
**สถานะ:** เสร็จแล้ว (2026-02-27)

**ปัญหาเดิม:** Face LLM ตอบก่อน แล้ว Secret Chat แปลทีหลัง → Big Manager dispatch ช้า, Face ไม่รู้ intent

**แก้ไข:** PreClassify LLM ทำงาน**ก่อน** Face เพื่อให้ Face รู้ intent ล่วงหน้า + รองรับทุกภาษา

```
New flow:
User msg
  → SmartPreprocessor (Thai fast-path, 0 LLM tokens)
     ├─ rule-based จับได้ (schedule/remind/etc.) → skip preClassify
     └─ intent = general → 🔬 preClassify LLM (language-agnostic)
         → inject [INTENT:SCHEDULE:ศาลากลาง,2026-02-28,09:00] ใน context
  → Face LLM (รู้ intent → ตอบถูกต้อง)
  → [async] logExchange(preClassifyResult: ✓) → 0 extra LLM call
```

- [x] **`PromptBuilder.buildPreClassifyPrompt()`** — lean JSON prompt, classify ทุกภาษา
- [x] **`SecretChatService.preClassify()`** → `PreClassifyResult {intent, summaryEn, title, date, time}`
- [x] **`PreClassifyResult.contextHint`** — สร้าง `[INTENT:SCHEDULE:...]` hint สำหรับ Face
- [x] **`logExchange(preClassifyResult:)`** — ถ้ามี preClassify → ข้าม LLM extraction (0 extra call)
- [x] **chat_screen.dart wired** — preClassify → inject context → Face → async log

**ผลลัพธ์ Token Budget (per exchange):**

| Scenario | LLM calls |
|---|---|
| Rule-based จับ intent ได้ | 1 (Face only) + async log ด้วย preClassify |
| Rule-based ไม่จับ → preClassify | 2 (PreClassify + Face) + 0 async log |
| เดิม (ไม่มี preClassify) | 1 (Face) + 1 async (SecretChat) = 2 |

**Language support:** PreClassify LLM เข้าใจทุกภาษา — ไม่ต้องเพิ่ม Thai regex สำหรับ global launch

---

### 2.6 Entry Summarization ✅
**สถานะ:** เสร็จแล้ว

- [x] สรุป Entry เดี่ยว (บันทึกยาว → สั้น)
- [x] สรุปหลาย Entries (สรุปวัน/สัปดาห์)
- [x] Extract Key Insights
- [x] Sentiment Analysis (rule-based + mood)
- [x] Fallback เมื่อไม่มี LLM

---

### 2.7 AI Auto-Scheduling ✅
**สถานะ:** เสร็จแล้ว (basic)

- [x] SchedulerService — ดึง event จากข้อความธรรมชาติ
- [x] CalendarWorker — regex detection สำหรับวัน/เวลาไทย
- [x] PromptBuilder.buildSchedulerPrompt — LLM extraction
- [x] Native Calendar API (MethodChannel → `SchedulerBridge.kt` → `CalendarContract`)
- [x] **Fixed:** MethodChannel parameter mismatch (ส่ง `startTime`/`endTime` เป็น Long milliseconds แทน ISO string)
- [x] Auto reminder 15 นาทีก่อนนัด (`addReminder`)
- [x] Fallback regex เมื่อไม่มี LLM
- [ ] Google Calendar sync (มี Mock Mode, real API พร้อมแต่ยังไม่เปิดใช้จริง)

---

### 2.8 Proactive Triggers ✅
**สถานะ:** เสร็จแล้ว

- [x] Time-based triggers (09:00 เช้า, 12:00 เที่ยง, 17:00 เย็น, 22:00 ก่อนนอน)
- [x] Location-based triggers (revisit 200m, 2+ hr gap)
- [x] No-entry reminder
- [x] Battery-optimized: เช็คทุก 5 นาที, toggle location tracking
- [x] Notification Service + Quick Reply จาก notification
- [x] Deep link เข้าแอปพร้อม context
- [ ] Proactive Voice Alert (TTS) — ยังไม่ implement

---

### 2.9 Background Processing (Deferred to Charging) ✅
**สถานะ:** เสร็จแล้ว

- [x] ChatSummaryService — เก็บแชท 24 ชม. แล้วสรุปตอนชาร์จ
- [x] BatteryAwareService — ตรวจจับ charging/discharging
- [x] DeferredTaskService — priority queue (high/normal/low) + auto-process ตอนชาร์จ
- [x] ManagerSummaryStrategy — วิเคราะห์ health, behavior, preferences patterns
- [x] BackgroundTaskHandlers — wire ManagerSummary + reindex vectors เข้ากับ DeferredTask
- [x] Energy Profile (ultraSaver/batterySaver/balanced/performance)

---

### 2.10 Web Search Integration ✅
**สถานะ:** เสร็จแล้ว + ปรับปรุง engine + English patterns + no-results fix + Location-aware search (2026-03-06)

- [x] WebSearchService
- [x] SmartPreprocessor ตรวจจับ search intent อัตโนมัติ
- [x] LLM สรุปผลค้นหาเป็นคำตอบ
- [x] Intermediate "กำลังค้นหา..." message ใน UI
- [x] **SearXNG JSON API** 🆕 — แทน DuckDuckGo HTML scraping (โดนบล็อก), ไม่ต้อง API key
  - 4 public instances fallback: `search.bus-hit.me` → `searx.be` → `paulgo.io` → `searxng.org`
  - ส่ง `?format=json` → structured results ตรงๆ ไม่ต้อง parse HTML
- [x] **Jina AI Reader** 🆕 — แทน manual HTML parser สำหรับ `fetchPageContent()`
  - `GET https://r.jina.ai/{url}` → clean markdown text โดยตรง
  - Google scraping (`_searchGoogle`) ยังเก็บไว้เป็น last resort fallback
- [x] **English search patterns** 🆕 — `_searchPatterns` รองรับ English queries:
  - `search/find/look up/look for ...`, `what is ...`, `how to/do ...`
  - `where is/are/can i find ...`, `... nearby/near me`
  - keywords: `news`, `price`, `stock`, `nearby`, `near me`
- [x] **No-results fix** 🆕 — `searchForAI()` return `''` แทน Thai string เมื่อไม่พบผล
  - แก้ bug: string ไม่ว่างทำให้ follow-up LLM hallucinate จาก "no results" text
  - แสดง `"ขอโทษนะคะ ไม่พบข้อมูลที่ค้นหาได้ในขณะนี้ค่ะ..."` แทนแบบ static (ไม่ผ่าน LLM)
- [x] **Location-aware Search (Google Places API)** 🆕 — ค้นหาสถานที่ใกล้เคียง (BYOK)
  - `_searchGooglePlaces()` — Google Places Text Search API พร้อม lat/lng radius 3km
  - แสดงชื่อร้าน + ⭐rating + ระยะห่าง (ม./กม.) จาก Haversine formula
  - `searchForAI()` รับ optional `lat`, `lng`, `googlePlacesKey`
  - **Fallback chain:** Google Places → SearXNG (ถ้าไม่มี key หรือ Places ไม่มีผล)
  - **Nearby keywords:** `ใกล้ฉัน`, `ใกล้ที่นี่`, `ใกล้บ้าน`, `แถวนี้`, `ในละแวก`, `nearby`, `near me`
  - chat_screen.dart: detect nearby → `LocationService.getCurrentPosition()` + key จาก SharedPreferences → pass ไป `searchForAI()`
  - Settings > Web Search: ช่องใส่ Google Places API Key (obscure, save button)
  - **Cost model:** BYOK — user ใส่ key เอง, ฟรี 10K req/เดือน ($200 credit)

---

---

## Phase 2 (ต่อ): New Features ที่วางแผน

### 2.11 ผู้ช่วยจัดตารางอัจฉริยะ ✅
**สถานะ:** เสร็จแล้ว

> พิมพ์ภาษาธรรมชาติ → Haku จัด task + สร้าง event ให้ทันที

- [x] Natural language → `intent=schedule` (Secret Chat)
- [x] สร้าง event ใน Android Calendar (SchedulerService fixed)
- [x] Reminder 15 นาทีก่อน
- [x] `getCalendarEvents()` — อ่าน events จาก Android Calendar (`SchedulerBridge.getEvents()`)
- [x] `checkConflicts()` — ตรวจ overlap ก่อน create → `ConflictResult`
- [x] `createCalendarEventWithCheck()` — สร้าง + warn ถ้าชนนัด → `ScheduleResult`
- [ ] Time block อัตโนมัติ — จัด slot ว่างให้พอดีวัน (future)

---

### 2.12 ผู้ช่วยวางแผนวันทำงาน ✅
**สถานะ:** ~80% done

> เช็กอินตอนเช้า ดู agenda วันนี้ + สรุปตอนเย็น

- [x] สร้างนัดหมาย + เตือนงานสำคัญ (ผ่าน 2.11)
- [x] จัดลำดับ priority (`GoalWorker`)
- [x] **Morning check-in (09:00)** — แสดง agenda วันนี้จาก `CalendarWorker` ใน notification
- [x] **Evening summary (20:00)** — `TriggerType.eveningSummary` สรุปนัดวันนี้
- [x] **WorkManager time triggers** — `BackgroundTaskService` ยิง 09:00 + 20:00 แม้แอพปิด (dynamic content จาก SharedPreferences)

**Enhancement: Smart Sleep-Prep & Auto-Alarm** 🆕 (จัดตารางนอนและตั้งปลุกอัตโนมัติ)

> แค่เสียบชาร์จตอนดึก → Haku เช็คนัดพรุ่งนี้ → คำนวณเวลานอน → ตั้งปลุกให้เอง!
> เช่น "พรุ่งนี้มีประชุม 8 โมง ฉันตั้งปลุก 6:30 ไว้ให้แล้วนะ รีบนอนล่ะ!"

```
เสียบชาร์จหลัง 22:00
  → ChargingTrigger (มีแล้ว)
  → getCalendarEvents(tomorrow) (มีแล้ว)
  → earliestEvent = 08:00
  → alarmTime = eventTime - prepTime(1.5hr) = 06:30
  → SchedulerBridge.setAlarm(6, 30) ← ใหม่
  → NotificationService: "พรุ่งนี้ประชุม 8 โมง
     ตั้งปลุก 6:30 ไว้ให้แล้ว รีบนอนนะ!" (มีแล้ว)
```

- [x] **`SchedulerBridge.setAlarm()`** — MethodChannel → Android `AlarmClock.ACTION_SET_ALARM` (EXTRA_SKIP_UI=true) ✅
- [x] **Sleep calculation** — `calculateAlarmFromTomorrow(prepMinutes)` + safety guard (ไม่ปลุกก่อนตี 4 / หลัง 4 ทุ่ม) ✅
- [x] **ChargingTrigger integration** — wired ใน `MVPTriggerService.bedtime` (22:00): ถ้ามี event พรุ่งนี้ → auto-alarm ✅
- [x] **Evening notification** — แจ้งเตือนพร้อมบอกเวลาปลุกที่ตั้งไว้ (ใน bedtime trigger message) ✅
- [ ] **Settings: prep time** — ให้ user ตั้งค่าเวลาเตรียมตัว (default 1.5 ชม.)
- **LLM usage:** 0 (rule-based ล้วน — คำนวณเวลาจาก CalendarWorker)

---

### 2.13 บอทช่วยเลิกผัดวันประกันพรุ่ง 🟡
**สถานะ:** ~70% done — MVP พร้อมใช้

> Focus timer + Streak + Goal-Linked (Haku-specific)

- [x] **FocusTimerService** — Pomodoro state machine (25/5/15 min)
- [x] **StreakService** — นับวันต่อเนื่อง, milestone (7/30/100 วัน), persist
- [x] **Goal-linked** — เลือก Goal ก่อน focus → `GoalWorker.logProgress()` อัตโนมัติเมื่อเสร็จ
- [x] **FocusTimerScreen** — UI: timer ring, pomodoro dots, goal picker, streak badge
- [x] **FAB shortcut** — เข้าถึงได้จาก Home Screen expandable FAB
- [ ] Deep Work session — lock notifications ระหว่าง focus
- [ ] Break reminder notification — push notification เมื่อ pomodoro เสร็จ

---

## Phase 2 (ต่อ): User-Proposed Features

> เรียงตามความยากจากน้อยไปมาก — ทำทีละอัน

---

### 2.14 Chat Persistence — ไม่ Reset ประวัติแชท ✅
**สถานะ:** เสร็จแล้ว + Clear History Set Zero (2026-03-05)
**ความยาก:** ⭐ (ง่าย)

> เก็บประวัติ 50 ข้อความล่าสุดไว้ข้าม session — ไม่ต้อง scroll ขึ้นไปหาอีก

- [x] `ChatMessage.toJson()` / `fromJson()` / `isPersistable` — serialize เฉพาะ user/assistant/proactive
- [x] `ChatNotifier._loadHistory()` — โหลดตอนเปิดแอป (async, ไม่บล็อก UI)
- [x] `ChatNotifier._saveHistory()` — บันทึกทุกครั้งที่รับ message ที่ persist ได้
- [x] จำกัด 50 ข้อความ (trim จากหัว)
- [x] ปุ่ม "ล้างประวัติแชท" ใน PopupMenu พร้อม confirm dialog
- [x] **Clear History = Set Zero** 🆕 — ล้างทุกอย่างจริง (ไม่ใช่แค่ UI):
  - `SmartPreprocessor().clearLeanContext()` → ล้าง LeanContext ทั้งหมด
  - `SecretChatService().clearAll()` → ล้าง Secret Chat log + SharedPreferences
  - `SecretChatService.clearAll()` reset `_isInitialized = false` ด้วย
- **Storage:** SharedPreferences key `chat_history_v1`

---

### 2.20 Samsung Now Brief Dashboard + WeatherService ✅ 🆕
**สถานะ:** เสร็จแล้ว (2026-02-28)

> HomeScreen "บันทึก" tab redesign เป็น full-width stacked time-adaptive cards แบบ Samsung Now Brief

**Time Periods:**
- Morning (05-12): weather chip + today's schedule
- Midday (12-17): AI suggestion card
- Evening (17-22): streak + goals summary
- Night (22-05): tomorrow preview

**Cards implemented:**
- [x] `_HeroBriefCard` — Hero card พร้อม time-adaptive accent color (amber/blue/pink/purple)
- [x] `_CalendarCard` — events วันนี้จาก `SchedulerService.getCalendarEvents()`
- [x] `_GoalsCard` — active goals จาก `ObjectiveService.objectives`
- [x] `_StreakCard` — streak วันนี้จาก `StreakService.currentStreak`
- [x] `_AiSuggestionCard` — placeholder (midday period)

**WeatherService** (`lib/services/weather_service.dart`) — singleton:
- [x] Open-Meteo API (ฟรี ไม่ต้อง key) → 3-day daily forecast
- [x] `WeatherForecast` + `DayForecast` — rolling window (today/tomorrow/day after)
- [x] Daily cache in SharedPreferences key `weather_forecast_v1`
- [x] `isFresh` = same calendar day (ไม่ใช่ 24h rolling)
- [x] `getContextString()` → `[Weather]\nวันนี้: ☀️ สูง 32°C...` สำหรับ LLM prompt
- [x] Shared singleton — HomeScreen display + SmartPreprocessor WeatherWorker ใช้ cache เดียวกัน (ไม่ double call)

---

### 2.15 Meeting Pre-Flight Check — การ์ดเตรียมตัวก่อนประชุม
**สถานะ:** ยังไม่ implement
**ความยาก:** ⭐⭐ (ง่าย-ปานกลาง — ต่อยอดจาก system ที่มีอยู่)

> 15 นาทีก่อนถึงเวลานัด → Haku ดึง RAG แล้วสรุปบริบทให้อ่านก่อนเข้าประชุม

**Flow:**
```
CalendarWorker มีนัด
  ↓ (เวลา = now + 15 นาที)
MVPTriggerService.schedulePreFlight(event)
  ↓
TimerTrigger ยิง
  ↓
RAG search ด้วย event.title + attendees
  ↓
ดึง: Diary entries ที่พูดถึงหัวข้อ/คน + Facts + Goals ที่เกี่ยวข้อง
  ↓
Notification popup "📋 เตรียมพร้อมก่อนนัด: [ชื่อนัด]"
  ↓
เปิดแอปแสดง Pre-Flight Card ใน ChatScreen
```

**งานที่ต้องทำ:**
- [ ] `CalendarWorker.schedulePreFlightReminders()` — หลัง addEvent, schedule trigger 15 นาทีก่อน
- [ ] `MVPTriggerService.TriggerType.preFlightCheck` — trigger ชนิดใหม่
- [ ] RAG search ด้วย context ของ event (title + attendees keyword)
- [ ] Pre-Flight Card UI — แสดง recap entries + facts ที่เกี่ยวข้อง
- [ ] NotificationService.showPreFlightNotification()
- **LLM usage:** 1 call (สรุป RAG results เป็นภาษาธรรมชาติ)

---

### 2.16 Dynamic Morning/Evening Briefing — แดชบอร์ดสรุปวัน
**สถานะ:** ✅ Done (รวมกับ 2.20 Samsung Now Brief)
**ความยาก:** ⭐⭐⭐ (ปานกลาง — มี infrastructure แต่ต้องออกแบบ card UI)

> **Implemented:** `home_screen.dart` redesign (Session 4) — Dashboard แสดง Weather Card + Calendar Card (ตารางวันนี้) + Goals Card + Streak Badge แบบ glassmorphism real-time ทุกครั้งที่เปิดแอป

ส่วนที่ทำแล้ว:
- [x] Weather Card — อุณหภูมิ, คำแนะนำ (WeatherService)
- [x] Calendar Card — ตารางนัดวันนี้ (SchedulerService)
- [x] Goals Card — เป้าหมาย + circular progress (ObjectiveService)
- [x] Streak Badge — Focus streak (StreakService)
- [x] RefreshIndicator — pull-to-refresh ทุก card

ส่วนที่ยังไม่ทำ (optional enhancement):
- [ ] Evening summary push notification ตอนชาร์จ (EveningBriefingTask)
- [ ] Persist briefing card ข้ามวัน via SharedPreferences

---

### 2.17 Thought Catcher — ปุ่มจับความคิดด้วยเสียง
**สถานะ:** ยังไม่ implement (รอ STT)
**ความยาก:** ⭐⭐⭐⭐ (ยาก — ต้องมี STT ก่อน)

> กด mic → พูด → บันทึกอัตโนมัติ → CalendarWorker/ReminderWorker เซฟทันที (0 LLM)

**Flow:**
```
กด FAB mic button
  ↓
STT: speech → text (Google Speech API หรือ Whisper-Tiny)
  ↓
SmartPreprocessor.preprocess(text)
  ↓ (rule-based fast path)
CalendarWorker.detectEvents() หรือ ReminderWorker.detectReminders()
  ↓
Auto-save + animation feedback (ไม่ต้องรอ LLM)
  ↓
[async] preClassify → บันทึก English ใน lean context
```

**งานที่ต้องทำ:**
- [ ] เลือก STT engine: Google Speech-to-Text API (cloud) หรือ Whisper-Tiny on-device
- [ ] `SpeechToTextService` wrapper
- [ ] FAB mic button → recording UI (waveform animation)
- [ ] SmartPreprocessor fast-path: STT text → detect → save (ไม่รอ LLM)
- [ ] Confirmation snackbar: "จดแล้ว: [ชื่อนัด/reminder]"
- **LLM usage:** 0 (rule-based fast path), async preClassify สำหรับ lean context เท่านั้น
- **ข้อกำหนด:** ต้องมี STT ก่อน (Phase 3.4 หรือ Google Speech API)

---

### 2.18 Focus Goal HUD — วิดเจ็ตลอยตัวกันอู้งาน
**สถานะ:** ยังไม่ implement
**ความยาก:** ⭐⭐⭐⭐ (ยาก — Android Overlay permission ซับซ้อน)

> Pomodoro timer ลอยอยู่บนหน้าจอ อัปเดต streak + goal โดยไม่ปลุก LLM

**Architecture:**
```
FocusTimerService (มีอยู่แล้ว)
  ↓ (rule-based timer, 0 LLM)
Android Overlay Service (SYSTEM_ALERT_WINDOW permission)
  ↓
Floating Widget: [timer] [streak 🔥] [goal name]
  ↓ (เมื่อ pomodoro เสร็จ)
GoalWorker.logProgress() → StreakService.increment()
  ↓
NotificationService: "🍅 Pomodoro เสร็จ!"
```

**งานที่ต้องทำ:**
- [ ] Android `SYSTEM_ALERT_WINDOW` permission flow (ต้องให้ user เปิดใน Settings)
- [ ] `FloatingHUDService` — Android Foreground Service + WindowManager overlay
- [ ] MethodChannel: Flutter ↔ FloatingHUDService (start/stop/update)
- [ ] Floating Widget layout (compact, draggable)
- [ ] FocusTimerService → broadcast state updates ไปยัง HUD
- **LLM usage:** 0 (rule-based ล้วน)
- **ข้อกำหนด:** Android 8.0+ (API 26+)

---

### 2.19 Contextual Memory Canvas — แผนผังความจำแบบภาพ
**สถานะ:** ยังไม่ implement
**ความยาก:** ⭐⭐⭐⭐⭐ (ยากมาก — UI intensive + heavy RAG)

> ดึง vectors จาก RAG มาวาด Mind Map แสดงความเชื่อมโยงระหว่าง Calendar, Facts, Diary

**Architecture:**
```
User เปิดหน้า Memory Canvas
  ↓
UnifiedVectorService.getClusteredVectors()
  ↓ (cosine similarity clustering)
CalendarWorker events + FactWorker facts + Diary entries
  ↓
Build graph: nodes = topics, edges = cosine similarity > 0.7
  ↓
Render Mind Map (flutter_graph หรือ custom Canvas painter)
  ↓
Tap node → ขยายดู raw content
```

**งานที่ต้องทำ:**
- [ ] `VectorGraphService` — cluster vectors + build adjacency graph
- [ ] `MemoryCanvasScreen` — Mind Map UI (custom `CustomPainter` หรือ library)
- [ ] Cross-worker data aggregation (Calendar + Fact + Diary ใน format เดียวกัน)
- [ ] Tap-to-expand: แสดง raw content ของ node
- [ ] Filter by date range / category
- [ ] Performance: lazy load ไม่ดึง vector ทั้งหมดพร้อมกัน
- **LLM usage:** 0 (visualization only, clustering = cosine similarity)
- **dependency candidates:** `graphview`, `flutter_force_directed_graph`, หรือ custom painter

---

## Pre-MVP Checklist (ก่อน Public Launch)

> งานที่ต้องทำก่อนปล่อยให้ผู้ใช้จริง — ข้ามข้อไหนไม่ได้

### Background Processing (งานหนัก เมื่อชาร์จ)

- ❌ **WorkManager batch** — defer post-MVP
  - TFLite ไม่รองรับ background isolate → LLM tasks ทำ background ไม่ได้อยู่แล้ว
  - `reindex_vectors` / `vectorize_topics` (non-LLM) ยังไม่ critical สำหรับ MVP
  - `BackgroundTaskService` ที่มีอยู่ handle notification scheduling ได้พอ

### Focus Timer (2.13 ที่ยังค้าง)

- [x] **Break reminder notification** — ✅ Done: `BackgroundTaskService.showBreakStartNotification()` + `showFocusReminderNotification()` wire แล้วใน `FocusTimerService._advanceState()`
- [ ] **Deep Work session** — mute notifications ระหว่าง focus session (post-MVP)

### GPS / Background Location

- [x] ✅ **ตัดสินใจ: Include สำหรับ MVP** — `GeofenceService` (Haversine, zone enter/exit, 5-min polling) + `MVPTriggerService` (locationRevisit trigger) implement แล้วครบ
  - ใช้ low accuracy + 200m distance filter → battery-friendly
  - `GeofenceService().startMonitoring()` เรียกจาก `ChatScreen._initializeServices()` (foreground เท่านั้น)
  - *ไม่ต้อง Foreground Service สำหรับ MVP — periodic polling เพียงพอ*
  - **ข้อจำกัด:** DwellTracker ทำงานได้เฉพาะตอนแอพเปิดอยู่ foreground — ถ้าแอพปิดจะไม่มี GPS poll
  - **Post-MVP:** WorkManager background polling → Phase 5.1

---

## Phase 3: Beta Testing (Insights & Analytics)

**เป้าหมาย:** วิเคราะห์ pattern ชีวิตและให้ insights

### 3.1 The Hidden Correlation
**สถานะ:** ✅ Done — `lib/services/correlation_service.dart`

หาความเชื่อมโยงที่ซ่อนอยู่ในชีวิต เช่น:
> "73% ของวันอารมณ์ไม่ดี มักเกิดขึ้นในวันที่มีเครียด"

- [x] Co-occurrence analysis + Lift scoring (pure Dart, 0 LLM)
- [x] Signals: กาแฟ, นอนดึก, เครียด, ประชุม/สังคม, ปวดหัว, ออกกำลังกาย, อาหารไม่ดี
- [x] Outcomes: lowMood (mood ≤ 2), fatigue (keyword), highMood (mood ≥ 4)
- [x] `_InsightCard` ใน home_screen — confidence chip + tinted message box
- [ ] (optional) LLM narrative สำหรับ insight ที่ซับซ้อน

---

### 3.2 Social Battery Forecast
**สถานะ:** ✅ Done — `lib/services/social_battery_service.dart`

พยากรณ์ "พลังงานสังคม" และเตือนก่อน burnout

- [x] Energy Cost Table: draining (ประชุม -10, งานสังคม -14, เครียด -10) / recharging (คนเดียว +12, นอน +10)
- [x] Cumulative score จาก 14 วันล่าสุด → level 0–100
- [x] Trend: เปรียบ 7 วันล่าสุด vs 7 วันก่อน (mood average)
- [x] `_SocialBatteryCard` ใน home_screen — LinearProgressIndicator + trend badge + nudge message
- [ ] (optional) Push notification เมื่อ level < 30 ติดต่อกัน 3 วัน

---

### 3.3 Music & News Context (Mood Tracking)
**สถานะ:** ยังไม่ implement

- [ ] Android Notification Listener → ดึงชื่อเพลงจาก Spotify/YT Music
- [ ] RSS Feed สรุปข่าว
- [ ] Morning Briefing (TTS อ่านข่าว + สรุปตาราง)

---

### 3.4 Proactive Voice Alert (TTS)
**สถานะ:** ยังไม่ implement

- [ ] Google TTS (pre-installed) หรือ Piper TTS (~50MB)
- [ ] Personalized alert messages ผ่าน LLM
- [ ] iOS: Siri Announce Notifications

```yaml
tts_engine:
  android: Google TTS (pre-installed) หรือ Piper-TTS (~50MB)
  ios: Siri Announce Notifications
```

---

## Phase 4: Production (Advanced Personalization)

**เป้าหมาย:** AI ที่เข้าใจคุณในระดับลึก

### 4.1 Shadow Mode (AI Writing Style)
**สถานะ:** ยังไม่ implement

AI เรียนรู้สไตล์การเขียนของคุณ และ Draft คำตอบให้เหมือนคุณพิมพ์เอง

- [ ] Few-shot prompting (ใช้ข้อความเก่าเป็น example)
- [ ] หรือ LoRA Fine-tune บน device (Gemma 2 2B base)

---

### 4.2 AR Memory Anchor (Future Concept)
**สถานะ:** ยังไม่แน่ใจ technical feasibility

ชี้กล้องไปที่สถานที่ → Haku บอกว่าเคยมีความทรงจำอะไรที่นี่

---

### 4.3 Direct Diary — บันทึกความจำฝังลึก (Core Memory)
**สถานะ:** ยังไม่ implement
**ความยาก:** ⭐⭐ (ง่าย — ต่อยอดจาก FactWorker + UnifiedVectorService ที่มี)

> บางเรื่อง diary ปกติเขียนแล้วจมหาย แต่บางอย่างอยากให้ AI "จำขึ้นใจ" เอามาเตือนสติ/ให้กำลังใจในอนาคต

**UX/UI:**
- ผู้ใช้สร้าง **หัวข้อ** (topic) เอง เช่น "ความสำเร็จ", "บทเรียนชีวิต", "กำลังใจ"
- พิมพ์/พูดนำหน้าด้วย "จำไว้นะ...", "Haku จดลงไดอารี่สำคัญ..."
- UI Feedback: แอนิเมชัน ⭐/🔒 ล็อกเก็บยืนยันว่าข้อมูลถูกจัดเก็บระดับพิเศษ
- เปิดหน้า Direct Diary → ดูรายการทั้งหมดแยกตามหัวข้อ (user อ่านเองได้)

**Architecture:**
```
User: "จำไว้นะ วันนี้พรีเซนต์งานผ่านแล้ว!"
  → SmartPreprocessor: regex จับ "จำไว้" → intent = directDiary
  → Face LLM ตอบ: "จดไว้แล้วนะ! เก่งมาก 🌟" (1 call)
  → [async] addFact(category: 'core_memory', topic: 'ความสำเร็จ',
       content: '...', metadata: {mood: 'positive', weight: 3})
  → AI ดึงมาแสดง: เมื่อ mood ≤ 2 → searchFacts(core_memory)
     → ดึงทีละ 1-2 ข้อ (ไม่ยัดทั้งหมด ไม่เปลือง context window)
```

**งานที่ต้องทำ:**
- [ ] `DirectDiaryScreen` — หน้า UI แสดง entries แยกตามหัวข้อ (CRUD)
- [ ] `SmartPreprocessor` เพิ่ม regex pattern: "จำไว้", "จดลงไดอารี่สำคัญ" → `DetectedIntent.directDiary`
- [ ] `addFact(category: 'core_memory')` + metadata `weight` field
- [ ] `UnifiedVectorService.search()` เพิ่ม weight boosting: `core_memory` → score × 2-3
- [ ] Evening Briefing integration: ถ้า mood ต่ำ → ดึง positive core_memory มาแสดง
- [ ] UI animation: ⭐ lock effect เมื่อบันทึกสำเร็จ
- **LLM usage:** 1 call (Face only) — SmartPreprocessor จับ intent ด้วย regex (0 token)

**Phase 5 Upgrade:**
- [ ] Automation Rule: `ถ้า mood < 3 ติดต่อกัน 2 วัน → ดึง Direct Diary (positive) → push notification`
- [ ] Automation Rule: `ทุกเช้า 8 โมง → ดึง random core_memory → แสดงใน Morning Briefing`

---

### 4.4 Direct Table — ตารางเฉพาะกิจ (Auto-Tracker)
**สถานะ:** ยังไม่ implement
**ความยาก:** ⭐⭐⭐ (ปานกลาง — ต้องสร้าง dynamic table + chart UI)

> หมอสั่งให้จดความดัน, เทรนเนอร์สั่งให้จดน้ำหนัก, อยากจดค่าใช้จ่าย — ต้องเปิด Excel ในมือถือน่ารำคาญจนเลิกทำ

**UX/UI:**
- ผู้ใช้สร้าง **ตาราง** เอง: ตั้งชื่อ + กำหนดคอลัมน์ + แถว
  - เช่น ตาราง "ความดัน" → คอลัมน์: ค่าบน, ค่าล่าง, หน่วย: mmHg
- พิมพ์/พูดสั้นๆ: "ความดันเช้านี้ 120 80" หรือ "น้ำหนัก 65"
- UI Feedback: popup **MiniChart** แสดงข้อมูลล่าสุด + trend เทียบเมื่อวาน
- เปิดหน้า Direct Table → ดูตาราง + กราฟ full-size

**Architecture:**
```
User: "ความดันเช้านี้ 120 80"
  → SmartPreprocessor → TrackerWorker (rule-based):
      table_name = "ความดัน" (match จาก user config)
      values = [120, 80]
      timestamp = now
  → SQLite INSERT → tracker_entries
  → Face LLM: "จดแล้ว! ความดัน 120/80 ปกติดีเลย"
  → UI: popup MiniChart แสดง trend 7 วัน

User: "สรุปความดันเดือนนี้ให้หน่อย"
  → intent = tracker_summary
  → query SQLite → ดึงข้อมูลเดือนนี้
  → LLM สรุป + แสดงตาราง/กราฟ
```

**งานที่ต้องทำ:**
- [ ] SQLite table: `tracker_tables` (id, name, columns JSON, unit, created_at)
- [ ] SQLite table: `tracker_entries` (id, table_id, values JSON, timestamp)
- [ ] `DirectTableScreen` — หน้า UI: สร้างตาราง + ดูข้อมูล + กราฟ full-size
- [ ] `TrackerWorker` (rule-based) — regex จับ table_name + numeric extraction
- [ ] `MiniChartWidget` — inline chart ใน ChatScreen
- [ ] `SmartPreprocessor` เพิ่ม intent: `DetectedIntent.tracker` + `DetectedIntent.trackerSummary`
- [ ] Export: สรุปตารางเป็น text/image สำหรับส่งให้หมอ
- **LLM usage:** 1 call (Face) สำหรับ input, 1 call สำหรับ summary query

**Phase 5 Upgrade:**
- [ ] Automation Rule: `ทุกเช้า 8 โมง → ถ้ายังไม่จดความดันวันนี้ → push notification เตือน`
- [ ] Automation Rule: `ทุกวันศุกร์ → สรุปตาราง 7 วัน → ส่งเข้าแชท`
- [ ] Condition: `ถ้าความดัน > 140 → แจ้งเตือนทันที`

---

---

## Phase 5: Background Intelligence

---

### 5.1 Background Geofence via WorkManager
**สถานะ:** ยังไม่ implement (Post-MVP)
**ความยาก:** ⭐⭐⭐⭐ (ยาก — Android Native + Kotlin WorkManager + Fused Location)

> ตอนนี้ GeofenceService ทำงานได้เฉพาะตอนแอพเปิดอยู่ (foreground polling ทุก 5 นาที)
> Phase 5.1 ทำให้ DwellTracker ทำงานได้แม้แอพปิด โดยใช้ WorkManager + Fused Location API

**ปัญหาที่แก้:**
```
ปัจจุบัน (MVP):
  แอพเปิด → GPS poll ทุก 5 นาที → DwellTracker → ตรวจ dwell ✅
  แอพปิด  → ไม่มี GPS poll → ไม่รู้ว่าไปไหน ❌

เป้าหมาย (5.1):
  แอพปิด  → WorkManager ยิง task ทุก 15 นาที → poll GPS → DwellTracker ✅
  ออกจากสถานที่ → feedback queued → เปิดแอพครั้งถัดไป → Haku ถามทันที ✅
```

**Architecture:**
```
Android WorkManager (PeriodicWorkRequest, 15 นาที minimum)
  ↓ LocationWorker.kt (Kotlin, Coroutine)
  ↓ FusedLocationProviderClient.getCurrentLocation(PRIORITY_LOW_POWER)
  ↓ SharedPreferences: บันทึก lastLat/lastLng/lastTime
  ↓ DwellLogic.kt (native — Haversine, dwell state, callback)
     ถ้า dwell สำเร็จ → เพิ่มใน place_feedback_queue (SharedPreferences)
  ↓ (เปิดแอพ) ChatScreen → dequeuePending() → PlaceFeedbackService → Haku ถาม
```

**งานที่ต้องทำ:**

Kotlin (Android):
- [ ] `LocationWorker.kt` — WorkManager `CoroutineWorker`, inject `FusedLocationProviderClient`
- [ ] `DwellLogic.kt` — Haversine + dwell state machine (mirror ของ `dwell_tracker.dart`)
- [ ] `WorkManagerBridge.kt` — MethodChannel `startBackgroundGeofence` / `stopBackgroundGeofence`
- [ ] Manifest: `ACCESS_BACKGROUND_LOCATION` permission + WorkManager dependency
- [ ] `SchedulerBridge.kt` (existing): เพิ่ม `writeFeedbackQueue()` helper

Flutter:
- [ ] `GeofenceService.startMonitoring()`: ถ้า Android → เรียก WorkManager bridge ด้วย
- [ ] Settings UI: toggle "Background Location Tracking" (แสดงผลกระทบ battery ชัดเจน)
- [ ] Permission flow: `ACCESS_BACKGROUND_LOCATION` (Android 10+) → dialog อธิบายเหตุผล

**Battery Impact:**
| Mode | GPS call | Battery/วัน |
|---|---|---|
| Foreground only (ปัจจุบัน) | ทุก 5 นาที ขณะเปิดแอพ | ~0 (แอพปิดไม่กิน) |
| WorkManager (Phase 5.1) | ทุก 15 นาที ตลอดเวลา | ~1-2% (PRIORITY_LOW_POWER) |

**Permission ที่ต้องขอเพิ่ม:**
- `android.permission.ACCESS_BACKGROUND_LOCATION` (Android 10+, ต้องขอแยกจาก foreground)
- User ต้องเลือก "Allow all the time" ใน Location Settings (ไม่ใช่แค่ "While using app")

**LLM usage:** 0 (rule-based ล้วน — native Kotlin + SharedPreferences)

---

## Phase 5 (ต่อ): Automation Engine (Future Concept)

**เป้าหมาย:** No-code automation แบบ Samsung Routine สำหรับ Haku — Trigger → Action โดยไม่ต้อง run LLM ตลอดเวลา

> ไอเดียนี้ยังอยู่ในขั้นวางแผน — ยังไม่ implement (มี mockup UI ใน Settings)

### แนวคิดหลัก

ผู้ใช้สร้าง "Rule" ด้วย Visual Block Editor (ไม่ต้องเขียน code):

```
[TRIGGER]  ──→  [CONDITION]  ──→  [ACTION]
เวลา 08:00        ถ้าพรุ่งนี้มีนัด      แจ้งเตือน "เตรียมตัวก่อนนัด"
ชาร์จแบต         ถ้า mood < 3          ส่ง "Check-in" เข้าแชท
เชื่อม WiFi บ้าน  ─                   เปลี่ยน ringtone เป็น silent
```

### Trigger Types (Battery-Efficient)

| Trigger | Android API | Battery Impact |
|---|---|---|
| เวลาที่กำหนด | AlarmManager (exact) | ~0 |
| ทุก N นาที (min 15) | WorkManager | ~ต่ำ |
| เสียบชาร์จ / ถอดชาร์จ | BroadcastReceiver | ~0 |
| เชื่อม WiFi SSID | BroadcastReceiver | ~0 |
| เข้า / ออก สถานที่ | Geofencing API | ต่ำ (fused) |
| Battery level | BroadcastReceiver | ~0 |
| เปิดแอป | App Lifecycle | ~0 |

### Action Types

- **ส่งข้อความเข้าแชท** — inject `ChatMessage.assistant(text)` เหมือน bot พูด
- **แจ้งเตือน** — push notification พร้อม Quick Reply
- **ค้นหาเว็บ** — trigger WebSearchService + ส่งผลเข้าแชท
- **บันทึก entry** — auto-create diary entry (0 LLM)
- **เปิดหน้า** — deep link ไปยังหน้าในแอป

### Step DSL Architecture (ไม่ใช่ arbitrary code)

```dart
// Step = typed action, ไม่ใช่ Turing-complete script
sealed class AutomationStep {}
class NotifyStep extends AutomationStep { final String title, body; }
class ChatMessageStep extends AutomationStep { final String message; }
class WebSearchStep extends AutomationStep { final String query; }
class CreateEntryStep extends AutomationStep { final String content; }

class AutomationRule {
  final String id, name, emoji;
  final TriggerConfig trigger;
  final List<AutomationStep> steps;
  final bool enabled;
}
```

### Mockup UI (ทำแล้ว)

- **AutomationScreen** (`lib/screens/automation_screen.dart`) — เข้าจาก Settings > Automation
- FAB "+" ด้านล่างขวา (placeholder, ยังเพิ่ม rule จริงไม่ได้)
- Demo cards:
  - **Gold Ticker 1Hr** 🥇 — กด Run → สุ่มราคาทอง → inject เข้าแชท
  - **Stock Ticker 1Hr** 📈 — กด Run → สุ่ม 3 หุ้น + ราคา → inject เข้าแชท

### งานที่ต้องทำ (Post-MVP)

- [ ] `AutomationRule` model + SharedPreferences persistence
- [ ] `AutomationEngine` service — load rules, register triggers, dispatch steps
- [ ] `TriggerRegistry` — AlarmManager / BroadcastReceiver / WorkManager bridge (Kotlin)
- [ ] Rule Builder UI — Visual block editor (drag-and-drop triggers + actions)
- [ ] Condition evaluator — `mood < 3`, `hasEventToday`, `batteryLevel < 20`
- [ ] Settings > Automation tile → AutomationScreen

---

## สรุปโมเดลที่ใช้

```yaml
# Core SLM — On-Device (ใช้ทุกฟีเจอร์)
primary_slm:
  model: Gemma 3 1B
  format: LiteRT (.task) ผ่าน MediaPipe GenAI
  size: ~600 MB
  context: ~2048 tokens
  features:
    - auto-unload หลัง 5 นาที (ประหยัดแบต)
    - lazy loading (โหลดเมื่อใช้จริง)
    - custom model path support

# Cloud LLM Fallback — ใช้แทน SLM เมื่อ user ต้องการ
cloud_providers:
  gemini_flash:
    provider: Google
    note: Free tier, เร็ว
  claude_haiku:
    provider: Anthropic
    cost: $0.25/1M tokens
  gpt4o_mini:
    provider: OpenAI
    cost: $0.15/1M tokens
  openrouter:
    provider: OpenRouter
    note: key เดียวใช้ได้ทุก model, default google/gemini-2.0-flash-001
    key_format: sk-or-v1-...
  thaillm:
    provider: KBTG (THaLLE-0.2-8B)
    note: LLM ภาษาไทย, 200 req/min ฟรี
    auth: apikey header (ไม่ใช่ Authorization Bearer)
  connection:
    - Tunnel mode (API key ฝั่ง server)
    - Direct mode (API key ในแอป)

# Vector Search (สำหรับ RAG)
vector_search:
  method: TF-IDF embedding + Cosine Similarity (Dart)
  storage: SQLite BLOB
  note: ไม่ต้องโหลด embedding model แยก

# Workers (Rule-based, 0 tokens) — 7 ตัว
workers:
  - FactWorker (ชื่อ, ชอบ, อาชีพ, เป้าหมาย)
  - CalendarWorker (นัดหมาย, เวลา)
  - ReminderWorker (เตือน, ความถี่)
  - GoalWorker (เป้าหมาย, progress)
  - HealthDoctor (ประจำเดือน, อาการ, ยา, แพ้)
  - TranslatorWorker (Thai→English batch, background ตอนชาร์จ)
  - WeatherWorker (Open-Meteo 3-day, daily cache, bypass web search)

# STT (Speech-to-Text) — ยังไม่ implement
stt_engine:
  on_device: Whisper-Tiny (~75MB) — ไทยไม่แม่น
  cloud: Google Speech-to-Text API

# TTS (Text-to-Speech) — ยังไม่ implement
tts_engine:
  android: Google TTS (pre-installed) หรือ Piper-TTS (~50MB)
  ios: Siri Announce Notifications
```

---

## สรุป Progress

| Phase | Feature | สถานะ |
|-------|---------|-------|
| 1 | SQLite + Encryption | ✅ |
| 1 | Biometric Lock | ✅ |
| 1 | Chat UI | ✅ |
| 1 | Android Widgets | ✅ |
| 2 | On-Device LLM (Gemma 3 1B + MediaPipe) | ✅ |
| 2 | Cloud LLM (Gemini/Claude/OpenAI/OpenRouter/ThaiLLM) | ✅ |
| 2 | Smart Search / RAG | ✅ |
| 2 | SmartPreprocessor + Workers (6 ตัว) | ✅ |
| 2 | Lean Context (token compression) + English update | ✅ |
| 2 | Entry Summarization | ✅ |
| 2 | Secret Chat Architecture + PreClassify First | ✅ |
| 2 | Auto-Scheduling + MethodChannel fix | ✅ |
| 2 | Proactive Triggers (time + location) | ✅ |
| 2 | Background Processing (charging) | ✅ |
| 2 | Web Search (SearXNG JSON + Jina AI reader + Google Places nearby) | ✅ |
| 2 | WeatherService (Open-Meteo, 3-day cache, weather worker) | ✅ |
| 2 | Samsung Now Brief Dashboard (HomeScreen redesign) | ✅ |
| 2 | CLI Test Tool (`/batch`, `/schedule`, `/translate`) | ✅ |
| 2 | Google Calendar (real API) | 🟡 Mock Mode |
| 2 | Proactive Voice (TTS) | ❌ |
| 2 | CalendarWorker day-first + typo support | ✅ |
| 2 | ผู้ช่วยจัดตารางอัจฉริยะ (2.11) | ✅ conflict detection |
| 2 | ผู้ช่วยวางแผนวันทำงาน (2.12) | ✅ morning agenda + evening summary |
| 2 | บอทช่วยเลิกผัดวันประกันพรุ่ง (2.13) | 🟡 70% goal-linked MVP |
| 2 | Chat Persistence 50 messages (2.14) | ✅ |
| 2 | Samsung Now Brief + WeatherService (2.20) | ✅ |
| 2 | Meeting Pre-Flight Check (2.15) | ❌ planned |
| 2 | Morning/Evening Briefing (2.16) | ✅ home_screen dashboard |
| 2 | Thought Catcher — Voice (2.17) | ❌ รอ STT |
| 2 | Focus Goal HUD — Overlay (2.18) | ❌ planned |
| 2 | Memory Canvas — Mind Map (2.19) | ❌ planned |
| 3 | Hidden Correlation | ✅ |
| 3 | Social Battery | ✅ |
| 3 | Music/News Context | ❌ |
| 4 | Shadow Mode (4.1) | ❌ |
| 4 | AR Memory Anchor (4.2) | ❌ |
| 4 | Direct Diary — Core Memory (4.3) | ❌ planned |
| 4 | Direct Table — Auto-Tracker (4.4) | ❌ planned |
| 5 | Background Geofence via WorkManager (5.1) | ❌ planned |
| 5 | Automation Engine | ❌ planned |

**Phase 2 progress: ~98%** (เหลือ Google Calendar real, TTS, Deep Work notification)

---

## งบประมาณพื้นที่

```
App base:          ~30 MB
Gemma 3 1B (.task): ~600 MB
----------------------------
รวม:              ~630 MB (ลดจาก ~2GB ที่วางแผนไว้เดิม)
```

## งบประมาณ RAM

```
Gemma 3 1B: ~1-2 GB ขณะทำงาน (auto-unload หลัง 5 นาที)
มือถือ RAM 4GB+: ใช้ได้สบาย
Cloud mode: ไม่กิน RAM เพิ่ม (ส่ง API แทน)
```



┌─────────────────────────────────────────────────────────────────────────────┐
│                           HAKU AI SYSTEM                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                      REAL-TIME LAYER (ขณะแชท)                          │ │
│  │                                                                         │ │
│  │  ① SmartPreprocessor (rule-based, 0 LLM tokens)                        │ │
│  │  ┌─────────────────────────────────────────────────────────────────┐   │ │
│  │  │ User message (Thai)                                              │   │ │
│  │  │  → FactWorker / CalendarWorker / HealthDoctor (0 tok, regex)    │   │ │
│  │  │  → [Fast Path] SQL LIKE search on Thai entries                  │   │ │
│  │  │    (e.g. "เคยไปทะเล" → SELECT * WHERE content LIKE '%ทะเล%')    │   │ │
│  │  │  → Build lean context (profile + history + found entries)       │   │ │
│  │  └─────────────────────────────────────────────────────────────────┘   │ │
│  │                              │                                          │ │
│  │  ② 🔬 PreClassify (🆕 ถ้า intent=general — language-agnostic)          │ │
│  │  ┌─────────────────────────────────────────────────────────────────┐   │ │
│  │  │ buildPreClassifyPrompt(userMessage) → JSON                      │   │ │
│  │  │ Input: user message only (any language)                         │   │ │
│  │  │ Output: {intent, summaryEn, title?, date?, time?}               │   │ │
│  │  │ → inject [INTENT:SCHEDULE:...] ใน context ก่อน Face             │   │ │
│  │  └─────────────────────────────────────────────────────────────────┘   │ │
│  │                              │                                          │ │
│  │  ③ Stage 1: The Face (ตอบ user พร้อม intent context)                   │ │
│  │  ┌─────────────────────────────────────────────────────────────────┐   │ │
│  │  │ Gemma 3 1B — ตอบภาษาไทยธรรมชาติ (1-2 ประโยค)                    │   │ │
│  │  │ Input: lean context + [INTENT:...] hint + user message          │   │ │
│  │  │ Output: Thai response → แสดง user ทันที                         │   │ │
│  │  └─────────────────────────────────────────────────────────────────┘   │ │
│  │                              │                                          │ │
│  │  ④ Secret Chat (async — 0 extra LLM call ถ้ามี preClassify) 🆕        │ │
│  │  ┌─────────────────────────────────────────────────────────────────┐   │ │
│  │  │ ถ้ามี preClassifyResult → ใช้ intent+summaryEn โดยตรง           │   │ │
│  │  │ ถ้าไม่มี → run buildWorkerExtractPrompt() ตามปกติ               │   │ │
│  │  │ Output: EnglishLogEntry {                                       │   │ │
│  │  │   summaryEn: "appointment city hall tmrw 9am"                   │   │ │
│  │  │   intent: log | schedule | query | chat                        │   │ │
│  │  │   tags: ["city hall"]                                           │   │ │
│  │  │ }                                                               │   │ │
│  │  │ → Store in SharedPreferences (english_chat_log, 50 entries)    │   │ │
│  │  │ → updateLastPairWithEnglish(summaryEn) → lean context EN 🆕    │   │ │
│  │  └─────────────────────────────────────────────────────────────────┘   │ │
│  │                              │                                          │ │
│  │  ④ Big Manager (async — dispatch from English log)                      │ │
│  │  ┌─────────────────────────────────────────────────────────────────┐   │ │
│  │  │ Reads EnglishLogEntry (no LLM call — intent already extracted)  │   │ │
│  │  │ dispatch:                                                        │   │ │
│  │  │   intent=schedule → CalendarWorker.addEvent()                   │   │ │
│  │  │   intent=log      → FactWorker.extractFacts()                   │   │ │
│  │  │   intent=search   → WebSearchService.search()                   │   │ │
│  │  │   intent=chat     → (no action, logged only)                    │   │ │
│  │  └─────────────────────────────────────────────────────────────────┘   │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                      SEARCH STRATEGY                                    │ │
│  │                                                                         │ │
│  │  Fast Path (ทันที, 0 LLM):                                              │ │
│  │  ┌─────────────────────────────────────────────────────────────────┐   │ │
│  │  │ SmartPreprocessor → keyword extraction (regex)                  │   │ │
│  │  │ → SQL LIKE search on raw Thai entries                           │   │ │
│  │  │ → ถ้าเจอ → เพิ่มใน context ก่อนส่ง Face                         │   │ │
│  │  └─────────────────────────────────────────────────────────────────┘   │ │
│  │                                                                         │ │
│  │  Slow Path (future, LLM-assisted):                                      │ │
│  │  ┌─────────────────────────────────────────────────────────────────┐   │ │
│  │  │ ถ้า Fast Path ไม่เจอ → แสดง "thinking..." animation             │   │ │
│  │  │ → Translate Thai query → English                                │   │ │
│  │  │ → Vector search English DB (whitespace tokenizer ใช้ได้)        │   │ │
│  │  │ → ส่ง context ให้ Face ตอบ                                       │   │ │
│  │  └─────────────────────────────────────────────────────────────────┘   │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                      TRIGGER LAYER (Event-based)                        │ │
│  │                                                                         │ │
│  │   ⏰ TimerTrigger              📍 LocationTrigger                       │ │
│  │   • 30 นาทีหลังถึงร้าน          • ถึงที่ทำงาน                            │ │
│  │   • "ร้านนี้เป็นไงบ้าง?"        • ถึงบ้าน                                │ │
│  │                                                                         │ │
│  │   🔋 ChargingTrigger           🌅 MorningTrigger (6:00)                 │ │
│  │   • เสียบชาร์จ = จบวัน          • แจ้งเตือนเช้า                          │ │
│  │   • เริ่ม ManagerSummary       • สุขภาพ + ตารางวัน                       │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                 BACKGROUND LAYER (จบวัน/ตอนชาร์จ)                       │ │
│  │                                                                         │ │
│  │   Input: English chat logs (from Secret Chat) +                         │ │
│  │          English diary translations (from TranslatorWorker)             │ │
│  │                                                                         │ │
│  │   ┌─────────────────────────────────────────────────────────────────┐  │ │
│  │   │              ManagerSummaryStrategy (Orchestrator)              │  │ │
│  │   │                                                                  │  │ │
│  │   │  1. รวม English logs ทั้งวัน                                     │  │ │
│  │   │  2. วิเคราะห์ pattern + extract insights                         │  │ │
│  │   │  3. Dispatch ไปยัง Specialists                                   │  │ │
│  │   └─────────────────────────────────────────────────────────────────┘  │ │
│  │                              │                                          │ │
│  │           ┌──────────────────┼──────────────────┐                       │ │
│  │           ▼                  ▼                  ▼                       │ │
│  │   ┌─────────────┐   ┌─────────────┐   ┌─────────────┐                  │ │
│  │   │HealthDoctor│   │FactWorker   │   │CalendarWork │                  │ │
│  │   │             │   │             │   │             │                  │ │
│  │   │ • period    │   │ • fav place │   │ • predict   │                  │ │
│  │   │ • symptoms  │   │   KidsHouse │   │   events    │                  │ │
│  │   │ • track 2-5d│   │ • fruit salad│  │   2-5 days  │                  │ │
│  │   └─────────────┘   └─────────────┘   └─────────────┘                  │ │
│  │          │                 │                  │                         │ │
│  │          ▼                 ▼                  ▼                         │ │
│  │   ┌─────────────────────────────────────────────────┐                  │ │
│  │   │           💾 RAG Storage (SQLite, English)       │                  │ │
│  │   │  • health_facts    • favorite_places             │                  │ │
│  │   │  • preferences     • scheduled_reminders         │                  │ │
│  │   │  • english_chat_log (from Secret Chat)           │                  │ │
│  │   └─────────────────────────────────────────────────┘                  │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                    NOTIFICATION LAYER (Proactive)                       │ │
│  │                                                                         │ │
│  │   🌅 Morning (6:00)              📱 Widget                              │ │
│  │   ┌─────────────────────┐       ┌─────────────────────┐                │ │
│  │   │ สวัสดีตอนเช้าค่ะ ฟุกิ  │       │ 📅 วันนี้:           │                │ │
│  │   │ อาการเป็นไงบ้างคะ?  │       │ • ติดตามอาการ       │                │ │
│  │   │ วันนี้ไม่มีนัดหมาย    │       │ • ไม่มีนัดหมาย       │                │ │
│  │   └─────────────────────┘       └─────────────────────┘                │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  TOKEN BUDGET (per exchange):                                                │
│                                                                              │
│  Fast path (rule-based จับ intent ได้):                                      │
│  🔬 PreClassify: 0 calls (skipped)                                          │
│  🎭 Face LLM:    1 call  (ตอบ user พร้อม context hint)                      │
│  🤫 Secret Chat: 0 calls (ใช้ preClassify result โดยตรง)                    │
│  ─────────────────────────────────────────────────────                      │
│  Total: 1 call/exchange                                                     │
│                                                                              │
│  Fallback (rule-based ไม่จับ intent):                                        │
│  🔬 PreClassify: 1 call  (language-agnostic intent + English summary)       │
│  🎭 Face LLM:    1 call  (ตอบ user พร้อม [INTENT:...] hint)                 │
│  🤫 Secret Chat: 0 calls (ใช้ preClassify result โดยตรง)                    │
│  ─────────────────────────────────────────────────────                      │
│  Total: 2 calls/exchange (เท่าเดิม แต่ Face รู้ intent ก่อนตอบ)             │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘


─────────────────────────────────────────────────────────────┐
│                   SmartPreprocessor                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   User Message: "นัดหมอพรุ่งนี้ ฉันเป็นเมนด้วย"                │
│                         │                                    │
│        ┌────────────────┼────────────────┐                  │
│        │                │                │                  │
│        ▼                ▼                ▼                  │
│   ┌─────────┐    ┌───────────┐    ┌────────────┐           │
│   │FactWork │    │CalendarWk │    │HealthDoc  │           │
│   │ 0 tok   │    │ 0 tok     │    │ 0 tok     │           │
│   └─────────┘    └───────────┘    └────────────┘           │
│        │                │                │                  │
│        ▼                ▼                ▼                  │
│   ┌─────────────────────────────────────────────────────┐  │
│   │              WorkerResults                          │  │
│   │ facts: [], events: [หมอ], health: [period]         │  │
│   └─────────────────────────────────────────────────────┘  │
│                         │                                    │
│        ┌────────────────┘                                    │
│        ▼                                                     │
│   [Fast Path Search] SQL LIKE '%หมอ%', '%เมน%'               │
│   → เจอ entry เก่า? → เพิ่มใน context                        │
│                         │                                    │
│                         ▼                                    │
│   ┌─────────────────────────────────────────────────────┐  │
│   │              Lean Context Builder                    │  │
│   │ [Name:ฟุกิ][Health:Period:0d][Cal:หมอ,พรุ่งนี้]       │  │
│   │ [Context] U:...|H:...|U:...|H:...                   │  │
│   │ [Recent] Full Thai                                   │  │
│   │ [Found] entry: "ไปหาหมอ 3 เดือนก่อน..."              │  │
│   └─────────────────────────────────────────────────────┘  │
│                         │                                    │
│                         ▼                                    │
│                    Gemma 3 1B (Face)                         │
│                         │                                    │
│                         ▼ (async, หลังตอบ user)              │
│                    Secret Chat                               │
│                    → English log                             │
│                    → Big Manager dispatch                    │
│                                                              │
└─────────────────────────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────────┐
│                      TriggerService                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   ┌─────────────┐    ┌─────────────┐    ┌─────────────────────┐ │
│   │TimerTrigger │    │ChargingTrig │    │ManagerSummaryStrat  │ │
│   │             │    │             │    │                     │ │
│   │ • 30m ถึงร้าน │    │ • จบวัน     │    │ • วิเคราะห์ pattern │ │
│   │ • เช้า 6 โมง  │    │ • Morning   │    │ • Health insights  │ │
│   │ • Health    │    │ • Health    │    │ • Dispatch workers  │ │
│   └─────────────┘    └─────────────┘    └─────────────────────┘ │
│           │                │                      │              │
│           └────────────────┼──────────────────────┘              │
│                            ▼                                     │
│                  ┌─────────────────────┐                        │
│                  │  RAG Storage        │                        │
│                  │ (English — from     │                        │
│                  │  Secret Chat +      │                        │
│                  │  TranslatorWorker)  │                        │
│                  └─────────────────────┘                        │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘