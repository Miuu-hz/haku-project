# Haku — Private Life OS: Features Roadmap

> อัปเดตล่าสุด: 2026-05-11
> เรียงตามวัตถุประสงค์และที่มาของโปรเจกต์

---

## 🎯 วัตถุประสงค์และที่มา

### ปัญหา 3 ข้อที่ Haku แก้

| # | ปัญหา | ที่มา |
|---|-------|-------|
| 1 | **Privacy Leaks from Cloud AI** | ChatGPT / Gemini ส่งข้อมูลส่วนตัวออก server — ผู้ใช้ไม่รู้ว่าข้อมูลไปไหน |
| 2 | **Passive AI (Prompt Burden)** | AI รอรับ prompt — ผู้ใช้ต้องรู้จักถามเองตลอด แทนที่จะให้ AI ช่วยก่อน |
| 3 | **Data Sovereignty** | Big Tech ผูกขาดข้อมูลชีวิตผู้ใช้ ไม่มีทางเลือกที่ privacy-first จริงๆ |

### เป้าหมาย 3 ข้อ

| # | เป้าหมาย | ผลลัพธ์ |
|---|---------|---------|
| 1 | **Deep Tech** — Hybrid SLM on NPU | On-device AI ที่เร็ว / แม่น / ทำงาน offline ได้ 100% |
| 2 | **B2B Application** — Team Delegation Protocol | Haku ต่อ Haku โดยไม่ผ่าน central server |
| 3 | **Data Sovereignty** — Haku OS | ผู้ใช้เป็นเจ้าของข้อมูลตัวเองอย่างแท้จริง |

### Business Model (Razor & Blades)

```
Freemium (Core ฟรี — ขยายฐาน user)
  ↓
B2C: AI Personas + Skill Modules (In-App Purchase)
  ↓
B2B: Team Delegation Protocol (Subscription)
  ↓
Vision: Haku OS / Launcher (National Infrastructure)
```

---

## 🗺️ Phase Map — เรียงตามวัตถุประสงค์

| Phase | ชื่อ | แก้ปัญหา / Goal | สถานะ |
|-------|------|----------------|--------|
| **1** | Privacy Core (MVP) | ปัญหา 1 — Privacy Leaks | ✅ Done |
| **2** | Proactive Intelligence | ปัญหา 2 — Passive AI | 🟡 ~85% Done |
| **3** | B2C Monetization | Goal 1+2 — Revenue + Stickiness | 🔴 Planned |
| **4** | Analytics & Deep Personalization | Goal 1 — AI รู้จักคุณในระดับลึก | 🟡 ~30% Done |
| **5** | B2B — Agent Protocol | Goal 2+3 — B2B + Data Sovereignty | 🔴 Planned |
| **6** | Haku OS Vision | Goal 3 — National Impact | 💡 Concept |

---

---

## 🏗️ Infrastructure: On-Device AI Stack

> รองรับทุก Phase — ฐานที่ทุก feature ต้องพึ่ง

### ✅ LiteRT-LM Migration (เสร็จแล้ว)

> เปลี่ยน runtime จาก MediaPipe (deprecated) → **LiteRT-LM v0.10.0**

- [x] ลบ `MediaPipeLLMBridge.kt` (deprecated, reflection-based)
- [x] สร้าง `LiteRTLMBridge.kt` — clean API, stateful Conversation + KV cache
- [x] อัพเดท `build.gradle` — swap `mediapipe:tasks-genai` → `litertlm-android:0.10.0`
- [x] อัพเดท `MainActivity.kt` — ใช้ `LiteRTLMBridge` + `generateTurn` + `resetConversation`
- [x] `LiteRTLLMProvider.generateTurn()` — stateful KV cache per chat session
- [x] `PromptBuilder.buildSystemInstruction()` + `buildUserTurn()` — แยก system vs user turn
- [ ] ทดสอบ build + รันบน device จริง
- [ ] Download `.litertlm` model format จาก HuggingFace (Gemma 3 1B)

**MethodChannel ที่รองรับ:**
```
loadModel(modelPath, maxTokens, systemInstruction?) → bool
generate(prompt)                                    → String  [stateless, one-shot]
generateTurn(prompt)                                → String  [stateful, KV cache]
resetConversation()                                 → null
setSystemInstruction(instruction?)                  → null
unloadModel()                                       → null
isModelLoaded()                                     → bool
getModelInfo()                                      → Map { hasActiveSession }
```

**Model Support:**
```yaml
current:
  model: Gemma 3 1B (.litertlm)
  size: ~600 MB
  context: ~4096 tokens (เพิ่มจาก 2048)

roadmap:
  model: Gemma 4 E2B (2-bit ~1.5GB) หรือ E4B (4-bit ~4GB)
  context: 128K tokens
  new_features: Thinking Mode, Function Calling native
```

---

### 🗓️ FunctionGemma 270M — Intent Dispatcher (Planned)

> แทน PreClassify LLM (Gemma 3 1B) ด้วย 270M ที่ specialized กว่า

