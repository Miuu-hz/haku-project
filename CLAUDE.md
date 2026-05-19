# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Build
flutter build apk --debug          # debug APK
flutter build apk --release        # release APK

# Run / Install
flutter run --device-id emulator-5554    # run on emulator (hot reload)
flutter install --device-id emulator-5554

# Analyze & Format
dart analyze lib/                   # must be zero errors before committing
dart format lib/

# Single-file check
dart analyze lib/services/foo.dart
```

No automated test suite exists yet — testing is done manually on device.

---

## Architecture: Message Processing Pipeline

Every user message in `chat_screen.dart → sendToAI()` passes through sequential stages:

```
User message
  │
  ├─ 0.   QuickAction          rule-based, 0 LLM — greetings, name recall
  ├─ 0.5  DeviceCommandIntentDetector  rule-based, 0 LLM — flashlight, alarm, check-in…
  ├─ 1.   SmartPreprocessor    rule-based workers, 0 LLM — calendar/reminder/search detect
  ├─ 1.5  PreClassify          LLM call (~50 token output) — intent + English summary
  ├─ 2.   TagContextService    queries SQLite FTS + WikiService using PreClassify tags
  ├─ 3.   Face LLM             Thai natural-language response (Stage 1)
  └─ 4.   SecretChatService.logExchange()  async English log → RAG index + Wiki write
```

Stages 0–2 are purely rule-based and must stay 0 LLM tokens. Stage 3 is the only user-facing LLM call.

---

## Key Services

| Service | Role |
|---|---|
| `secret_chat_service.dart` | After Face LLM responds: extracts English log entry, drives `BigManager` dispatch |
| `smart_preprocessor.dart` | Workers: FactWorker, CalendarWorker, ReminderWorker, GoalWorker, HealthDoctor |
| `prompt_builder.dart` | All LLM prompts — `buildGemmaPrompt`, `buildPreClassifyPrompt`, `buildManagerPrompt` |
| `device_command_intent_detector.dart` | Step 0.5 — regex-detect and execute device commands with zero LLM |
| `device_command_service.dart` | Flutter↔Android MethodChannel bridge (`com.example.haku/device`) |
| `geofence_service.dart` | Location monitoring (significant-change, not continuous GPS) |
| `nominatim_service.dart` | Reverse geocode GPS→area name (OSM, non-profit) — used by check-in + nearby search |
| `web_search_service.dart` | Wikipedia → SearXNG (parallel race) → Google scraping fallback |
| `rag_service.dart` | HybridVectorSearch: BM25 FTS5 + sqlite-vec cosine similarity |
| `wiki_service.dart` | Knowledge graph — facts written per tag/location after every exchange |
| `mvp_trigger_service.dart` | Foreground proactive triggers (time + location) |
| `background_task_service.dart` | AlarmManager daily triggers (09:00, 20:00) — survives app kill |
| `llm_provider_manager.dart` | Switches between: LiteRT on-device / Gemini / Claude / OpenRouter / ThaiLLM |
| `database_helper.dart` | SQLite + SQLCipher: `entries`, `chat_log` (FTS5), `device_command_log` |

---

## 3-Tier Memory Architecture

```
Working memory   → LLM KV-cache (in-session, resets on cold start)
Episodic memory  → SQLite chat_log FTS5 BM25 (searchable English summaries)
Semantic memory  → WikiService knowledge_pages (knowledge graph per tag/location)
```

RAG read path (before each LLM call): FTS5 + WikiService.query() + RAGService.buildContext() + Calendar  
RAG write path (after each reply): SecretChatService → RAGService.indexEntry() + WikiService.onNewFact()

---

## Android Native Layer

Kotlin files in `android/app/src/main/kotlin/com/example/haku/`:

| File | Role |
|---|---|
| `DeviceCommandHandler.kt` | Executes all device commands received via MethodChannel |
| `MainActivity.kt` | Registers MethodChannel `com.example.haku/device` |
| `service/HakuForegroundService.kt` | Foreground service (dataSync type) |
| `receiver/BootReceiver.kt` | Reschedules alarms after reboot |
| `receiver/ChargingBroadcastReceiver.kt` | Fires ChargingTrigger when charger connected |
| `receiver/NotificationAlarmReceiver.kt` | Shows proactive notification from AlarmManager |

**MethodChannel protocol:** Flutter calls `execute` with `{command: String, params: Map}` → Kotlin returns `{success: bool, ...fields}`.

---

## Device Commands (step 0.5)

Patterns detected in `DeviceCommandIntentDetector` and executed without LLM:

- **Flashlight**: เปิดไฟฉาย / ปิดไฟฉาย / toggle
- **Alarm**: ตั้งปลุก + Thai time (ตีN, Nทุ่ม, บ่ายN, H:MM, เที่ยง, เที่ยงคืน, ครึ่ง)
- **Timer**: จับเวลา N นาที/ชั่วโมง/วินาที
- **Ringer**: เงียบ / สั่น / เปิดเสียง — DND fallback to vibrate on API 23+
- **Volume**: เพิ่มเสียง / ลดเสียง (STREAM_RING)
- **Check-in**: เช็คอิน → GPS → SavedPlaces (300m) → Nominatim → diary Entry
- **Open app / dial / SMS / URL / settings / maps / camera / gallery**
- **Battery / Network status query**

Security tiers defined in `DeviceCommandGate`: auto / notify / confirm / biometric.  
All executions logged to `device_command_log` table via `DeviceCommandAudit`.

---

## Location & Privacy Notes

- GPS exits the device **once** via Nominatim (OSM non-profit) for reverse geocoding only
- `searchNearby()` in `WebSearchService` converts GPS→area name, then searches by name — Overpass/Google never see exact coordinates
- `GeofenceService.lastKnownPosition` is public; fresh GPS uses `LocationService.getCurrentPosition()` (10s timeout)
- Emulator has no GPS — check-in will fail unless you set mock location in Extended Controls → Location
