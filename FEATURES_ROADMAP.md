# Haku Features Roadmap - Proactive AI Assistant

> วางแผนฟีเจอร์ AI ตาม Phase พร้อมโมเดลที่ใช้
> อัปเดตล่าสุด: 2026-02-17



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
- B2B Monetization: Enterprises pay a subscription for the "Team Delegation Protocol" to boost productivity.

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
**สถานะ:** เสร็จแล้ว

- [x] Gemini Flash (Google) — free tier
- [x] Claude Haiku (Anthropic)
- [x] GPT-4o-mini (OpenAI)
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
**สถานะ:** เสร็จแล้ว

ใช้ rule-based (0 LLM tokens) ก่อนส่งเข้า LLM:

- [x] **FactWorker** — จดจำชื่อ, ชอบ/ไม่ชอบ, อาชีพ, เป้าหมาย, สถานที่
- [x] **CalendarWorker** — ตรวจจับนัดหมายจากข้อความไทย (regex)
- [x] **ReminderWorker** — ตรวจจับการเตือน + frequency (once/daily/weekly/monthly)
- [x] **GoalWorker** — ตรวจจับเป้าหมาย + ติดตาม progress
- [x] **HealthDoctor** — ตรวจจับ period, อาการปวด, แพ้, ยา
- [x] Search intent detection (keyword-based)
- [x] Quick action detection (ทักทาย, ถามชื่อ)

---

### 2.5 Lean Context Service ✅
**สถานะ:** เสร็จแล้ว

บีบ chat history ให้พอดี context window ของ Gemma 3 1B (~2048 tokens):

- [x] Chat 1-3: Full Thai (ไม่บีบ)
- [x] Chat 4+: Lean Syntax (ตัดคำลงท้าย, ย่อคำ, max 50 chars)
- [x] Session summaries (English, 1-line)
- [x] ผลลัพธ์: 25 คู่แชทใน ~330 tokens (เดิม 5 คู่ใน ~750 tokens)

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
- [x] Native Calendar API (MethodChannel)
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
**สถานะ:** เสร็จแล้ว

- [x] WebSearchService
- [x] SmartPreprocessor ตรวจจับ search intent อัตโนมัติ
- [x] LLM สรุปผลค้นหาเป็นคำตอบ
- [x] Intermediate "กำลังค้นหา..." message ใน UI

---

## Phase 3: Beta Testing (Insights & Analytics)

**เป้าหมาย:** วิเคราะห์ pattern ชีวิตและให้ insights

### 3.1 The Hidden Correlation
**สถานะ:** ยังไม่ implement

หาความเชื่อมโยงที่ซ่อนอยู่ในชีวิต เช่น:
> "80% ของวันที่คุณปวดหัว คือวันที่คุณดื่มกาแฟร้าน A และนอนน้อยกว่า 6 ชม."

- [ ] Multivariate correlation analysis
- [ ] Pattern matching: Food + Sleep + Mood + Health
- [ ] Insight message generation ด้วย LLM

**Note:** ManagerSummaryStrategy มี basic pattern detection อยู่แล้ว (period, fatigue) สามารถต่อยอดได้

**Technical:**
```yaml
approach: Rule-based correlation + simple statistics
# ไม่ต้องใช้ ML หนัก ใช้ frequency analysis + co-occurrence
llm: Gemma 3 1B หรือ Cloud LLM (สรุป correlation เป็นภาษาธรรมชาติ)
```

---

### 3.2 Social Battery Forecast
**สถานะ:** ยังไม่ implement

พยากรณ์ "พลังงานสังคม" และเตือนก่อน burnout

- [ ] Energy Cost Scoring สำหรับแต่ละกิจกรรม
- [ ] Cumulative score calculation
- [ ] Visual Health Bar บนหน้า Home

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
  connection:
    - Tunnel mode (API key ฝั่ง server)
    - Direct mode (API key ในแอป)

# Vector Search (สำหรับ RAG)
vector_search:
  method: TF-IDF embedding + Cosine Similarity (Dart)
  storage: SQLite BLOB
  note: ไม่ต้องโหลด embedding model แยก

# Workers (Rule-based, 0 tokens)
workers:
  - FactWorker (ชื่อ, ชอบ, อาชีพ, เป้าหมาย)
  - CalendarWorker (นัดหมาย, เวลา)
  - ReminderWorker (เตือน, ความถี่)
  - GoalWorker (เป้าหมาย, progress)
  - HealthDoctor (ประจำเดือน, อาการ, ยา, แพ้)

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
| 2 | On-Device LLM (Gemma 3 1B) | ✅ |
| 2 | Cloud LLM (Gemini/Claude/OpenAI) | ✅ |
| 2 | Smart Search / RAG | ✅ |
| 2 | SmartPreprocessor + Workers (5 ตัว) | ✅ |
| 2 | Lean Context (token compression) | ✅ |
| 2 | Entry Summarization | ✅ |
| 2 | Auto-Scheduling (basic) | ✅ |
| 2 | Proactive Triggers (time + location) | ✅ |
| 2 | Background Processing (charging) | ✅ |
| 2 | Web Search | ✅ |
| 2 | Google Calendar (real API) | 🟡 Mock Mode |
| 2 | Proactive Voice (TTS) | ❌ |
| 3 | Hidden Correlation | ❌ |
| 3 | Social Battery | ❌ |
| 3 | Music/News Context | ❌ |
| 4 | Shadow Mode | ❌ |
| 4 | AR Memory Anchor | ❌ |

**Phase 2 progress: ~90%** (เหลือ Google Calendar real + TTS)

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