```
User Message
  ↓ SmartPreprocessor (rule-based, 0 LLM)
  ↓ (intent=general)
FunctionGemma 270M (~288 MB) — โหลดค้างไว้ใน RAM ตลอด
  → function call: log_mood / create_event / search / ...
  ↓
Gemma 3 1B (Face) — ตอบภาษาธรรมชาติ
```

- [ ] Download FunctionGemma 270M `.litertlm` จาก HuggingFace
- [ ] สร้าง `FunctionLLMBridge.kt` — Engine แยกสำหรับ FunctionGemma
- [ ] ออกแบบ ToolSet สำหรับ Haku (log_entry, create_event, set_reminder, search_rag)
- **Dependency:** LiteRT-LM migration เสร็จก่อน

---

## 🎨 Infrastructure: Haku Crystal Design System

> UI/UX ทั้งแอปเป็น glass-morphic "aurora crystal" design

**Design Tokens:**
- Primary Cyan: `#3CDFFF` · Deep Navy: `#0A1F4D` · Lavender: `#9B7CB6`
- Glass Card: `BackdropFilter.blur(20)` + translucent white + inner highlight
- Caustic Shimmer: 105° diagonal gradient sweep, 4s loop

| Screen | สถานะ |
|--------|--------|
| `main.dart` — App theme | ✅ |
| `main_navigation_screen.dart` — Curved nav | ✅ |
| `chat_screen.dart` — Dark scaffold + crystal accent | ✅ |
| `home_screen.dart` — Aurora blob + glass cards | ✅ |
| `onboarding_screen.dart` | ✅ |
| `quick_actions_fab.dart` | ✅ |
| `settings_screen.dart` | ❌ ยังไม่ migrate |

**Widgets:**
- [x] `CausticShimmer` — Reusable glass shimmer `CustomPainter`
- [x] `FlutterMap` mini map ใน `view_entry_screen.dart` (OpenStreetMap, 200px)

**Rules:** ไม่ใช้ emoji ใน user-facing string ยกเว้น source comments

---

---

## Phase 1: Privacy Core — MVP ✅

> **แก้ปัญหา 1:** Privacy Leaks from Cloud AI
> ทุก feature ในเฟสนี้ทำงาน on-device ล้วน ไม่มี network call สำหรับข้อมูล user

- [x] SQLite + SQLCipher Encryption (ข้อมูลทุกอย่างเข้ารหัส at rest)
- [x] Biometric Lock (Auto-lock 1-10 min)
- [x] Basic Chat UI — Haku Crystal glass-morphic design
- [x] Android Widgets (Home screen 4×2 / 4×3)
- [x] Data Export (JSON, Markdown, CSV, Backup)
- [x] Profile Editor

---

---

## Phase 2: Proactive Intelligence

> **แก้ปัญหา 2:** Passive AI — AI ทำงานก่อน user ถาม

---

### 2.1 On-Device LLM ✅

**สถานะ:** เสร็จแล้ว (LiteRT-LM migration ✅)

- [x] Gemma 3 1B ผ่าน LiteRT-LM (`.litertlm` format)
- [x] Stateful Conversation — KV cache ข้าม request (ไม่ re-encode history ทุกครั้ง)
- [x] Auto-unload หลัง 5 นาทีไม่ใช้งาน (ประหยัดแบต)
- [x] Lazy loading — โหลดเมื่อ generate() ครั้งแรก
- [x] Two-Stage Architecture:
  - Stage 1 (Face): ตอบสนทนาธรรมชาติ ทุกภาษา
  - Stage 2 (Secret Chat): classify intent + dispatch งาน async

---

### 2.2 Cloud LLM — Dev/Fallback Mode ✅

> **หมายเหตุ:** Cloud provider ขัดกับ Objective 1 (Privacy-first)
> ใช้เฉพาะ development mode / ผู้ใช้ที่ต้องการ fallback อย่างชัดเจน — ไม่ใช่ default

**สถานะ:** เสร็จแล้ว

- [x] Gemini Flash (Google) — free tier
- [x] Claude Haiku (Anthropic)
- [x] GPT-4o-mini (OpenAI)
- [x] **OpenRouter** — key เดียวเข้าถึงทุก model, default: `google/gemini-2.0-flash-001`
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

```yaml
vector_search:
  method: TF-IDF like embedding + Cosine Similarity
  storage: SQLite BLOB (sqflite)
  fallback: Keyword search
  note: ไม่ต้องโหลด embedding model แยก
```

---

### 2.4 SmartPreprocessor + Workers ✅

**สถานะ:** เสร็จแล้ว (7 workers + Brain-Dump Auto-Sorter)

> ใช้ rule-based (0 LLM tokens) ก่อนส่งเข้า LLM — Proactive Detection

- [x] **FactWorker** — จดจำชื่อ, ชอบ/ไม่ชอบ, อาชีพ, เป้าหมาย, สถานที่
- [x] **CalendarWorker** — ตรวจจับนัดหมายจากข้อความไทย+English (regex allMatches → หลาย events)
  - day-first, มีนัด-first, พรุ้งนี้ typo, เช้า/เย็น/กลางคืน suffix
