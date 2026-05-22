# Haku — Private Life OS: Features Roadmap

> อัปเดตล่าสุด: 2026-05-22 (Memory system audit ✅ — write/read paths ครบทุก tier, FactWorker→UnifiedVectorService fix, Gemma 4 Vision + Thinking Mode, MCP chip)
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
| **2** | Proactive Intelligence | ปัญหา 2 — Passive AI | 🟡 ~93% Done |
| **3** | B2C Monetization | Goal 1+2 — Revenue + Stickiness | 🔴 Planned |
| **4** | Analytics & Deep Personalization | Goal 1 — AI รู้จักคุณในระดับลึก | 🟡 ~45% Done |
| **5** | B2B — Agent Protocol | Goal 2+3 — B2B + Data Sovereignty | 🔴 Planned |
| **6** | Haku OS Vision | Goal 3 — National Impact | 💡 Concept |

---

---

## 🚀 18-Month Business Roadmap (depa Grant Plan)

> แผนธุรกิจสำหรับยื่นขอทุน depa — เริ่มต้นจาก Foundation ที่สร้างแล้ว
> **ก่อนขอทุน:** Phase 1 (Privacy Core) ✅ + Phase 2 (Proactive Intelligence) 🟡 90% — สร้างด้วยทุนส่วนตัว

### Phase B1: Sovereign Core & Context Awareness (เดือนที่ 1–6)

> **เป้าหมาย:** "สร้างสมองและสัมผัสอัจฉริยะ" — วางโครงสร้าง AI ที่รู้ใจ ไม่มโน เริ่มทำงานเชิงรุกพื้นฐาน

**🛠️ Tech & Product:**
- [ ] **Voice Input (STT)** — Whisper-Tiny on-device (privacy-safe, ไม่ส่งเสียงออก Cloud)
- [ ] **Meeting Pre-Flight Check** — RAG สรุปบริบทส่งถึงมือ 15 นาทีก่อนนัดทุกครั้ง
- [ ] **A2A Identity Layer** — keypair บน Android Keystore + E2E encrypted bundle (รากฐาน A2A)
- [ ] **Privacy Transparency Screen** — แสดงหลักฐาน Zero Cloud ให้ผู้ใช้เห็นด้วยตาตัวเอง (Zero network calls audit)

**💼 BD & Marketing:**
- [ ] **Pre-B2B Onboarding** — เข้าพบและทำ MOU หอการค้าจังหวัดกาฬสินธุ์ (กลุ่ม SME, YEC)
- [ ] สำรวจ Workflow จริงของ SME เพื่อจูน A2A ให้ตอบโจทย์ธุรกิจจริง
- [ ] รวบรวม Requirements สำหรับ B2B Beta Phase B2

**🎯 Milestone:** A2A Foundation พร้อม Beta — MOU หอการค้าฯ กาฬสินธุ์ลงนามแล้ว

---

### Phase B2: The A2A Network & B2B MVP (เดือนที่ 7–12)

> **เป้าหมาย:** "เปิดตัวเครือข่าย AI ระดับองค์กร" — สร้าง Game Changer ด้วย AI ที่คุยกันเองได้

**🛠️ Tech & Product:**
- [ ] **A2A Transport Layer** — WiFi Direct ก่อน (ออฟฟิศเดียวกัน) → E2E Encrypted Relay สำหรับระยะไกล
- [ ] **AI Handshake (เพิ่มเพื่อน)** — Haku-to-Haku peer pairing + E2E Encryption ไม่เห็น Calendar ของกัน
- [ ] **MeetingNegotiationProtocol** — ประสานนัดหมายโดยส่งเพียง "ว่าง/ไม่ว่าง" ไม่เปิด Calendar จริง
- [ ] **A2A UI** — ค้นหา Haku peers ในเครือข่าย + real-time negotiation status screen
- [ ] **Task Delegation Protocol** — มอบหมายงานระหว่าง Haku agents แบบ encrypted

**💼 BD & Marketing:**
- [ ] **Exclusive Beta Test** — เครือข่ายหอการค้าฯ กาฬสินธุ์เป็น Real-world Sandbox พิสูจน์ A2A ลดงานซ้ำซ้อน
- [ ] **Traction Building** — เก็บ Case Study ตัวเลขจริง: ประหยัดเวลา/ต้นทุนเท่าไหร่ เพื่อ Pitching
- [ ] เตรียม Traction Report + Product Demo สำหรับ investor รอบถัดไป

**🎯 Milestone:** A2A Alpha ทำงานจริงกับ SME 3–5 องค์กรในกาฬสินธุ์ — มีตัวเลข Case Study พิสูจน์แล้ว

---

### Phase B3: Proactive Guardrails & Commercialization (เดือนที่ 13–18)

> **เป้าหมาย:** "ระบบป้องกันขั้นสูงและการทำรายได้" — ขยายสเกลธุรกิจ + ปกป้องการตัดสินใจของผู้ใช้

**🛠️ Tech & Product:**
- [ ] **Pin of Point (Cognitive Guardrail)** — ประมวลผลขั้นสูง สังเกตพฤติกรรม สะกิดเตือนเมื่อตัดสินใจผิดปกติจากมาตรฐาน
  - rule-based anomaly detection (threshold-based, fast) + optional LLM nudge
  - ตัวอย่าง: กำลังโอนเงินให้บัญชีแปลกหน้า / ตัดสินใจโดยไม่มีข้อมูล
- [ ] **A2A Commercial Release** — เสถียรจาก Alpha สู่ Enterprise-grade พร้อม SLA + B2B subscription gate
- [ ] **AI Personas + Skills System** — เปิด B2C revenue layer (IAP Personas + Skill Modules)

**💼 BD & Marketing:**
- [ ] **Monetization** — Convert Beta Testers หอการค้าฯ → Paid B2B Subscribers
- [ ] **National Expansion** — นำ Success Story จากกาฬสินธุ์เสนอขายหอการค้าจังหวัดอื่น + หน่วยงานส่วนกลาง
  - เป้าหมาย: "เริ่มติดต่อ" ไม่ใช่ "close ทันที" (realistic)
- [ ] เตรียมเอกสาร Pre-Series A ด้วย Valuation ที่สูงขึ้นจาก Product-Market Fit ที่พิสูจน์กับ SME ไทย

