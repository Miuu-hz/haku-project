# Haku (箱) — Private Life OS

> Your AI companion that knows you deeply — and never tells anyone else.

[![Flutter](https://img.shields.io/badge/Flutter-3.x-blue)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-iOS%20%7C%20Android-green)](https://haku.bbpillow.com)
[![Version](https://img.shields.io/badge/Version-0.1.0-orange)](https://haku.bbpillow.com)

---

## What is Haku?

**Haku** is a privacy-first AI personal life logger that runs entirely on your device. No cloud. No subscriptions. No data leaks.

It is a personal AI that genuinely knows you — your schedule, your patterns, your context — and proactively helps before you even have to ask. Every thought, plan, and memory stays encrypted on your phone, owned entirely by you.

---

## The Problem We Solve

| # | Problem | Why It Matters |
|---|---------|----------------|
| 1 | **Privacy Leaks from Cloud AI** | ChatGPT and Gemini send your personal data to remote servers — you have no control over where it goes |
| 2 | **Passive AI (Prompt Burden)** | AI waits for commands. You always have to know what to ask. Real assistance means AI acts first |
| 3 | **Data Sovereignty** | Big Tech monopolizes your life data. There is no genuinely privacy-first alternative |

---

## How Haku Works

### On-Device AI Pipeline

Haku runs a Small Language Model (SLM) directly on your device's Neural Processing Unit (NPU) — no internet connection required for AI inference.

```
User Input
    │
    ▼
SmartPreprocessor  (rule-based, zero LLM cost)
├── CalendarWorker     → schedule intents
├── ReminderWorker     → reminder intents
└── WebSearchWorker    → search intents
    │
    ▼
Face LLM  (on-device, stateful KV cache)
├── Gemma 3 1B   — fast, low memory footprint
├── Gemma 4 E2B  — balanced  (4K context window)
└── Gemma 4 E4B  — most capable  (8K context window)
    │
    ▼
3-Tier Memory System
├── Working Memory   — last 8 turns in RAM  (~800 tokens)
├── Episodic Memory  — SQLite FTS5 + BM25 retrieval
└── Semantic Memory  — entity facts + wiki pages, vector search
```

### 3-Tier Memory Architecture

Haku never forgets — even when you clear your chat history:

| Tier | Storage | Purpose |
|------|---------|---------|
| **Working Memory** | RAM | Current conversation context |
| **Episodic Memory** | SQLite FTS5 | Compressed logs, BM25 full-text retrieval |
| **Semantic Memory** | sqlite-vec | Distilled facts per entity, contradiction detection, confidence scoring |

Memory consolidation runs nightly, only when your device is plugged in and charging.

**Token Budget (Gemma 4 4B / 8 192-token context):**

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

## Features & Roadmap

### ✅ Phase 1 — Privacy Core (Complete)

- **Life Logging** — log daily entries, activities, mood, and location
- **Timeline View** — scroll your personal history with full context
- **Daily AI Summary** — on-device digest of your day, no cloud needed
- **Encrypted Storage** — SQLCipher for all user data at rest
- **Location Tracking** — Significant Change API only; no continuous GPS drain

### 🟡 Phase 2 — Proactive Intelligence (~90% Complete)

- **Proactive Triggers** — Haku acts before you ask: meeting prep, schedule conflicts, contextual reminders
- **Meeting Pre-Flight** — 15-minute RAG briefing before every calendar event
- **Persistent SLM Service** — background model loaded for instant, zero-latency responses
- **User-Controlled Toggles** — full control over what Haku monitors

### 🔴 Phase 3 — B2C Monetization (Planned)

- **AI Personas** — customizable AI personalities (In-App Purchase)
- **Skill Modules** — domain-specific skill packs: cooking, fitness, finance

### 🟡 Phase 4 — Analytics & Deep Personalization (~45% Complete)

- **Semantic Search (RAG)** — ask questions about your own past, answered from your own data
- **Pattern Recognition** — weekly habit and behavior analysis
- **Cognitive Guardrails** — anomaly detection to protect high-stakes decisions (e.g. unusual transfers, out-of-character choices)

### 🔴 Phase 5 — B2B Agent-to-Agent Protocol (Planned)

- **A2A Identity Layer** — keypair on Android Keystore + E2E encrypted message bundles
- **Meeting Negotiation Protocol** — coordinate schedules between Haku instances sharing only availability, never raw calendar content
- **Task Delegation** — assign tasks between AI agents without a central server

### 💡 Phase 6 — Haku OS (Vision)

- **Haku as National Infrastructure** — a sovereign AI platform for Thailand, owned by its citizens

---

## Tech Stack

| Layer | Technology | Notes |
|-------|------------|-------|
| **Framework** | Flutter (Dart) | Cross-platform iOS + Android |
| **UI Engine** | Impeller | 120 Hz smooth rendering |
| **Database** | SQLite + sqflite FFI | Industry standard, extensible |
| **Full-text Search** | SQLite FTS5 (BM25) | Episodic memory retrieval |
| **Vector Search** | sqlite-vec | On-device RAG, zero server dependency |
| **AI Runtime** | LiteRT-LM v0.10.0 (Google) | Replaces deprecated MediaPipe |
| **AI Models** | Gemma 3 1B / Gemma 4 E2B / E4B | 4-bit quantized, NPU-optimized |
| **Location** | Significant Change / Fused Provider | Battery-efficient, not continuous |
| **Encryption** | SQLCipher | All user data encrypted at rest |

### Android GPU Rules

| GPU | Inference Backend |
|-----|-------------------|
| Adreno 700+ | ✅ OpenCL |
| Mali | ✅ CPU-only |
| Vulkan (mobile) | ❌ Never — 15–16× slower than CPU on Mali |

---

## Privacy Principles

These are non-negotiable:

1. **Zero network calls** for user data — everything stays on device
2. **No analytics SDKs** that transmit data externally
3. **No hardcoded secrets** — Keychain (iOS) / Android Keystore
4. **Data minimization** — only store what is strictly necessary
5. **Encryption at rest** — SQLCipher, always, for all user data

---

## Business Model

```
Freemium  (Core free — grow the user base)
    ↓
B2C: AI Personas + Skill Modules  (In-App Purchase)
    ↓
B2B: Team Delegation Protocol  (Subscription)
    ↓
Vision: Haku OS  (National Infrastructure)
```

---

## 18-Month Roadmap (depa Grant Plan)

| Period | Phase | Key Deliverables |
|--------|-------|-----------------|
| Month 1–6 | Sovereign Core & Context Awareness | Voice input (Whisper-Tiny on-device), Meeting Pre-Flight RAG, A2A identity foundation, Privacy Transparency Screen |
| Month 7–12 | A2A Network & B2B MVP | Haku-to-Haku pairing, WiFi Direct transport, SME beta with Kalasin Chamber of Commerce |
| Month 13–18 | Proactive Guardrails & Commercialization | Cognitive Guardrails, B2B commercial release, national expansion |

---

## Battery & Performance

- AI inference: only on user request, or when idle and charging
- Location: Significant Change only — never continuous GPS polling
- Heavy tasks: WorkManager (Android) / BGProcessingTask (iOS)
- Target: **< 10% battery drain per day** from all background tasks
- Thermal guard: pause inference when battery < 20% or device is overheating

---

## Website

[haku.bbpillow.com](https://haku.bbpillow.com)

---

*Haku — your life, your data, your rules.*