- [x] **ReminderWorker** — ตรวจจับการเตือน + frequency (once/daily/weekly/monthly)
- [x] **GoalWorker** — ตรวจจับเป้าหมาย + ติดตาม progress
- [x] **HealthDoctor** — ตรวจจับ period, อาการปวด, แพ้, ยา
- [x] **TranslatorWorker** — batch Thai→English แบบ background (ตอนชาร์จ) สำหรับ RAG
- [x] **WeatherWorker** — detect weather keywords → fetch Open-Meteo API → inject context
- [x] Search intent detection + Quick action (ทักทาย, ถามชื่อ)
- [x] English Past-Data Patterns (`did/have i ever`, `last time i ...`)
- [x] Conditional RAG Fallback (SQL miss → RAGService semantic search)
- [x] `_extractPastFilters()` — date range + mood filters (Thai + English)

**Brain-Dump Auto-Sorter:**
> "พรุ่งนี้บ่ายโมงประชุม อ้อ เตือนโอนค่าไฟด้วย แล้วตอนเย็นรับลูก"
> → CalendarWorker + ReminderWorker แยก 3 items อัตโนมัติ (0 LLM)

- [x] `buildBrainDumpSummary()` — summary card "✅ จดได้ 3 รายการ: 📅 ประชุม | ⏰ ค่าไฟ | 📅 รับลูก"

---

### 2.5 Secret Chat + Context Architecture ✅

**สถานะ:** เสร็จแล้ว

**Flow:**
```
User msg
  → SmartPreprocessor (0 LLM) — rule-based fast path
     ├─ จับได้ (schedule/remind/etc.) → skip preClassify
     └─ intent=general → preClassify LLM (language-agnostic)
         → inject [INTENT:SCHEDULE:ศาลากลาง,2026-02-28,09:00] ใน context
  → Face LLM (รู้ intent → ตอบถูกต้อง)
  → [async] logExchange() → EnglishLogEntry → SharedPreferences
  → ManagerDispatchService → execute urgent actions
```

- [x] `SecretChatService.preClassify()` → `PreClassifyResult {intent, summaryEn, title, date, time}`
- [x] `logExchange(preClassifyResult:)` — reuse PreClassify → 0 extra LLM call
- [x] `TagContextService` — keyword search past entries → inject context ก่อน Face LLM
- [x] LeanContextService (legacy) — ยังคงไว้สำหรับ Gemma 3 1B context window เล็ก

---

### 2.6 Entry Summarization ✅

- [x] สรุป Entry เดี่ยว (บันทึกยาว → สั้น)
- [x] สรุปหลาย Entries (สรุปวัน/สัปดาห์)
- [x] Extract Key Insights
- [x] Sentiment Analysis (rule-based + mood)
- [x] Fallback เมื่อไม่มี LLM

---

### 2.7 AI Auto-Scheduling ✅

- [x] SchedulerService — ดึง event จากข้อความธรรมชาติ (LLM extraction)
- [x] CalendarWorker — regex detection วัน/เวลาไทย
- [x] Native Calendar API (MethodChannel → `SchedulerBridge.kt` → CalendarContract)
- [x] Auto reminder 15 นาทีก่อนนัด
- [x] `getCalendarEvents()` — อ่าน events จาก Android Calendar
- [x] `checkConflicts()` — ตรวจ overlap ก่อน create → `ConflictResult`
- [x] `createCalendarEventWithCheck()` — warn ถ้าชนนัด → `ScheduleResult`
- [ ] Google Calendar sync (Mock Mode พร้อม, real API ยังไม่เปิด)
- [ ] Time block อัตโนมัติ — จัด slot ว่างให้พอดีวัน (future)

---

### 2.8 Proactive Triggers ✅

- [x] Time-based (09:00 เช้า, 12:00 เที่ยง, 17:00 เย็น, 22:00 ก่อนนอน)
- [x] Location-based (revisit 200m, 2+ hr gap)
- [x] No-entry reminder
- [x] Battery-optimized: เช็คทุก 5 นาที
- [x] Notification Service + Quick Reply จาก notification
- [x] Deep link เข้าแอปพร้อม context
- [ ] Proactive Voice Alert (TTS) — ยังไม่ implement

---

### 2.9 Background Processing (Charging-Deferred) ✅

- [x] `BatteryAwareService` — ตรวจจับ charging/discharging
- [x] `DeferredTaskService` — priority queue + auto-process ตอนชาร์จ
- [x] `ManagerSummaryStrategy` — วิเคราะห์ health, behavior, preferences
- [x] `BackgroundTaskHandlers` — wire ManagerSummary + reindex vectors
- [x] Energy Profile (ultraSaver / batterySaver / balanced / performance)

---

### 2.10 Web Search Integration ✅

- [x] SearXNG JSON API — 4 public instances fallback (ไม่ต้อง API key)
- [x] Jina AI Reader — `GET https://r.jina.ai/{url}` → clean markdown
- [x] English + Thai search patterns
- [x] Location-aware Search (Google Places API, BYOK)
- [x] No-results fix — return `''` แทน Thai string (ป้องกัน hallucinate)
- [x] 6h cache + 2s rate limit