**🎯 Milestone:** รายได้ B2B จริงครั้งแรก + National Expansion เริ่มแล้ว + เอกสาร Pre-Series A พร้อม

---

---

## 🏗️ Infrastructure: On-Device AI Stack

> รองรับทุก Phase — ฐานที่ทุก feature ต้องพึ่ง

### ✅ Long-Term Memory + Context Compression (เสร็จแล้ว — 2026-05-11)

> แชทเดียวต่อเนื่องตลอดชีพ — ลบแชทแล้วยังจำ + รองรับ A2A Protocol

**Architecture: 3-Tier Memory**
```
Working Memory (RAM, ~800 tokens)   ← LeanContext last 8 turns
  ↓ flush every 5 exchanges
Episodic Memory (SQLite FTS5)       ← secret_chat_log + BM25 retrieval
  ↓ nightly consolidation (charging)
Semantic Memory (facts + Wiki)      ← UnifiedVectorService + WikiService
```

- [x] `DatabaseHelper` v3 — `secret_chat_log` table + `chat_fts` FTS5 virtual table + 3 sync triggers
- [x] `SecretChatService` — dual-write SharedPrefs + SQLite (episodic LTM)
- [x] `TagContextService` — ใช้ `searchChatFTS()` BM25 แทน linear scan (fallback ไว้)
- [x] `ContextBudgetService` — hard token budget สำหรับ Gemma 4 4B (8192 ctx): input 4100 / response 2000 / safety ~2000
- [x] `SessionResumeService` — `buildResume()` = top facts + calendar today/tomorrow + recent episodic → inject system instruction ทุก session
- [x] `chat_screen._startNewLiteRTSession()` — async + inject LTM resume
- [x] `clearHistory()` — ล้างแค่ UI + in-memory, **SQLite LTM preserved** (ลบแชท ≠ ลืม)
- [x] `BackgroundTaskHandlers.handleMemoryConsolidation` — episodic >7d → LLM 1 call → fact, prune >30d
- [x] `BackgroundTaskHandlers.handleWikiUpdate` — update pending wiki summaries
- [x] `DeferredTaskService._enqueueNightlyTasks()` — auto-enqueue consolidation + wiki ทุกครั้งที่ชาร์จ
- [x] `WikiService` — LLM Wiki (Karpathy+Mem0 pattern): `KnowledgePage` per entity, contradiction detection, supersession chain, confidence scoring
- [x] `knowledge_pages` + `knowledge_links` SQLite tables
- [x] `MemoryBundleService` — `exportBundle(categories)` + `importBundle()` + dedup/conflict flagging (A2A foundation)
- [x] `PromptBuilder.buildConsolidationPrompt()` — distill episodic batch → facts

**Token Budget (Gemma 4 4B / 8192 ctx):**
```
System + persona   :  300 tokens
Session resume     :  300 tokens  ← facts + calendar
Working memory     :  800 tokens  ← last 8 turns
Episodic FTS5      : 1000 tokens  ← BM25 top-3
Wiki pages         : 1200 tokens  ← top-2 entities
User message       :  300 tokens
────────────────────────────────
Total input        : 3900 tokens  (safety margin ~2300)
Response budget    : 2000 tokens
```

