# 📦 Haku (箱) — Proactive OS & Sovereign AI Life Logger

> **"Redefining personal intelligence with Sovereign AI Architecture."**
>
> เรากำลังสร้างอินเทอร์เฟซแห่งอนาคตที่จะเปลี่ยนสมาร์ทโฟนแบบเดิมๆ ให้กลายเป็น **"Intelligent Phone"**

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-iOS%20%7C%20Android-lightgrey?logo=apple)](https://haku.bbpillow.com)
[![AI](https://img.shields.io/badge/AI-100%25%20On--Device-brightgreen)](https://haku.bbpillow.com)
[![License](https://img.shields.io/badge/License-Proprietary-red)](LICENSE)

---

Haku (箱) คือ **"ระบบปฏิบัติการชีวิตส่วนตัว" (Private Life OS)** ที่ทำงานเป็นเสมือนสมองที่สองของคุณ เราสร้าง Haku ขึ้นมาเพื่อแก้ปัญหา AI ในตลาดปัจจุบันที่ต้องแลกความสะดวกสบายมาด้วยความลับส่วนตัว Haku ขับเคลื่อนด้วยระบบ **Proactive AI** ที่ทำงานแบบ **On-Device 100%** — ปลอดภัย ไร้รอยต่อ และเคารพความเป็นส่วนตัวขั้นสูงสุด

---

## 🎯 Vision & Purpose — วิสัยทัศน์และจุดประสงค์

เป้าหมายหลักของ Haku คือการคืน **อธิปไตยทางข้อมูล (Data Sovereignty)** ให้กับผู้ใช้งาน

| # | Problem | Why It Matters |
|---|---------|----------------|
| 1 | **Privacy Leaks from Cloud AI** | ChatGPT, Gemini ส่งข้อมูลส่วนตัวออก server — ผู้ใช้ไม่รู้ว่าข้อมูลไปไหน |
| 2 | **Passive AI (Prompt Burden)** | AI รอรับ prompt — ผู้ใช้ต้องรู้จักถามเองตลอด แทนที่จะให้ AI ช่วยก่อน |
| 3 | **Data Sovereignty** | Big Tech ผูกขาดข้อมูลชีวิตผู้ใช้ ไม่มีทางเลือกที่ privacy-first จริงๆ |

- เราต้องการ AI ที่แก้ปัญหาความปลอดภัยและการถูกแอบฟัง — ข้อมูลทุกอย่างจบในมือถือ ไม่มีการส่งออกเพื่อเทรนโมเดล
- เรามุ่งแก้ไข **Prompt Burden** โดยเปลี่ยนจากระบบที่ต้องรอรับคำสั่ง (Passive) มาเป็นระบบที่ "ทักก่อน (Proactive)"
- ระบบช่วยจัดสรรภาระงาน ลดงานซ้ำซ้อน และลดภาวะหมดไฟ (Burnout) ทั้งในระดับบุคคลและองค์กร

---

## ✨ Core Features & Innovations — จุดเด่นและนวัตกรรม

- **100% On-Device Sovereign AI** — ทำงานบนชิป NPU โดยไม่มีการส่งข้อมูลออกไปประมวลผลบน Cloud ภายนอก (Zero Data Leakage)
- **Proactive Intelligence** — อาศัยเซนเซอร์ในโทรศัพท์ (พิกัด, การเคลื่อนไหว, เวลา, แบตเตอรี่) เป็น Trigger เพื่อประเมินและทำงานแทนผู้ใช้โดยอัตโนมัติ
- **Zero-Token Workers** — ผลักภาระงานพื้นฐาน (ปฏิทิน, เตือนความจำ) ให้ Rule-based Workers จัดการ เพื่อสงวนทรัพยากร SLM ไว้สำหรับงานที่ซับซ้อนจริงๆ
- **3-Tier Memory System** — Working Memory (RAM) + Episodic Memory (SQLite FTS5 + BM25) + Semantic Memory (sqlite-vec) — Haku จำได้แม้หลังจากที่ลบแชทแล้ว
- **Asynchronous Batch Processing** — ประหยัดแบตเตอรี่โดยประมวลผลงานหนักเฉพาะตอนอุปกรณ์เสียบชาร์จและปิดหน้าจอ
- **Agent-to-Agent Protocol (A2A)** — โปรโตคอล E2E Encrypted ให้ Haku ของผู้ใช้สองคนประสานงานกันโดยตรง ไม่ผ่าน Central Server

---

## 🏗️ System Architecture & Tech Stack

ระบบ Haku ถูกออกแบบภายใต้สถาปัตยกรรม 4 เลเยอร์หลัก:

```
┌────────────────────────────────────────────────────┐
│  Real-Time Layer    — User Input & Chat Interface  │
├────────────────────────────────────────────────────┤
│  Trigger Layer      — Sensors, Calendar, Location  │
├────────────────────────────────────────────────────┤
│  Background Layer   — Memory Consolidation, RAG    │
├────────────────────────────────────────────────────┤
│  Notification Layer — Proactive Alerts & Briefs    │
└────────────────────────────────────────────────────┘
```

### On-Device AI Pipeline

```
User Input
    │
    ▼
SmartPreprocessor  (rule-based, zero LLM cost)
├── CalendarWorker     → schedule intents
├── ReminderWorker     → reminder intents
└── WebSearchWorker    → search intents
    │
    ▼  (unmatched → general inference path)
    │
Face LLM  (LiteRT-LM, stateful KV cache on NPU)
├── Gemma 3 1B   — fast, low memory    (~1K context)
├── Gemma 4 E2B  — balanced            (4K context)
└── Gemma 4 E4B  — most capable        (8K context)
    │
    ▼
3-Tier Memory System
├── Working Memory   — last 8 turns in RAM  (~800 tokens)
├── Episodic Memory  — SQLite FTS5 + BM25 retrieval
└── Semantic Memory  — entity wiki pages + sqlite-vec
```

### Tech Stack

| Layer | Technology | Rationale |
|-------|------------|-----------|
| **Frontend & UI** | Flutter (Dart) + Impeller | Native-grade performance, single codebase for iOS & Android, 120 Hz rendering |
| **Core Database** | SQLite via sqflite FFI | Stable, standard SQL, natively supports sqlite-vec extension |
| **Full-text Search** | SQLite FTS5 (BM25) | In-process episodic memory retrieval, zero dependency overhead |
| **Vector Engine** | sqlite-vec | Zero-dependency C extension, runs in the same process as the app |
| **AI Runtime** | LiteRT-LM v0.10.0 (Google) | Stateful KV cache, direct NPU access — replaces deprecated MediaPipe |
| **AI Models** | Gemma 3 1B / Gemma 4 E2B / E4B | 4-bit quantized SLMs: best balance of reasoning and memory on mobile |
| **Location / Sensors** | Native Platform Channels | Fine-grained battery control (Significant Change on iOS, Fused Provider on Android) |
| **Encryption** | SQLCipher | All user data encrypted at rest |

### Android GPU Strategy

| GPU | Inference Backend | Note |
|-----|-------------------|------|
| **Adreno 700+** | ✅ OpenCL | Best performance on Qualcomm chipsets |
| **Mali** | ✅ CPU-only | Safe, consistent performance |
| **Vulkan (mobile)** | ❌ Disabled | 15–16× slower than CPU on Mali — never use |

---

## 🧠 3-Tier Memory Architecture

> Haku never forgets — even when you clear your chat history.

| Tier | Storage | Purpose |
|------|---------|---------|
| **Working Memory** | RAM (~800 tokens) | Active conversation context, last 8 turns |
| **Episodic Memory** | SQLite FTS5 | Compressed chat logs, BM25 semantic retrieval |
| **Semantic Memory** | sqlite-vec + Wiki pages | Distilled facts per entity, contradiction detection, confidence scoring |

Memory consolidation runs nightly via WorkManager (Android) / BGProcessingTask (iOS) — only when plugged in and charging.

**Token Budget — Gemma 4 E4B (8 192-token context):**

```
System + persona    :   300 tokens
Session resume      :   300 tokens  ← top facts + today's calendar
Working memory      :   800 tokens  ← last 8 turns
Episodic FTS5       : 1 000 tokens  ← BM25 top-3 matches
Wiki pages          : 1 200 tokens  ← top-2 entity pages
User message        :   300 tokens
────────────────────────────────────
Total input         : 3 900 tokens  (2 300-token safety margin)
Response budget     : 2 000 tokens
```

---

## 🗺️ Roadmap — แผนการดำเนินงาน

### Product Phase Map

| Phase | Name | Goal | Status |
|-------|------|------|--------|
| **1** | Privacy Core | Privacy-first foundation, encrypted life logging | ✅ Complete |
| **2** | Proactive Intelligence | Proactive triggers, Meeting Pre-Flight, SLM background service | 🟡 ~90% |
| **3** | B2C Monetization | AI Personas, Skill Modules (IAP) | 🔴 Planned |
| **4** | Analytics & Deep Personalization | RAG search, pattern recognition, Cognitive Guardrails | 🟡 ~45% |
| **5** | B2B Agent Protocol | A2A identity, Meeting Negotiation, Task Delegation | 🔴 Planned |
| **6** | Haku OS Vision | Sovereign AI national infrastructure | 💡 Concept |

### 18-Month Execution Plan (depa Grant)

| Period | Phase | Key Deliverables |
|--------|-------|-----------------|
| **Month 1–6** | Sovereign Core & Context Awareness | Voice input (Whisper-Tiny, on-device), Meeting Pre-Flight RAG, A2A identity foundation (Android Keystore), Privacy Transparency Screen |
| **Month 7–12** | A2A Network & B2B MVP | Haku-to-Haku peer pairing, WiFi Direct transport, E2E encrypted relay, SME beta — Kalasin Chamber of Commerce |
| **Month 13–18** | Proactive Guardrails & Commercialization | Cognitive Guardrails, B2B commercial release, AI Personas (B2C), national expansion |

---

## 🚀 Getting Started

> **Prerequisites:** Flutter 3.x · Android SDK · Xcode (for iOS builds)

```bash
# Clone the repository
git clone https://github.com/Miuu-hz/haku-project.git
cd haku-project

# Install dependencies
flutter pub get

# Run on a physical device
# (on-device AI inference requires real hardware — simulator not supported)
flutter run
```

**AI Model Setup**

Haku downloads models on first launch from HuggingFace. To set up manually, place `.litertlm` files under `assets/models/`:

```
assets/models/
├── gemma3-1b-it-int4.litertlm      ← fast, low memory
├── gemma4-e2b-it-int4.litertlm     ← balanced
└── gemma4-e4b-it-int4.litertlm     ← most capable
```

> **Note:** Cloud providers (Gemini / Claude / OpenAI / OpenRouter) are available as fallback in developer settings for testing purposes only. All production user data is processed entirely on-device.

---

## 🔒 Privacy Principles

These are non-negotiable and verified in every release:

1. **Zero network calls** for user data — everything stays on device
2. **No analytics SDKs** that transmit data externally
3. **No hardcoded secrets** — Keychain (iOS) / Android Keystore
4. **Data minimization** — only store what is strictly necessary
5. **Encryption at rest** — SQLCipher for all user data, always

---

## ⚡ Battery & Performance

| Rule | Target |
|------|--------|
| AI inference | On user request only, or idle + charging |
| Location tracking | Significant Change API — never continuous GPS |
| Heavy processing | WorkManager (Android) / BGProcessingTask (iOS) |
| Daily background drain | **< 10%** battery per day |
| Thermal guard | Pause inference if battery < 20% or device overheating |

---

## 💼 Business Model

```
Freemium  (Core free — grow the user base)
    ↓
B2C: AI Personas + Skill Modules  (In-App Purchase)
    ↓
B2B: Team Delegation Protocol     (Subscription)
    ↓
Vision: Haku OS                   (National Sovereign AI Infrastructure)
```

---

## 🌐 Website

[haku.bbpillow.com](https://haku.bbpillow.com)

---

*Haku — your life, your data, your rules.*