---

### 2.11 Work Day Planner ✅

- [x] Morning check-in (09:00) — agenda วันนี้ใน notification
- [x] Evening summary (20:00) — สรุปนัดวันนี้
- [x] WorkManager time triggers — ยิงแม้แอพปิด
- [x] Goal priority (`GoalWorker`)

**Smart Sleep & Auto-Alarm:**
```
เสียบชาร์จหลัง 22:00
  → ChargingTrigger → getCalendarEvents(tomorrow)
  → คำนวณ alarmTime = earliestEvent - 1.5hr
  → SchedulerBridge.setAlarm() → Android AlarmClock
  → Notification: "พรุ่งนี้ประชุม 8 โมง ตั้งปลุก 6:30 ไว้ให้แล้ว"
```

- [x] `SchedulerBridge.setAlarm()` — Android `AlarmClock.ACTION_SET_ALARM`
- [x] `calculateAlarmFromTomorrow()` — safety guard (ไม่ปลุกก่อนตี 4)
- [x] ChargingTrigger integration — bedtime 22:00
- [ ] Settings: prep time (default 1.5 ชม.)

---

### 2.12 Samsung Now Brief Dashboard ✅

> HomeScreen time-adaptive cards แบบ Samsung Now Brief

- [x] `_HeroBriefCard` — time-adaptive accent (amber/blue/pink/purple)
- [x] `_CalendarCard` — events วันนี้
- [x] `_GoalsCard` — active goals + circular progress
- [x] `_StreakCard` — focus streak
- [x] `WeatherService` (Open-Meteo, ฟรี) — 3-day forecast, daily cache

---

### 2.13 Anti-Procrastination Bot 🟡

**สถานะ:** ~70% done

- [x] `FocusTimerService` — Pomodoro state machine (25/5/15 min)
- [x] `StreakService` — นับวันต่อเนื่อง, milestone (7/30/100 วัน)
- [x] Goal-linked — `GoalWorker.logProgress()` อัตโนมัติเมื่อเสร็จ
- [x] `FocusTimerScreen` — UI: timer ring, pomodoro dots, goal picker, streak badge
- [x] FAB shortcut — เข้าถึงจาก Home Screen
- [x] Break reminder notification
- [ ] Deep Work session — mute notifications ระหว่าง focus (post-MVP)

---

### 2.14 Chat Persistence ✅

- [x] `ChatMessage.toJson()` / `fromJson()` — serialize 50 ข้อความล่าสุด
- [x] `ChatNotifier._loadHistory()` / `_saveHistory()` — async, ไม่บล็อก UI
- [x] ปุ่ม "ล้างประวัติแชท" + confirm dialog + clear everything (LeanContext + SecretChat)

---

### 2.15 Meeting Pre-Flight Check 🔴

**สถานะ:** ยังไม่ implement
**ความยาก:** ⭐⭐

> 15 นาทีก่อนถึงนัด → Haku ดึง RAG → สรุปบริบทให้อ่านก่อนเข้าประชุม

```
CalendarWorker มีนัด → schedulePreFlight(event)
  → TimerTrigger ยิง (event.time - 15 min)
  → RAG search ด้วย event.title + attendees
  → Notification "📋 เตรียมพร้อมก่อนนัด: [ชื่อนัด]"
  → Pre-Flight Card ใน ChatScreen
```

- [ ] `TriggerType.preFlightCheck` + `schedulePreFlightReminders()`
- [ ] RAG search ด้วย context ของ event
- [ ] Pre-Flight Card UI — recap entries + facts ที่เกี่ยวข้อง
- **LLM usage:** 1 call

---

### 2.16 Thought Catcher — Voice Input 🔴

**สถานะ:** ยังไม่ implement (รอ STT)
**ความยาก:** ⭐⭐⭐⭐

> กด mic → พูด → บันทึกอัตโนมัติ → SmartPreprocessor เซฟทันที (0 LLM)

- [ ] เลือก STT: **Whisper-Tiny on-device** (privacy-safe) หรือ Google Speech (cloud)
- [ ] `SpeechToTextService` wrapper
- [ ] FAB mic button + recording UI
- [ ] Confirmation snackbar: "จดแล้ว: [ชื่อนัด/reminder]"
- **Priority note:** ควรใช้ Whisper on-device เพื่อรักษา Objective 1

---

### 2.17 Focus Goal HUD — Floating Widget 🔴

**สถานะ:** ยังไม่ implement
**ความยาก:** ⭐⭐⭐⭐

> Pomodoro timer ลอยบนหน้าจอ — Android Overlay (SYSTEM_ALERT_WINDOW)

- [ ] `FloatingHUDService` — Android Foreground Service + WindowManager overlay
- [ ] MethodChannel: Flutter ↔ HUD (start/stop/update)
- [ ] Floating Widget: compact, draggable
- **LLM usage:** 0

---