**Reference:** [Karpathy LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) · [Mem0 AI](https://github.com/mem0ai/mem0) · [Microsoft GraphRAG](https://github.com/microsoft/graphrag) · [Zep](https://github.com/getzep/zep)

---

### ✅ LiteRT-LM Migration (เสร็จแล้ว)

> เปลี่ยน runtime จาก MediaPipe (deprecated) → **LiteRT-LM v0.10.0**

- [x] ลบ `MediaPipeLLMBridge.kt` (deprecated, reflection-based)
- [x] สร้าง `LiteRTLMBridge.kt` — clean API, stateful Conversation + KV cache
- [x] อัพเดท `build.gradle` — swap `mediapipe:tasks-genai` → `litertlm-android:0.10.0`
- [x] อัพเดท `MainActivity.kt` — ใช้ `LiteRTLMBridge` + `generateTurn` + `resetConversation`
- [x] `LiteRTLLMProvider.generateTurn()` — stateful KV cache per chat session
- [x] `PromptBuilder.buildSystemInstruction()` + `buildUserTurn()` — แยก system vs user turn
- [x] ทดสอบ build + รันบน device จริง ✅ (Gemma 4 active)
- [x] Download `.litertlm` model format — **ใช้ Gemma 4 E2B/E4B แล้ว** (ไม่ใช่ Gemma 3 1B)

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
# อัปเดต 2026-05-22: เปลี่ยนมาใช้ Gemma 4 แล้ว
current:  # ✅ ACTIVE
  model: Gemma 4 E2B / E4B (.litertlm)
  size: ~1.5GB / ~4GB
  context: 128K tokens (budget: 8192, set ใน ContextBudgetService)
  features_active:
    - Thinking Mode ✅  # parse <thinking> tags → _ThinkingSection
    - Vision ✅         # visionBackend=GPU auto, generateTurnWithImages
  lean_syntax: ยังใช้อยู่แต่ผ่อนคลายกว่า (ไม่ต้อง extreme compress)
               — ContextBudgetService จัดการ budget แทน manual lean
               — PreClassify ยังคงไว้ เพราะประหยัดแบต (ไม่ใช่ context)

legacy:  # ไม่ได้ใช้แล้ว
  model: Gemma 3 1B (.litertlm)
  size: ~600 MB
  context: ~4096 tokens
  lean_syntax: full lean (compress Thai ให้สั้น + PreClassify)
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
| `onboarding_screen.dart` — Glass emoji card + accent per page | ✅ |
| `lock_screen.dart` — Lavender fingerprint orb | ✅ |
| `settings_screen.dart` — Glass sections + aurora bg | ✅ |
| `new_entry_screen.dart` — Glass AppBar + mood selector | ✅ |
| `view_entry_screen.dart` — AI summary + insights glass cards | ✅ |
| `focus_timer_screen.dart` — Lavender timer ring + glass chips | ✅ |
| `model_manager_screen.dart` — Glass cards + kVividMint badge | ✅ |
| `automation_screen.dart` — Aurora bg + crystal FAB | ✅ |
| `presets_screen.dart` — Glass TabBar + preset cards | ✅ |
| `quick_actions_fab.dart` | ✅ |

**Widgets:**
- [x] `CausticShimmer` — Reusable glass shimmer `CustomPainter`
- [x] `FlutterMap` mini map ใน `view_entry_screen.dart` (OpenStreetMap, 200px)

**Rules:** ไม่ใช้ emoji ใน user-facing string ยกเว้น source comments

---

---

## 🔬 Memory & Knowledge System — Architecture Research

> วิเคราะห์สถาปัตยกรรมระบบความจำระยะยาวและ Knowledge Graph จาก Repository ชั้นนำ
> วันที่วิเคราะห์: 2026-05-13

---

### 1. Karpathy's LLM Wiki (Gist) — Haku ทำไป 90% แล้ว

| แนวคิด Karpathy | Haku ปัจจุบัน | สถานะ |
|---|---|---|
| AI ดูแลหน้า Wiki ต่อ entity | `KnowledgePage` (person/place/topic/goal/habit) | ✅ มีแล้ว |
| อัปเดตสะสม ไม่เขียนทับ | `rawFacts[]` + `copyWith()` สะสม | ✅ มีแล้ว |
| ตรวจจับข้อขัดแย้ง | `_detectContradiction()` → YES/NO LLM check | ✅ มีแล้ว |
| Confidence Scoring | `confidence` field + corroboration boost | ✅ มีแล้ว |
| Wiki-links เชื่อมโยง | `knowledge_links` table | ⚠️ มี schema แต่ยังไม่มี graph traversal |
| Supersession chain | `supersededBy` field | ✅ มีแล้ว |

**สรุป:** Haku ไม่ต้องศึกษาเพิ่มมาก — แค่ต้อง implement **graph traversal** บน `knowledge_links` ให้ WikiService สามารถ "เดินตามลิงก์" ได้ (เช่น ค้นหา "บอส" → เจอ linked "ออฟฟิศ" → ดึง context สองหน้ามา inject พร้อมกัน)

---

### 2. Mem0 (mem0ai/mem0) — น่าศึกษาเฉพาะบางส่วน

**จุดเด่นที่ Haku ยังไม่มี:**

| Mem0 Feature | Haku ปัจจุบัน | ควรยืมมั้ย? |
|---|---|---|
| **Graph Memory** (Neo4j/Memgraph) | มีแค่ `knowledge_links` table เปล่าๆ | ✅ **ควรยืม concept** |
| **Hybrid Search** (Vector + BM25 + Graph) | Vector (TF-IDF) + FTS5 แยกกัน | ⚠️ ปรับปรุงได้ |
| **Multi-user isolation** | Haku เป็น single-user | ❌ ไม่จำเป็น |
| **REST API / MCP Server** | On-device ไม่มี server | ❌ ไม่จำเป็น |

**ข้อจำกัดของ Mem0 ที่ทำให้ไม่เหมาะกับ Haku:**
- Mem0 ต้องการ **PostgreSQL + pgvector** (ต้องลง Docker) → Haku ใช้ SQLite + SQLCipher (single file, encrypted)
- Mem0 ใช้ LLM สำหรับ extraction ทุกครั้ง → Haku ใช้ **Workers (0 LLM token)** + LLM เฉพาะตอนชาร์จ
- Mem0 เป็น Python/JS server-side → Haku เป็น Dart on-device

**สรุป:** ศึกษา concept **Graph Memory + Hybrid Search** ได้ แต่ **อย่าเอา codebase มาใช้** — ไม่ fit architecture on-device

---

### 3. Microsoft GraphRAG — เก็บไว้สำหรับเอกสารในอนาคต

| ปัจจัย | GraphRAG | Haku ปัจจุบัน |
|---|---|---|
| **Target use case** | Index เอกสารเป็นชุดใหญ่ (batch) | Real-time chat memory |
| **LLM usage ตอน index** | หนักมาก (extract entity+relation ทุก chunk) | Workers 0 token / LLM เฉพาะ background |
| **Hardware** | Server / Desktop + GPU | Mobile CPU |
| **Speed** | นาที-ชั่วโมงต่อ corpus | ต้องตอบใน <1 วินาที |

**เหตุผลที่เก็บไว้:** ในอนาคต Haku อาจรองรับการ import เอกสาร (PDF, รูปภาพ, ไฟล์) → GraphRAG pattern (entity extraction + community detection + hierarchical summarization) อาจมีประโยชน์สำหรับ **batch indexing** เอกสารเหล่านั้น โดยเฉพาะตอนชาร์จ

**คำแนะนำ:** อย่า port GraphRAG มาทั้งตัว — ถ้าต้องการ multi-hop reasoning ให้ implement เองบน `knowledge_links` ที่มีอยู่ สำหรับ document RAG ค่อยศึกษา GraphRAG pattern อีกครั้งตอน implement Phase 4.5 (Document Import)

---

### 4. Zep (getzep/zep) — Temporal Memory & Time-Decay

> [GitHub: getzep/zep](https://github.com/getzep/zep) — Long-term memory service ที่เน้น **temporal awareness**

| Zep Feature | Haku ปัจจุบัน | ควรยืมมั้ย? |
|---|---|---|
| **Temporal tracking** — fact เปลี่ยนแปลงเมื่อไหร่ | `supersededBy` ใน WikiService | ✅ concept ดี, มี partial แล้ว |
| **Time decay scoring** — fact เก่า → confidence ลด | ยังไม่มี | ✅ **ควรเพิ่ม** |
| **Bi-temporal schema** — `valid_time` vs `transaction_time` | ยังไม่มี | 🟡 nice-to-have |
| **Graphiti** — knowledge graph ที่ track timeline | `knowledge_links` table (static) | ⚠️ เพิ่ม `created_at` / `invalidated_at` ใน links |
| **Retrieval via graph traversal** | vector + FTS5 แยกกัน | ⚠️ graph traversal ยังไม่ implement |

**จุดเด่นของ Zep เทียบ Mem0:**
- จัดการ "เคยทำงานที่ X ตอนนี้ย้ายไป Y" ได้โดยไม่ confuse — เพราะ track timeline
- Confidence ของ fact ลดลงตามเวลา (เก่ากว่า → น่าเชื่อถือน้อยกว่า)

**ข้อจำกัดของ Zep ที่ทำให้ไม่เหมาะกับ Haku:**
- Server-side: ต้องการ Neo4j / PostgreSQL
- Python/JS → Haku เป็น Dart on-device SQLite

**สรุป:** อย่า port codebase — ยืมเฉพาะ 2 concept:
1. **Time decay**: เพิ่ม `lastCorroboratedAt` + decay formula ใน `KnowledgePage.confidence`
2. **Bi-temporal schema**: เพิ่ม `validUntil` field ใน `knowledge_links` เพื่อ invalidate links เก่า

---

### 5. Workers vs Skill.md — คำตอบสถาปัตยกรรม

**ตอบ: Workers (rule-based) ยังจำเป็น และน่าจะ "จำเป็นมากขึ้น" เมื่อ Haku ใหญ่ขึ้น**

| ปัจจัย | Workers (Rule-based) | Skill.md / Function Calling |
|---|---|---|
| **Token cost** | 0 | 1+ LLM call |
| **Latency** | <1ms | 2-10s (load model + generate) |
| **Battery** | ไม่กินแบต | กิน NPU/CPU มาก |
| **Offline** | ทำงานได้ทันที | ต้องรอ model load |
| **Coverage** | 80% common cases | 20% edge cases |
| **Maintainability** | เพิ่ม regex | เพิ่ม tool definition |

**Architecture ที่ถูกต้องคือ Hybrid:**
- **Workers** จับ common cases ก่อน (เร็ว ฟรี แน่นอน)
- **Function Calling / Skill.md** จับ cases ที่ Workers miss (flexible แต่แพง)
- **Wiki + Memory** เป็นชั้น long-term storage ที่ทั้งสองฝั่งใช้ร่วมกัน

Gemma 4 มี context มากขึ้น → ไม่ได้แปลว่าต้องใช้ LLM ทุกอย่าง แต่แปลว่า **มี budget เหลือสำหรับงานที่ LLM ทำได้ดีจริงๆ** (เช่น contradiction detection, summary generation, link inference)

---

### 6. Action Items จากการวิเคราะห์

| # | งาน | แหล่งที่มา | Priority | Effort | LLM tokens |
|---|---|---|---|---|---|
| 1 | Implement graph traversal บน `knowledge_links` | Karpathy + Mem0 | 🔴 High | 1-2 วัน | 0 |
| 2 | Hybrid search (Vector + FTS5 + Graph) สำหรับ Wiki | Mem0 | 🟡 Medium | 2-3 วัน | 0 |
| 3 | Time decay scoring ใน `KnowledgePage.confidence` | **Zep** | 🟡 Medium | 0.5 วัน | 0 |
| 4 | เพิ่ม `validUntil` ใน `knowledge_links` (bi-temporal) | **Zep** | 🟢 Low | 1 วัน | 0 |
| 5 | Auto-generate knowledge_links ตอนชาร์จ | Karpathy | 🟢 Low | 3-5 วัน | ~100/page |
| 6 | GraphRAG pattern สำหรับ document import (อนาคต) | GraphRAG | 🔴 Future | — | — |

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

**Architecture: 4-Layer Trigger Flow**
```
App Startup  →  Background  →  Foreground  →  Notification
     ↓              ↓              ↓              ↓
scheduleDaily   AlarmManager   MVPTriggerService  unified channel
+HakuBgService  + ChargingBR   (5-min poll+GPS)   haku_proactive_triggers
```

- [x] Time-based (09:00 เช้า, 12:00 เที่ยง, 17:00 เย็น, 22:00 ก่อนนอน)
- [x] Location-based (revisit 200m, 2+ hr gap)
- [x] No-entry reminder
- [x] Battery-optimized: เช็คทุก 5 นาที
- [x] Notification Service + Quick Reply จาก notification
- [x] Deep link เข้าแอปพร้อม context
- [x] **Dead code cleanup** — ลบ `TriggerService` + `TimerTrigger` (ไม่มีใครใช้)
- [x] **Channel unification** — ทุก notification ใช้ `haku_proactive_triggers` channel
- [x] **User toggles** — Settings > Proactive AI: ปิด/เปิด morning, evening, GPS location, charging AI แยกกัน
- [ ] Proactive Voice Alert (TTS) — ยังไม่ implement

---

### 2.9 Background Processing (Charging-Deferred) ✅

- [x] `BatteryAwareService` — ตรวจจับ charging/discharging
- [x] `DeferredTaskService` — priority queue + auto-process ตอนชาร์จ
- [x] `ManagerSummaryStrategy` — วิเคราะห์ health, behavior, preferences
- [x] `BackgroundTaskHandlers` — wire ManagerSummary + reindex vectors
- [x] Energy Profile (ultraSaver / batterySaver / balanced / performance)
- [x] **`flutter_background_service`** — foreground service ทำงานได้แม้แอพปิด (Dart isolate)
- [x] **`HakuForegroundService.kt`** — native Android service spawn FlutterEngine ตอนชาร์จ → รัน Dart callback
- [x] **`BootReceiver.kt`** — reschedule daily alarm หลัง reboot
- [x] **SLM in background** — `ChargingTrigger.processEndOfDay()` เรียก `LLMService.generate()` ผ่าน `beginBackgroundSession()` (ป้องกัน auto-unload)
- [x] **`BatteryOptimizationService`** — ขอ `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` + คู่มือตั้งค่าแบรนด์ (Xiaomi/Samsung/OPPO)
- [x] **Charging toggle guard** — `proactive_charging_enabled` ปิดได้จาก Settings

---

### 2.10 Web Search Integration ✅ (MCP Migration Done)

> **อัปเดต 21/5/2026:** MCP migration เสร็จสมบูรณ์ — WebSearchService HTTP scraping ถอดออกจาก pipeline แล้ว, McpService พร้อมใช้งาน

**Architecture ใหม่ (หลัง MCP):**
```
"ค้นเว็บ" chip / SmartPreprocessor DetectedIntent.search
  ↓
McpService (lib/services/mcp_service.dart)
  ├─ loadSettings() → serverUrl จาก SharedPreferences 'mcp_server_url'
  ├─ connect() → initialize handshake + tools/list
  └─ search(query) → tools/call brave_search | web_search | search
  ↓
ผลลัพธ์ → _buildSearchFollowUpPrompt() → Face LLM → Thai response
fallback (MCP ไม่ตั้งค่า / ล้มเหลว) → Face LLM ตอบจากความรู้เอง
```

**สิ่งที่เสร็จแล้ว:**
- [x] **`lib/services/mcp_service.dart`** ✅ — JSON-RPC 2.0 over HTTP POST
  - `McpTool` model, singleton `McpService`
  - `loadSettings()` / `saveServerUrl()` — SharedPreferences `mcp_server_url`
  - `connect()` → `initialize` + `tools/list`
  - `callTool(name, args)` → `tools/call`, parse content array
  - `search(query)` → ลอง `brave_search` → `web_search` → `search` → fallback tool ที่มี "search" ในชื่อ
- [x] **PATH A rewired** — `chat_screen.dart` SmartPreprocessor search → McpService, graceful fallback ถ้าไม่ตั้งค่า
- [x] **"ค้นเว็บ" chip dialog rewired** — SnackBar ถ้าไม่ตั้งค่า MCP, connect + search ถ้าพร้อม
- [x] **Settings > MCP Integration** — ListTile + dialog บันทึก URL, subtitle สีเขียว/ส้มตามสถานะ
- [x] **WebSearchService ถอดออกจาก** `manager_dispatch_service.dart` + `ai_action_service.dart`
- [x] **`dart analyze lib/` → No issues found** ✅
- [x] UI shell ยังอยู่ครบ: chip (L1041), AlertDialog (L1343–1372), `_buildSearchingBubble()`, `_buildSearchFollowUpPrompt()`

**สิ่งที่ถอดออก (เพราะ broken):**
- [~] ~~SearXNG public instances~~ — rate-limit 429 หลัง ~5 ครั้ง
- [~] ~~Google scraping~~ — JS-rendered, static HTML ใช้ไม่ได้
- [~] `WebSearchService` HTTP pipeline ใน chat/manager/action

**ขั้นต่อไป (ต้องทำเอง):**
- [ ] ตั้ง MCP server จริง เช่น `npx @modelcontextprotocol/server-brave-search` (ต้อง Brave API key)
- [ ] ใส่ URL ใน Settings > MCP Integration → ทดสอบ search end-to-end

**MCP Tools ที่รองรับ:**
| Tool | Server ตัวอย่าง | API Key |
|------|----------------|---------|
| `brave_search` | `@modelcontextprotocol/server-brave-search` | ✅ ต้องการ |
| `web_search` | generic MCP search servers | ขึ้นอยู่กับ server |
| `search` | fallback — tool แรกที่มีคำว่า search | — |

**Privacy Note:** ข้อมูลออกนอกเครื่องเฉพาะตอน user กด search และ MCP server ตั้งค่าไว้ — user เลือก server เอง (self-hosted = ไม่ออกนอกบ้าน)

---

**อัปเดต 18/5/2026 — Nominatim Nearby Search:**
- [x] **`NominatimService`** — reverse geocode GPS → `NominatimAddress` (suburb, county) โดยใช้ OpenStreetMap Nominatim (ฟรี, ไม่ต้อง API key) + 1km cache
- [x] **`searchNearby(lat, lng, query)`** — GPS → Nominatim area name → ค้น "cafe ยางตลาด กาฬสินธุ์" (แทนเพียงพิกัด GPS)
- [x] **`searchNearbyForAI(query, lat, lng)`** — ใช้ Nominatim เมื่อมี GPS แต่ไม่มี Google API key
- [x] **Expanded nearby keywords** — ใกล้ๆ, ร้านใกล้, หาร้าน, near here

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

**สถานะ:** เสร็จแล้ว + พร้อมใช้งานกับ Gemma 4 (2026-05-22)

- [x] parse `<thinking>...</thinking>` และ `<think>...</think>` (Gemma 4 + DeepSeek-R1) ด้วย RegExp
- [x] `_ThinkingSection` — collapsible widget เหนือ reply จริง (default collapsed)
- [x] แสดงเฉพาะเมื่อ model ส่ง thinking tags มา (Gemma 4 / reasoning models)
- [x] `LLMModelConfig.supportsThinking` getter — Gemma 4 E2B/E4B คืน `true`
- [x] `_CapabilitiesSheet` — Feature Guide Sheet (tap AppBar chip) พร้อม step-by-step + ตัวอย่าง

**วิธีเรียกใช้:** แตะ chip `[Gemma 4 E2B 👁 💭]` ใน AppBar → ดูคู่มือ + ตัวอย่าง prompt

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

### 2.22 Device Commands — Smartphone Control 🟡 ~50% Done

> **แก้ปัญหา 2 (Passive AI):** Haku สั่งงาน smartphone ได้ตามคำพูดธรรมชาติ ไม่ต้องออกจากแชท

**สถานะ:** Foundation เสร็จแล้ว (2026-05-17/18) — Phase 2 Proactive ยังไม่ implement

**Architecture:**
```
User: "เงียบหน่อย" / "จับเวลา 5 นาที"
  ↓
DeviceCommandIntentDetector (step-0 rule-based, 0 LLM)
  ↓
DeviceCommandGate (4-tier safety check)
  ├─ 🟢 Auto → execute ทันที
  ├─ 🟡 Notify → execute + แจ้งเตือน
  ├─ 🔴 Confirm → ขึ้น dialog ยืนยัน
  └─ 🔒 Biometric → ต้อง Face ID/ลายนิ้วมือ
  ↓
DeviceCommandService.execute() → MethodChannel
  ↓
DeviceCommandHandler.kt (Android native)
  ↓
DeviceCommandAudit.logEntry() (SQLite, 30-day prune)
```

**Level 1 — Implemented ✅:**

| คำสั่ง | Pattern ตัวอย่าง | Tier |
|-------|-----------------|------|
| Flashlight on/off/toggle | เปิดไฟฉาย, ปิดแฟลช, สลับไฟฉาย | 🟢 Auto |
| Set alarm | ตั้งปลุก 6 โมงครึ่ง, ปลุกฉัน 07:30 | 🟢 Auto |
| Set timer | จับเวลา 5 นาที, ตั้งเวลา 10 minutes | 🟢 Auto |
| Silent mode | เงียบหน่อย, ปิดเสียงเรียก, โหมดเงียบ | 🟢 Auto |
| Vibrate mode | โหมดสั่น, เปิดสั่น | 🟢 Auto |
| Sound on | เปิดเสียงกลับ, unmute | 🟢 Auto |
| Volume up/down | เพิ่มเสียง, ลดเสียง, louder | 🟢 Auto |
| Check-in | เช็คอินที่นี่, check in | 🟢 Auto |
| Dial phone | โทร 0812345678 | 🔴 Confirm |
| WiFi/BT settings | เปิดหน้า WiFi, ตั้งค่าบลูทูธ | 🟡 Notify |

**Implementation Detail:**
- [x] `DeviceCommandService` — singleton MethodChannel bridge `com.example.haku/device`
- [x] `DeviceCommandHandler.kt` — Android native: AlarmClock intent, AudioManager, CameraManager
- [x] `DeviceCommandIntentDetector` — rule-based, detect ก่อน LLM (step-0.5 ใน chat flow)
- [x] `DeviceCommandAudit` — SQLite `device_command_log` table + auto-prune 30 วัน
- [x] `DeviceCommandGate` — 4-tier: auto / notify / confirm / biometric + Thai tier labels
- [x] `NotificationAlarmReceiver.kt` — รับ alarm/timer broadcast
- [x] Thai time parser: `_parseThaiTime()` (6 โมง = 06:00, บ่าย 3 = 15:00)
- [x] Thai timer parser: `_parseTimerSeconds()` (5 นาที, 2 ชั่วโมง)
- [x] **Check-in command**: GPS → nearest SavedPlace (300m) → Nominatim fallback → สร้าง diary Entry + prompt ตั้งชื่อสถานที่ใหม่
- [x] MODIFY_AUDIO_SETTINGS permission ใน AndroidManifest
- [x] `withValues(alpha:)` แทน deprecated `.withOpacity()` ใน Gate UI

**Phase 2 — Proactive Commands (ยังไม่ implement):**
- [ ] `ProactiveCommandEngine` — subscribe TriggerStream (GPS, Time, Calendar) → auto execute
- [ ] `TriggerCommandMapping` — trigger → command table ใน SQLite (ตั้งค่าได้)
  - ตัวอย่าง: ถึงบ้าน → เปิด WiFi / เข้าที่ทำงาน → เปิด DND / 22:00 → เปิด Night Mode
- [ ] `ContextAwareFilter` — ตัดสินใจว่าควรรันหรือไม่ (user_busy?, battery_low?, already_done_today?)
- [ ] `CommandAuditScreen` — UI แสดงประวัติคำสั่งที่ AI สั่ง ("AI ทำอะไรไปบ้างวันนี้")

**Phase 3 — Security & B2B (อนาคต):**
- [ ] Biometric approval integration (Face ID / Fingerprint)
- [ ] Enterprise MDM Commands (lock_device, camera_disable, app_whitelist)
- [ ] A2A Command Relay — สั่งงานข้ามเครื่องในทีม

**Reference:** `docs/DEVICE_COMMAND_ROADMAP.md` · `docs/DEVICE_COMMAND_DESIGN.md`

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

### 3.2 MCP Integration — External Tools Gateway ✅ (Foundation Done)

**สถานะ:** Foundation เสร็จแล้ว (21/5/2026) — รอ MCP server จริงมาต่อ
**ความยาก:** ⭐⭐
**Privacy:** User เลือก MCP server เอง — self-hosted = ข้อมูลไม่ออกนอกบ้าน

> MCP (Model Context Protocol) เป็น standard JSON-RPC 2.0 สำหรับ LLM tool calls — แทนที่ broken HTTP scraping ด้วย pluggable tool interface

**Architecture (implement แล้ว):**
```
User: "ค้นหา..." / SmartPreprocessor DetectedIntent.search
  ↓
McpService (lib/services/mcp_service.dart)
  ├─ loadSettings() → serverUrl จาก SharedPreferences 'mcp_server_url'
  ├─ connect() → initialize + tools/list
  └─ search(query) → tools/call brave_search | web_search | search
  ↓
ผลลัพธ์ inject เข้า Face LLM → Thai response
fallback: Face LLM ตอบจากความรู้เอง (ถ้า MCP ไม่ตั้งค่า / ล้มเหลว)
```

**เสร็จแล้ว:**
- [x] `lib/services/mcp_service.dart` — McpTool model + McpService singleton
- [x] `connect()` → `initialize` handshake + `tools/list`
- [x] `callTool()` → `tools/call`, parse content array
- [x] `search()` → ลอง `brave_search` → `web_search` → `search` → fallback
- [x] PATH A (SmartPreprocessor search) → McpService
- [x] "ค้นเว็บ" chip dialog → McpService / SnackBar
- [x] Settings > "🔌 MCP Integration" section — URL tile + dialog + save
- [x] `dart analyze lib/` → No issues found
- **LLM usage:** 0 extra

**ยังต้องทำ (รอ user ตั้งค่า):**
- [ ] ตั้ง MCP server จริง เช่น `npx @modelcontextprotocol/server-brave-search`
- [ ] ทดสอบ end-to-end: พิมพ์ query → searching bubble → MCP result → LLM Thai response

**MCP Tools ที่รองรับ:**
| Tools | ต้องการ | ตัวอย่าง server |
|-------|--------|----------------|
| `brave_search` | Brave API key | `@modelcontextprotocol/server-brave-search` |
| `web_search` | ขึ้นอยู่กับ server | generic MCP search |
| `runJs` (อนาคต) | Gallery WebView bridge | real-browser search ไม่ถูก detect |

**อ้างอิง:** `C:\Users\haiki\.claude\plans\integration-mcp-compiled-forest.md`

---

### 3.3 Skills System 🔴 (Feature 6 จาก Gallery)

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

### 3.4 Native Function Calling 🔴 (Feature 7 จาก Gallery)

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

### 5.1 Agent-to-Agent Protocol 🟡 (Foundation Done)

**สถานะ:** Foundation implement แล้ว — transport layer + UI ยังไม่ implement
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

**Foundation ที่ทำแล้ว:**
- [x] `MemoryBundleService` — `exportBundle(categories)` → JSON + `importBundle()` → merge with dedup/conflict flagging
- [x] `WikiService` — knowledge pages พร้อม confidence score + supersession chain (ส่งผ่าน bundle ได้)
- [x] DB schema: `knowledge_pages` + `knowledge_links` tables

**งานที่ยังเหลือ:**
- [ ] `HakuAgentIdentity` — keypair ที่เก็บใน device keystore (Keystore API)
- [ ] `AgentChannel` — encrypt bundle ด้วย NaCl/libsodium ก่อนส่ง
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
> แผน 3 ปี — Road to Haku OS (The 3-Year Fast Track)

### 🗺️ 4-Phase OS Roadmap

#### Step 1: The Beachhead — App + Accessibility (เดือนที่ 1–18) ✅ Committed
> ยึดหัวหาดผ่านแอปพลิเคชัน — นี่คือแผน depa 18 เดือน

- **ระดับเทคโนโลยี:** Haku ยังเป็น "แอปพลิเคชัน" ที่ขอสิทธิ์ Accessibility Service เพื่อทำหน้าที่ Intelligent Assistant
- **เป้าหมาย:** พิสูจน์ว่า AI ออฟไลน์ 100% ทำงานได้จริง ไม่มโน (LLM Wiki) และ A2A ประสานงานได้
- **กลยุทธ์:** เจาะ B2B นำร่องผ่านหอการค้าจังหวัดกาฬสินธุ์ เปลี่ยน workflow SME จนขาด Haku ไม่ได้

#### Step 2: The Enterprise Layer — MDM Profile (เดือนที่ 19–24) ✅ Realistic
> แทรกซึมระดับองค์กร — ก้าวข้ามจากแอปธรรมดาสู่ระบบควบคุมมือถือองค์กร

- **ระดับเทคโนโลยี:** พัฒนา Haku ให้เป็น Mobile Device Management (MDM) Profile
- **เป้าหมาย:** Haku กลายเป็น "แอปบังคับลง (System-level App)" สำหรับมือถือที่แจกให้พนักงานองค์กร
- **กลยุทธ์:** นำเสนอ "Haku for Work" ให้องค์กรใหญ่/หน่วยงานรัฐ (กฟภ., โรงพยาบาลรัฐ) — ชูจุดขาย "ข้อมูลความลับองค์กรไม่มีวันรั่วไหล 100%"
- **Tech:** Android MDM API (standard, ไม่ต้อง AOSP) + Zero Data Leakage USP

#### Step 3: The Strategic OEM Partnership (เดือนที่ 25–36) ⚠️ Ambitious
> จับมือค่ายมือถือ/Telco — Haku เริ่มฝังตัวลงถึงแกนระบบ

- **ระดับเทคโนโลยี:** นำ AOSP มาดัดแปลง ฝัง SLM + A2A Protocol ระดับแกนกลาง Pre-installed จากโรงงาน
- **เป้าหมาย:** สร้าง "Sovereign AI Phone" เครื่องแรกของไทย
- **กลยุทธ์ (Game Changer):** จับมือ Telco (AIS, True) หรือแบรนด์มือถือระดับกลาง (POCO, Infinix) ออกรุ่นพิเศษ "Powered by Haku OS" สำหรับราชการและ B2B Enterprise
- **Note:** แทนที่จะผลิตมือถือเอง (แพง+เสี่ยง) ให้ partnership เป็นช่องทาง

#### Step 4: True Haku OS (ปีที่ 3–4) 💡 Vision / Moonshot
> ระบบปฏิบัติการแห่งชาติ — บรรลุวิสัยทัศน์ Data Sovereignty

- **ระดับเทคโนโลยี:** Haku OS แยกจาก Google Services สมบูรณ์ — AI สั่ง NPU โดยตรง (Direct NPU Integration) ทำงาน Proactive 24 ชม. แบตต่ำมาก
- **เป้าหมาย:** สถาปนา "อธิปไตยข้อมูล (Data Sovereignty)" ให้กับประเทศ
- **กลยุทธ์:** เปิด Patent + API ให้หน่วยงานอื่นสร้างแอปบน Haku OS → กลายเป็น Platform → Series C / IPO ในฐานะ Alternative OS ของอาเซียน

---

### ❓ Q&A — สิ่งที่ Investor มักถาม

#### 🔋 Haku OS จะ "Power-up" พลัง AI ได้อย่างไร?

| จากแอป (ปัจจุบัน) | จาก OS (เป้าหมาย) |
|---|---|
| ประมวลผลผ่านชั้นคัดกรอง Android | **Direct NPU Integration** — AI ฝังตัวกับชิปโดยตรง Zero-Latency |
| เห็นแค่ข้อความที่ user พิมพ์ | **System-Level Context** — รู้บริบทข้ามทุกแอป (เพิ่งเปิดรูป อ่านอีเมล กำลังแชท) |
| Knowledge Graph ต่อแอป | **OS-level LLM Wiki** — ทุกแอปรวมสู่ Knowledge Graph ส่วนกลาง |

#### 🔓 ข้อจำกัดที่จะถูกปลดล็อกเมื่อเป็น OS

| ข้อจำกัดปัจจุบัน | สิ่งที่ OS ปลดล็อก |
|---|---|
| Android บังคับปิดแอป (Background Kill) | **No More Background Kills** — Haku OS ควบคุม battery เอง, AI standby 24 ชม. ไม่หลุด |
| ข้อมูลถูกขังแยกแอป (App Silos) | **No App Silos** — ทุกข้อมูลรวมสู่ Knowledge Graph เดียว |
| Accessibility Service มีความเสี่ยงถูกแฮก | **Absolute Zero Leakage** — Kernel-level architecture บล็อก external data extraction สมบูรณ์ (Air-Gap Capable) |

#### 🚀 Features ที่ OS ปลดล็อกให้

- **System-Wide Pin of Point** — สะกิดเตือนกลางจอทุกแอป เช่น กำลังโอนเงินให้บัญชีแปลกหน้า / พิมพ์ด้วยอารมณ์โกรธใน Line → Haku ป็อปอัปเตือนทันที
- **Native A2A Protocol** — คล้าย AirDrop สำหรับ AI — แลกเปลี่ยนงานระหว่างเครื่องโดยไม่ต้องเปิดแอปใดๆ
- **Intent-Based UI (App-less)** — ไม่ต้องเปิดแอป แค่บอกเป้าหมาย Haku จัดการทุกอย่างให้ ไม่สลับหน้าจอ

#### 🔑 Key Success Factors (KSF) ที่ investor อยากได้ยิน

1. **Strategic OEM/Telco Partnership** — จับมือค่ายมือถือ/Telco Pre-install "Sovereign AI Phone" เครื่องแรกของประเทศ
2. **Killer B2B Ecosystem** — องค์กรมองว่า Haku OS = MDM ที่ปลอดภัยที่สุด ยอมซื้อมือถือ Haku ให้พนักงานทั้งบริษัท
3. **Developer API** — เปิด API ให้นักพัฒนาสร้าง Skill บน Haku AI → สร้าง Ecosystem ที่แข็งแกร่ง

#### 🌍 Turning Point — จุดเปลี่ยนของยุคสมัย AI

1. **จาก App-Centric สู่ Intent-Centric** — โลกเลิกหมกมุ่นกับการ "เปิดแอป" มือถือเปลี่ยนจาก "Smart Phone (ลงแอปได้)" → "Intelligent Phone (คิดแทนคุณ)"
2. **ยุคทองของ Data Sovereignty** — เมื่อ AI ระดับโลกทำงานได้โดยไม่ต้องใช้ Internet ผู้คนและองค์กรจะ "เลิกส่งข้อมูลชีวิตตัวเองให้ Big Tech ข้ามชาติ" — Haku นำร่องพิสูจน์ให้โลกเห็น

---

---

## Pre-MVP Checklist (ก่อน Public Launch)

### Background Processing
- [x] **`flutter_background_service`** — foreground Dart isolate ทำงานตอนชาร์จ + periodic 15 min ✅
- [x] **AlarmManager daily triggers** — 09:00 morning + 20:00 evening ยิงแม้แอพปิด ✅
- **ข้อจำกัด:** WorkManager batch (post-MVP) — ยังไม่รองรับ heavy LLM tasks ผ่าน WorkManager

### Focus Timer
- [x] Break reminder notification ✅
- [ ] Deep Work session (mute notifications) — post-MVP

### GPS / Location
- [x] `GeofenceService` + `MVPTriggerService` (foreground only) ✅
- **ข้อจำกัด:** DwellTracker ทำงานได้เฉพาะแอพเปิดอยู่ — Phase 5.3 จะแก้

### Memory System Audit ✅ (เสร็จแล้ว — 2026-05-22)
> ตรวจสอบ write/read paths ทุก tier ครบแล้ว — ไม่มี gap เหลือ

**WRITE PATH (confirmed ✅):**
```
Chat → logExchange() → RAGService.indexEntry()           ✅ secret_chat_service.dart
Chat → logExchange() → WikiService.onNewFact() per tag   ✅
FactWorker → WikiService.onNewFact()                     ✅ name/nickname/role/pref/goal
FactWorker → UnifiedVectorService.upsertFact()           ✅ fixed 2026-05-22
Charging → ChargingTrigger.processEndOfDay()
  └─► WikiService.updatePendingSummaries()               ✅ (เมื่อ SLM โหลดได้)
BackgroundTaskHandlers.handleWikiUpdate()                ✅ AlarmManager fallback (ไม่ขึ้นกับ SLM)
WikiService.updatePendingSummaries() → _indexSummaryIntoRag() → RAGService.indexEntry() ✅
```

**READ PATH (confirmed ✅):**
```
sendToAI()
  ├─► WikiService.query()          ✅ vector + title-match + 1-hop graph
  ├─► TagContextService.buildContext() ✅ FTS5 BM25 chat_log
  └─► SessionResumeService.buildResume()
        ├─► UnifiedVectorService.facts  ✅ (ได้ name/job/goal/pref/health ครบแล้ว)
        └─► calendar today/tomorrow     ✅
```

**Gap ที่แก้แล้ว:**
- `FactWorker` เขียน name/nickname/role/pref/goal ลง `WikiService` เท่านั้น → `SessionResumeService.[RESUME]` ว่าง
- แก้: เพิ่ม `_vectorService.upsertFact()` คู่กันสำหรับทุก category สำคัญ (`name`, `job`, `goal`, `preference`)

### UI / UX
- [x] Haku Crystal Design System — ครบทุก screen (13 screens) ✅
- [x] `CausticShimmer` widget ✅
- [x] Entry Mini Map (FlutterMap, OpenStreetMap) ✅



ระดับ 2 — ต่อยอดความเป็น life logger (จุดแตกต่างจาก assistant ทั่วไป)
Photo → Auto-log ✅ (Gemma 4 Vision พร้อมใช้งาน 2026-05-22)
เปิดกล้อง → ถ่ายรูป → กลับมา Haku → "บันทึกด้วยไหม?" พร้อม location tag อัตโนมัติ
- [x] `_autoLogPhoto()` — ถ่ายรูป → Gemma 4 บรรยาย → diary entry + GPS location
- [x] `generateTurnWithImages()` — Dart + Kotlin bridge พร้อม (visionBackend=GPU auto เมื่อ modelId มี gemma-4)
- [x] `LLMModelConfig.supportsVision` getter
- [x] Quick question chip "📷 วิเคราะห์รูป" แสดงเฉพาะเมื่อ Gemma 4 โหลดอยู่
- [x] `_CapabilitiesSheet` — คู่มือ step-by-step + ตัวอย่าง prompt + ปุ่ม "ลองเลย"
**วิธีใช้:** แตะ 📷 ในช่อง input → เลือกรูป → ส่ง (หรือกด "บันทึก diary" เพื่อ auto-log)

Check-in อัตโนมัติ
"เช็คอิน" → Haku ดึง current GPS → สร้าง diary entry พร้อม location ทันที — ปิด loop ที่ตอนนี้ user ต้องพิมพ์เองว่าอยู่ที่ไหน

Clipboard read/write
"คัดลอกข้อความนี้ให้หน่อย" หรือ "อ่านที่ฉัน copy ไว้" — เชื่อม Haku เข้ากับ workflow นอก app ได้เลย ไม่มี permission พิเศษ (API 28+)

ระดับ 3 — ถ้าทำได้ = ต่างจากทุก app ในตลาด
Accessibility Service → อ่าน notification
Haku เห็น notification จาก LINE, email, calendar reminder → เชื่อมเข้า memory → "เมื่อกี้ Boss ส่งอะไรมา?" ตอบได้เลย — นี่คือ จุดที่ก้าวไปสู่ Haku OS ตาม roadmap

Share Sheet Integration
ผู้ใช้ share อะไรก็ได้จาก app ไหนก็ได้ → Haku รับ → log อัตโนมัติ เหมือน "inbox ส่วนตัว" สำหรับทุกอย่างที่ผ่านมือถือ