### 2.18 Contextual Memory Canvas 🔴

**สถานะ:** ยังไม่ implement
**ความยาก:** ⭐⭐⭐⭐⭐

> Mind Map แสดงความเชื่อมโยงระหว่าง Calendar, Facts, Diary จาก vector clustering

- [ ] `VectorGraphService` — cosine similarity clustering → adjacency graph
- [ ] `MemoryCanvasScreen` — custom `CustomPainter` Mind Map
- [ ] Cross-worker data aggregation + filter by date / category
- **LLM usage:** 0 (visualization only)

---

### 2.19 Thinking Mode ✅

**สถานะ:** เสร็จแล้ว (2026-05-11)

- [x] parse `<thinking>...</thinking>` จาก model response ด้วย RegExp
- [x] `_ThinkingSection` — collapsible widget เหนือ reply จริง (default collapsed)
- [x] แสดงเฉพาะเมื่อ model ส่ง thinking tags มา (Gemma 4 / reasoning models)

---

### 2.20 Mood Trend Chart ✅

**สถานะ:** เสร็จแล้ว (2026-05-11)

- [x] `_MoodTrendCard` ใน home_screen — แสดงถ้ามี ≥2 วันที่มี mood data
- [x] `_MoodSparklinePainter` — gradient fill + line + dots (custom painter, ไม่ใช้ library)
- [x] avg mood + trend icon (↑ / → / ↓)

---

### 2.21 Benchmark Tab ✅

**สถานะ:** เสร็จแล้ว (2026-05-11)

- [x] Section "ทดสอบประสิทธิภาพโมเดล" ใน Settings
- [x] รัน `generate()` 3 ครั้ง → avg ms + token/s estimate
- [x] Dart Stopwatch (ไม่ต้องแก้ Kotlin)

---

---

## Phase 3: B2C Monetization

> **Goal 1+2:** Revenue + User Stickiness
> หัวใจของ Business Model — "Blades" ใน Razor & Blades

---

### 3.1 AI Personas 🔴 NEW

**สถานะ:** ยังไม่ implement
**ความยาก:** ⭐⭐ (leverage system instruction ที่มีอยู่)
**Business:** IAP gate สำหรับ premium personas

> เปลี่ยน "บุคลิก" ของ Haku ผ่าน system instruction — Strict Coach, Empathetic Friend, No-Filter Advisor ฯลฯ

**Personas (ตัวอย่าง):**
| Persona | คำอธิบาย | Tier |
|---------|----------|------|
| **Haku (Default)** | ผู้ช่วยส่วนตัวที่สมดุล อบอุ่น | ฟรี |
| **Coach** | กระตุ้น, ตรง, ไม่ยอมรับข้อแก้ตัว | IAP |
| **Empath** | รับฟัง, เข้าใจ, ไม่ตัดสิน | IAP |
| **Advisor** | วิเคราะห์ข้อมูล, ตรง, ไม่เกรงใจ | IAP |
| **[User Custom]** | ผู้ใช้เขียน system prompt เอง | IAP Premium |

**Architecture:**
```
PersonaService (Dart singleton)
  ├─ loadPersonas() → List<Persona> (assets/personas/*.json)
  ├─ activePersona → Persona
  └─ getSystemInstruction() → String (inject ใน LiteRTLMProvider)

_startNewLiteRTSession() (chat_screen.dart)
  → provider.setSystemInstruction(PersonaService().getSystemInstruction())
```

**งานที่ต้องทำ:**
- [ ] `Persona` model — name, description, systemInstruction, tier (free/paid)
- [ ] `PersonaService` singleton — load from `assets/personas/`, persist active via SharedPreferences
- [ ] `PersonaPickerScreen` — grid UI: persona cards + lock icon สำหรับ paid
- [ ] IAP integration (RevenueCat หรือ native Billing) — unlock paid personas
- [ ] `buildSystemInstruction()` ใน `PromptBuilder` — inject active persona
- [ ] Settings > AI Persona tile → PersonaPickerScreen
- **LLM usage:** 0 extra (แค่ swap system instruction)

---

### 3.2 Skills System 🔴 (Feature 5 จาก Gallery)

**สถานะ:** ยังไม่ implement
**ความยาก:** ⭐⭐⭐⭐
**Business:** IAP Skill Modules

> LLM เรียก "Skill" เพื่อทำ task เฉพาะทาง — Mood Tracker, Coach, Kitchen Adventure ฯลฯ

**แนวคิดจาก Google AI Edge Gallery:**
```
LLM → loadSkill(name) → runJs(skillScript) → JS returns JSON → UI renders
```

**Haku Skill Format (SKILL.json):**
```json
{
  "name": "mood-tracker",
  "description": "Track and visualize mood patterns",
  "trigger": ["mood", "อารมณ์", "รู้สึก"],
  "entrypoint": "assets/skills/mood_tracker/index.html",
  "tier": "free"
}
```

**Skills ที่เหมาะกับ Haku:**
| Skill | ความเกี่ยวข้อง | Tier |
|-------|--------------|------|
| mood-tracker | core feature | ฟรี |
| focus-coach | productivity | IAP |
| kitchen-adventure | food logging | IAP |
| health-dashboard | health tracking | IAP |
| qr-code | utility | ฟรี |

**Process:**
1. สร้าง `SkillManager` (Dart) — index skills จาก `assets/skills/`
2. สร้าง `SkillWebViewScreen` — sandboxed WebView + MethodChannel bridge
3. เพิ่ม tool: `loadSkill` ใน function calling chain
4. เขียน Skill format spec + packaging guide
5. Port skills จาก Gallery (mood-tracker ก่อน)

**Privacy Note:** WebView ต้อง sandbox ไม่ให้เข้า network (ยกเว้น skill ที่ explicit opt-in)
**Dependency:** Function Calling (3.3)

---

### 3.3 Native Function Calling 🔴 (Feature 6 จาก Gallery)

**สถานะ:** ยังไม่ implement
**ความยาก:** ⭐⭐⭐⭐⭐
**Dependency:** Gemma 4 E2B/E4B บนเครื่อง

> LLM เรียก device functions ผ่าน structured tool calls — แทน regex intent dispatch

**HakuToolSet:**
```kotlin
// HakuToolSet.kt
- log_entry(content: String, mood: Int?, location: String?)
- create_event(title: String, date: String, time: String, location: String?)
- set_reminder(message: String, datetime: String)
- search_rag(query: String)
- get_weather()
- load_skill(name: String)   // เชื่อมกับ Skills System
```

**ข้อดีเทียบ current:**
| ปัจจุบัน | Function Calling |
|---------|-----------------|
| regex → intent → dispatch | LLM เรียก tool ตรง |
| error-prone Thai parsing | structured args |
| 2-stage (Face + SecretChat) | 1-stage |
| ขยาย intent = แก้ regex | เพิ่ม tool definition |

**Process:**
1. เพิ่ม function calling ใน `LiteRTLMBridge.kt` (LiteRT-LM ToolProvider API)
2. สร้าง `HakuToolSet.kt` — define + register tools
3. สร้าง `HakuTools.dart` — Dart side receives + dispatches tool call results
4. แทนที่ `ManagerDispatchService` ด้วย tool-based dispatch
5. ทดสอบ: "สร้างนัดพรุ่งนี้ 9โมงเช้า" → LLM เรียก `create_event()` โดยตรง

---

---

## Phase 4: Analytics & Deep Personalization

> **Goal 1:** AI ที่รู้จักคุณในระดับลึก — pattern recognition จากชีวิตจริง

---

### 4.1 Hidden Correlation ✅

**สถานะ:** Done — `lib/services/correlation_service.dart`

> "73% ของวันอารมณ์ไม่ดี มักเกิดขึ้นในวันที่มีเครียด"

- [x] Co-occurrence analysis + Lift scoring (pure Dart, 0 LLM)
- [x] Signals: กาแฟ, นอนดึก, เครียด, ประชุม, ปวดหัว, ออกกำลังกาย
- [x] Outcomes: lowMood (≤2), fatigue, highMood (≥4)
- [x] `_InsightCard` ใน home_screen — confidence chip + tinted message

---

### 4.2 Social Battery Forecast ✅

**สถานะ:** Done — `lib/services/social_battery_service.dart`

- [x] Energy Cost Table: ประชุม -10, นอน +10, คนเดียว +12
- [x] Cumulative score 14 วัน → level 0-100
- [x] `_SocialBatteryCard` — LinearProgressIndicator + nudge message
- [ ] Push notification เมื่อ level < 30 ติดต่อกัน 3 วัน

---

### 4.3 Direct Diary — Core Memory 🔴

**สถานะ:** ยังไม่ implement
**ความยาก:** ⭐⭐

> "จำไว้นะ..." → AI จัดเก็บระดับพิเศษ → ดึงมาให้กำลังใจเมื่อ mood ต่ำ

- [ ] SmartPreprocessor regex: "จำไว้", "จดลงไดอารี่สำคัญ" → `DetectedIntent.directDiary`
- [ ] `addFact(category: 'core_memory')` + weight boosting ใน RAG
- [ ] `DirectDiaryScreen` — CRUD แยกตามหัวข้อ
- [ ] Evening Briefing: ถ้า mood ต่ำ → ดึง positive core_memory
- **LLM usage:** 1 call (Face only)

---

### 4.4 Direct Table — Auto-Tracker 🔴

**สถานะ:** ยังไม่ implement
**ความยาก:** ⭐⭐⭐

> "ความดันเช้านี้ 120 80" → auto-log → MiniChart trend ทันที

- [ ] SQLite: `tracker_tables` + `tracker_entries`
- [ ] `TrackerWorker` (rule-based) — numeric extraction + table matching
- [ ] `DirectTableScreen` + `MiniChartWidget`
- [ ] Export: สรุปตารางเป็น text/image
- **LLM usage:** 1 call (Face) + 1 call (summary query)

---

### 4.5 Music & News Context 🔴

**สถานะ:** ยังไม่ implement

- [ ] Android Notification Listener → ชื่อเพลงจาก Spotify/YT Music
- [ ] RSS Feed สรุปข่าว
- [ ] Morning Briefing integration

---

### 4.6 Proactive Voice Alert (TTS) 🔴

**สถานะ:** ยังไม่ implement

```yaml
tts_engine:
  android: Google TTS (pre-installed) หรือ Piper-TTS (~50MB on-device)
  ios: Siri Announce Notifications
```

- [ ] TTS wrapper service
- [ ] Personalized alert messages ผ่าน LLM
- **Privacy note:** Piper-TTS on-device preferred (Objective 1)

---

### 4.7 Shadow Mode — AI Writing Style 🔴

**สถานะ:** ยังไม่ implement

> AI เรียนรู้สไตล์การเขียนของคุณ → Draft คำตอบเหมือนคุณพิมพ์เอง

- [ ] Few-shot prompting (ใช้ข้อความเก่าเป็น example)
- [ ] หรือ LoRA Fine-tune on-device (Gemma base)

---

### 4.8 AR Memory Anchor 💡

**สถานะ:** Concept — feasibility ยังไม่ชัด

> ชี้กล้องไปที่สถานที่ → Haku บอกว่าเคยมีความทรงจำอะไรที่นี่

---

---

## Phase 5: B2B — Agent Protocol + Automation

> **Goal 2+3:** B2B Revenue + Data Sovereignty
> ทุก feature ในเฟสนี้ต้องไม่มี central server ที่เห็นข้อมูล

---

### 5.1 Agent-to-Agent Protocol 🔴 NEW

**สถานะ:** ยังไม่ implement
**ความยาก:** ⭐⭐⭐⭐⭐
**Business:** B2B Subscription — Team Delegation Protocol

> Haku ของ User A คุยกับ Haku ของ User B โดยตรง — ไม่มี central server เห็นข้อมูล

**ปัญหาที่แก้:**
- ทีมงานต้องการ schedule meeting โดยไม่เปิดเผย calendar ส่วนตัวให้คนอื่นเห็น
- ปัจจุบัน: ต้องส่ง calendar ให้ secretary หรือใช้ Google Calendar (data หนีออก cloud)
- Haku A2A: แค่บอก "ขอนัดกับ Bob" → Haku ของทั้งคู่เจรจากันเอง

**Architecture (Privacy-First):**
```
User A: "ขอนัดประชุม Bob วันพฤหัส บ่าย"
  ↓
Haku A (Face LLM) → function call: request_meeting(to: "bob_haku_id", ...)
  ↓ (encrypted P2P)
Haku B ได้รับ → ตรวจ Bob's free slots (local only)
  → ตอบกลับ: available_slots[] (encrypted)
  ↓
Haku A เสนอเวลา → User A confirm → Haku A สร้าง event ทั้งสองฝ่าย
```

**Transport Options (ไม่มี central server):**
| Option | ข้อดี | ข้อเสีย |
|--------|-------|---------|
| Bluetooth / WiFi Direct | offline 100% | ต้องอยู่ใกล้กัน |
| E2E Encrypted Relay (self-hosted) | ระยะไกลได้ | ต้องการ relay server (operator ไม่เห็น content) |
| Local Network (LAN) | ออฟฟิศ fast | จำกัด network เดียวกัน |

**งานที่ต้องทำ:**
- [ ] `HakuAgentIdentity` — keypair ที่เก็บใน device keystore (Keystore API)
- [ ] `AgentChannel` — encrypted message format (NaCl/libsodium)
- [ ] `MeetingNegotiationProtocol` — request / propose / confirm / decline
- [ ] Transport layer abstraction — BT / WiFi Direct / relay
- [ ] `A2AScreen` — UI: ค้นหา Haku user ใกล้เคียง + negotiation status
- [ ] Settings: B2B subscription gate + Team management
- **LLM usage:** on each device separately (ไม่มี shared LLM)

---

### 5.2 Privacy Data Transparency Screen 🔴 NEW

**สถานะ:** ยังไม่ implement
**ความยาก:** ⭐ (ง่าย แต่ USP ชัดมาก)

> "What happens on your phone, stays on your phone" — แสดงหลักฐานให้ user เห็น

**หน้า Data Transparency:**
```
📱 Stored on This Device
  ├─ 🗒️ Diary entries: 234 entries (12.3 MB)
  ├─ 🧠 AI memories: 1,247 facts
  ├─ 📅 Calendar events: 89 events
  └─ 🔒 Encrypted with: AES-256 (SQLCipher)

☁️ Network Activity (last 30 days)
  ├─ LLM calls: 0 (on-device only) ✅
  ├─ Web searches: 12 queries (DuckDuckGo/SearXNG) ℹ️
  ├─ Weather: 30 requests (Open-Meteo, no account) ℹ️
  └─ Cloud LLM: 0 calls ✅

🔍 What leaves your device
  └─ Only: anonymous weather requests, web search queries
     (no personal content, no account required)
```

**งานที่ต้องทำ:**
- [ ] `NetworkAuditService` — log outbound calls (type, domain, ไม่ log content)
- [ ] `DataInventoryService` — count entries/facts/events จาก SQLite + SharedPreferences
- [ ] `PrivacyTransparencyScreen` — UI แสดงข้อมูลทั้งหมด
- [ ] Settings > Privacy & Data tile → PrivacyTransparencyScreen
- **LLM usage:** 0 (read-only audit)

---

### 5.3 Background Geofence via WorkManager 🔴

**สถานะ:** ยังไม่ implement (Post-MVP)
**ความยาก:** ⭐⭐⭐⭐

> ทำให้ DwellTracker ทำงานได้แม้แอพปิด — WorkManager + Fused Location API

```
ปัจจุบัน: แอพเปิด → GPS poll ทุก 5 นาที ✅ / แอพปิด → ไม่มี GPS ❌
เป้าหมาย: WorkManager ยิงทุก 15 นาที → poll GPS → DwellTracker ✅
```

**Battery Impact:**
| Mode | Battery/วัน |
|------|------------|
| Foreground only (ปัจจุบัน) | ~0 (แอพปิดไม่กิน) |
| WorkManager (Phase 5.3) | ~1-2% (PRIORITY_LOW_POWER) |

**งานที่ต้องทำ (Kotlin):**
- [ ] `LocationWorker.kt` — WorkManager `CoroutineWorker` + FusedLocationProviderClient
- [ ] `DwellLogic.kt` — Haversine + dwell state machine (mirror ของ Dart side)
- [ ] `WorkManagerBridge.kt` — MethodChannel startBackgroundGeofence / stop
- [ ] Manifest: `ACCESS_BACKGROUND_LOCATION` permission

**งานที่ต้องทำ (Flutter):**
- [ ] Settings UI: toggle "Background Location Tracking" + battery impact warning
- [ ] Permission flow: Android 10+ dialog อธิบายเหตุผล

---

### 5.4 Automation Engine 🔴

**สถานะ:** Planned (mockup UI มีแล้วใน `automation_screen.dart`)

> No-code automation — Trigger → Condition → Action ไม่ต้อง run LLM ตลอดเวลา

```
[TRIGGER] ──→ [CONDITION] ──→ [ACTION]
เวลา 08:00     ถ้าพรุ่งนี้มีนัด   แจ้งเตือน "เตรียมตัว"
ชาร์จแบต       ถ้า mood < 3       ส่ง Check-in เข้าแชท
เชื่อม WiFi บ้าน  ─              เปลี่ยน ringtone
```

**Trigger Types:**
| Trigger | Android API | Battery |
|---------|-------------|---------|
| เวลาที่กำหนด | AlarmManager | ~0 |
| ทุก N นาที (min 15) | WorkManager | ต่ำ |
| เสียบ/ถอดชาร์จ | BroadcastReceiver | ~0 |
| เชื่อม WiFi SSID | BroadcastReceiver | ~0 |
| เข้า/ออกสถานที่ | Geofencing API | ต่ำ |

**Action Types:** ส่งข้อความเข้าแชท / แจ้งเตือน / ค้นหาเว็บ / บันทึก entry / เปิดหน้า

**งานที่ต้องทำ:**
- [ ] `AutomationRule` model + `AutomationEngine` service
- [ ] `TriggerRegistry` — AlarmManager / BroadcastReceiver / WorkManager bridge (Kotlin)
- [ ] Rule Builder UI — Visual block editor
- [ ] Condition evaluator — `mood < 3`, `hasEventToday`, `batteryLevel < 20`

---

---

## Phase 6: Haku OS Vision 💡

> **Goal 3:** National Impact — Data Sovereignty
> ระยะยาว — ยังเป็น concept

**Phase 6 Concept:**
- Haku Launcher — แทน Android home screen เป็น "Haku OS"
- AI Layer ระหว่าง human กับ digital world
- Thai Data Sovereignty — ข้อมูลอยู่บน device คนไทย ไม่ออก server ต่างชาติ
- Enterprise Haku — deploy บน device องค์กรที่ควบคุมโดย IT admin

---

---

## Pre-MVP Checklist (ก่อน Public Launch)

### Background Processing
- ❌ **WorkManager batch** — defer post-MVP (LLM tasks ทำ background ไม่ได้ใน Flutter isolate)

### Focus Timer
- [x] Break reminder notification ✅
- [ ] Deep Work session (mute notifications) — post-MVP

### GPS / Location
- [x] `GeofenceService` + `MVPTriggerService` (foreground only) ✅
- **ข้อจำกัด:** DwellTracker ทำงานได้เฉพาะแอพเปิดอยู่ — Phase 5.3 จะแก้

### UI / UX
- [x] Haku Crystal Design System (main, nav, chat, home, onboarding, FAB) ✅
- [x] `CausticShimmer` widget ✅
- [x] Entry Mini Map (FlutterMap, OpenStreetMap) ✅
- [ ] `settings_screen.dart` — ยังไม่ migrate เป็น Haku Crystal
