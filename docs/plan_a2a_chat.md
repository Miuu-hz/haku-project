# Plan: A2A (Haku-to-Haku) Chat — Detailed Implementation

> Status: Planning  
> Phase: B1 (MVP relay)  
> Author: CTO / Senior Architect

---

## 1. Goal

Build a privacy-first, end-to-end encrypted peer communication layer for Haku.  
Two Haku devices can pair in-person (QR / NFC), exchange encrypted messages via a
self-hosted relay, attach documents, and share curated knowledge context — all
without any plaintext ever leaving the devices.

**Done = paired → chatting → context attached → privacy guaranteed.**

---

## 2. Scope

**In scope (Phase B1)**
- Device identity (UUID + shared AES key per peer)
- Peer pairing via QR code (two-step handshake)
- Encrypted A2A chat screen (send / receive text)
- Document attachment (file pick → local path stored)
- Privacy filter (hard-block sensitive data before any share)
- Smart context filter (vector search → minimal relevant bundle)
- Person positioning in Wiki (KnowledgePage per A2A contact)
- Self-hosted relay transport (WebSocket)
- Offline queue (outbox retry when relay unreachable)

**Out of scope (Phase B2+)**
- NFC tap pairing
- On-device OCR (google_mlkit)
- WiFi Direct (no-relay mode)
- Voice messages
- Group chat

---

## 3. Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│                   A2A Chat Flow                     │
│                                                     │
│  User types message                                 │
│       │                                             │
│       ▼                                             │
│  A2AContextFilter.buildRelevantContext()            │
│  ├── VectorService.searchFacts(msg, limit=10)       │
│  ├── WikiService.query(msg, limit=3)                │
│  └── A2APrivacyFilter.filter(bundle, settings)      │
│       │                                             │
│       ▼                                             │
│  A2AMessageService.sendMessage(peerId, text, ctx)   │
│  ├── Build A2ABundle { text, contextSnapshot }      │
│  ├── JSON → encrypt with peer's AES key (CBC-256)   │
│  └── A2ATransportService.send(peerId, ciphertext)   │
│       │                                             │
│       ├── [online]  → WebSocket → relay → peer     │
│       └── [offline] → INSERT INTO a2a_outbox        │
│                                                     │
│  Receive side:                                      │
│  relay → WebSocket → A2ATransportService.onMessage  │
│  → INSERT INTO a2a_inbox                            │
│  → A2AMessageService.processInbox()                 │
│    ├── Decrypt with own AES key                     │
│    ├── UPDATE KnowledgePage (last_topic)            │
│    └── INSERT INTO a2a_messages (direction=1)       │
└─────────────────────────────────────────────────────┘
```

---

## 4. Crypto Design (MVP)

**No new libraries needed** — reuse existing `encrypt` package (AES-256-CBC).

### Key Exchange (In-person QR Pairing)

```
Step 1: Device A shows QR
  Payload: { v:1, id:"uuid_a", key:"base64(K_a)", name:"Haku A" }
  K_a = 32 random bytes (flutter_secure_storage)

Step 2: Device B scans A's QR
  → Stores A's peer record with K_a
  → Shows its own QR:
  Payload: { v:1, id:"uuid_b", key:"base64(K_b)", name:"Haku B" }

Step 3: Device A scans B's QR
  → Stores B's peer record with K_b
  → Pairing complete
```

### Message Encryption

```
A sends to B:
  plaintext = json { content, contextBundle?, timestamp }
  ciphertext = AES-256-CBC(plaintext, key=K_b, iv=random16)
  wire = base64(iv + ciphertext)

B receives from A:
  raw = base64decode(wire)
  iv = raw[0..15]
  cipher = raw[16..]
  plaintext = AES-256-CBC-decrypt(cipher, key=K_b, iv=iv)
```

Each device uses **its own key** to encrypt outgoing messages (which the other
device has from pairing). Each device uses **its own key** to decrypt incoming.

---

## 5. Person Positioning in Wiki

When a peer is paired, create a `KnowledgePage` for them automatically.

```
id:          "a2a_contact:<uuid>"
entity_type: "a2a_contact"
title:       "Miuu's Haku"
raw_facts:   [
  { text: "role: project_manager", addedAt: ... },
  { text: "relationship: colleague", addedAt: ... },
  { text: "last_topic: Q2 roadmap", addedAt: ... },
  { text: "shared_topics: [flutter, AI]", addedAt: ... }
]
```

**When updated:**
- After every A2A session → SLM extracts topics → `WikiService.onNewFact()`
- On bundle receive → merge peer's self-declared role
- Wiki page is NEVER shared back to peer (hard-blocked by privacy filter)

**SLM context injection (in A2AChatScreen):**
```
System: "You are helping [User] communicate with: Miuu's Haku
         Role: Project Manager | Relationship: Colleague
         Last discussed: Q2 roadmap | Shared: Flutter, AI
         Prioritise task-oriented, business-level tone."
```

### New method in HakuIdentityService

```dart
Future<void> upsertPeerWikiPage(A2APeer peer, {String? newTopic}) async {
  await WikiService().getOrCreate(
    'a2a_contact:${peer.deviceId}',
    entityType: 'a2a_contact',
    title: peer.nickname,
  );
  if (newTopic != null) {
    await WikiService().onNewFact(
      category: 'a2a_contact',
      key: peer.deviceId,
      content: 'last_topic: $newTopic',
    );
  }
}
```

---

## 6. Privacy Filter (`filter_sensor`)

**All outgoing data MUST pass through `A2APrivacyFilter` before encryption.**

### Hard block (never share — no toggle can enable these)

| Data | Source Table / Category |
|------|------------------------|
| Diary entry content | `entries.content` |
| Location coordinates | `entries.latitude / longitude` |
| Location names | `entries.location_name` |
| Mood scores | `entries.mood` / fact category `mood` |
| Health data | worker output, category `health` |
| Full chat logs | `secret_chat_log` |
| Financial facts | category `finance` |
| Personal relationship | category `personal` |
| Private goals | category `goal` |
| Other contacts | entity_type `person`, `a2a_contact` |

### Consent-gated (user must toggle ON before sharing)

| Data | Default |
|------|---------|
| Work / project facts | OFF |
| Skills & expertise | OFF |
| Calendar free/busy slots (no event titles) | OFF |
| Topic interests | OFF |

### Always safe

| Data |
|------|
| Encrypted message text (E2E) |
| Task status (in / out, estimate) |
| Negotiated time slots (free / busy only) |

### Implementation sketch

```dart
// lib/services/a2a_privacy_filter.dart

class A2APrivacyFilter {
  static const _hardBlockCategories = {'finance', 'personal', 'health', 'goal', 'mood'};
  static const _hardBlockEntityTypes = {'person', 'a2a_contact'};

  Map<String, dynamic> filter(
    Map<String, dynamic> rawBundle,
    A2AShareSettings settings,
  ) {
    final facts = (rawBundle['facts'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .where((f) {
          final cat = f['category'] as String? ?? '';
          if (_hardBlockCategories.contains(cat)) return false;
          if (cat == 'work' && !settings.shareWork) return false;
          if (cat == 'skill' && !settings.shareSkills) return false;
          return true;
        })
        .map((f) => Map<String, dynamic>.from(f)..remove('content')
              ..['content'] = _sanitize(f['content'] as String? ?? ''))
        .toList();

    final pages = (rawBundle['knowledgePages'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .where((p) => !_hardBlockEntityTypes.contains(p['entityType']))
        .toList();

    return {'facts': facts, 'knowledgePages': pages};
  }

  // Strip GPS coordinates from any text field
  String _sanitize(String text) =>
      text.replaceAll(RegExp(r'\b\d{1,3}\.\d{4,},\s*\d{1,3}\.\d{4,}\b'), '[location]');
}
```

---

## 7. Smart Context Filter (`filter_search`)

Before attaching context to an outgoing A2A message, run relevance search.
Goal: send only facts relevant to the current message — never dump the full Wiki.

```dart
// lib/services/a2a_context_filter.dart

class A2AContextFilter {
  static const int kMaxFacts = 10;
  static const int kMaxWikiPages = 3;

  Future<Map<String, dynamic>> buildRelevantContext({
    required String message,
    required String peerId,
    required A2AShareSettings settings,
  }) async {
    // 1. Semantic search — facts relevant to this message
    final vectorResults = await UnifiedVectorService().search(message, limit: kMaxFacts);
    final relevantFacts = vectorResults.map((r) => {
      'id': r.item.id,
      'category': r.item.metadata?['category'] ?? '',
      'content': r.item.content,
      'score': r.score,
    }).toList();

    // 2. Wiki pages relevant to message topic
    final wikiPages = await WikiService().query(message, limit: kMaxWikiPages);
    final pageMaps = wikiPages.map((p) => p.toMap()).toList();

    // 3. Build raw bundle
    final rawBundle = {'facts': relevantFacts, 'knowledgePages': pageMaps};

    // 4. Apply privacy filter on top
    return A2APrivacyFilter().filter(rawBundle, settings);
  }
}
```

**Flow diagram:**
```
message text
    │
    ├─ VectorService.search()       → top-N semantically similar facts
    ├─ WikiService.query()          → related knowledge pages
    └─ A2APrivacyFilter.filter()    → strip blocked categories / sanitize
    │
    ▼
{ facts: [...], knowledgePages: [...] }   ← attached to outgoing message
```

---

## 8. Database — 4 New Tables

Current version: 3 → New version: **4**

```sql
-- Paired peers
CREATE TABLE a2a_peers (
  device_id      TEXT PRIMARY KEY,
  nickname       TEXT NOT NULL,
  shared_key     TEXT NOT NULL,   -- base64 AES-256 key (stored in encrypted DB)
  avatar_emoji   TEXT DEFAULT '🤖',
  paired_at      INTEGER NOT NULL,
  last_seen      INTEGER,
  share_settings TEXT DEFAULT '{}'  -- JSON: A2AShareSettings
);

-- Chat messages (both directions)
CREATE TABLE a2a_messages (
  id              TEXT PRIMARY KEY,   -- client-generated UUID
  peer_id         TEXT NOT NULL REFERENCES a2a_peers(device_id),
  direction       INTEGER NOT NULL,   -- 0=sent  1=received
  content         TEXT NOT NULL,
  attachment_type TEXT,               -- 'document' | 'photo' | null
  attachment_ref  TEXT,               -- local file path
  context_bundle  TEXT,               -- JSON snapshot (filtered) sent/received
  timestamp       INTEGER NOT NULL,
  is_read         INTEGER DEFAULT 0
);

-- Outbound queue: retry when relay is offline
CREATE TABLE a2a_outbox (
  id           TEXT PRIMARY KEY,
  peer_id      TEXT NOT NULL,
  ciphertext   TEXT NOT NULL,   -- base64 already-encrypted payload
  created_at   INTEGER NOT NULL,
  retry_count  INTEGER DEFAULT 0,
  expires_at   INTEGER           -- drop after 24 h
);

-- Inbound queue: pending decryption / processing
CREATE TABLE a2a_inbox (
  id          TEXT PRIMARY KEY,
  sender_id   TEXT NOT NULL,
  ciphertext  TEXT NOT NULL,
  received_at INTEGER NOT NULL,
  processed   INTEGER DEFAULT 0
);
```

**Migration in `_onUpgrade`:**
```dart
if (oldVersion < 4) {
  await _createA2ATables(db);
}
```

---

## 9. New Dependencies

```yaml
# pubspec.yaml additions
qr_flutter: ^4.1.0          # generate own QR for pairing
mobile_scanner: ^5.2.0      # scan peer's QR (camera)
web_socket_channel: ^3.0.2  # relay WebSocket transport
```

No new crypto dependencies — reuse existing `encrypt: ^5.0.1`.

---

## 10. Files to Create

### Models

| File | Key Fields |
|------|-----------|
| `lib/models/a2a_share_settings.dart` | shareWork, shareSkills, shareCalendarSlots, shareTopics |
| `lib/models/a2a_peer.dart` | deviceId, nickname, sharedKey, avatarEmoji, pairedAt, lastSeen, shareSettings |
| `lib/models/a2a_message.dart` | id, peerId, direction, content, attachmentType, attachmentRef, contextBundle, timestamp, isRead |
| `lib/models/a2a_context_bundle.dart` | relevantFacts, wikiSummaries, peerRoleHint |

### Services

| File | Responsibility |
|------|---------------|
| `lib/services/haku_identity_service.dart` | Own UUID + per-peer AES key, `upsertPeerWikiPage()` |
| `lib/services/a2a_privacy_filter.dart` | Hard-block + consent-gated filter before any export |
| `lib/services/a2a_context_filter.dart` | Vector search → minimal relevant bundle |
| `lib/services/a2a_transport_service.dart` | WebSocket relay: connect / send / receive / retry |
| `lib/services/a2a_message_service.dart` | Encrypt / decrypt / store / deliver / processInbox |
| `lib/services/a2a_document_service.dart` | File pick → local copy → return attachment path |

### Screens

| File | Purpose |
|------|---------|
| `lib/screens/peer_pairing_screen.dart` | Step 1: show own QR · Step 2: scan peer QR |
| `lib/screens/a2a_peers_list_screen.dart` | List paired peers, FAB → pairing screen |
| `lib/screens/a2a_chat_screen.dart` | Chat UI with context badge + attach button |
| `lib/screens/a2a_privacy_settings_screen.dart` | Per-peer share toggles |

### Navigation change

Add 4th tab "A2A" (icon: `Icons.hub_outlined`) to `HakuGlassNavBar._tabs` and
wire `A2APeersListScreen` in `MainNavigationScreen`.

---

## 11. A2A Chat Screen — UI Spec

```
┌─────────────────────────────────────────────┐
│ ←  🤖 Miuu's Haku           🔒  ⚙️         │
│    Project Manager · last seen 2m ago        │  ← from Wiki
├─────────────────────────────────────────────┤
│                                             │
│ [bubble] ช่วยสรุป Q2 report หน่อย         │  received
│                                             │
│ [SLM card]  📄 Thinking with context...    │  local SLM
│                                             │
│         สรุป Q2: revenue +12%… [you] →    │  sent
│         📄 Q2_report.pdf                   │
│                                             │
│ [context badge] 🧠 3 work facts attached   │  privacy-filtered ctx
│                                             │
├─────────────────────────────────────────────┤
│  📎   [Type a message…]         🎤   ➤     │
└─────────────────────────────────────────────┘
```

---

## 12. Relay Backend — Decision

**Do NOT use Supabase** as the A2A relay.  
Supabase stores metadata (social graph: who talks to whom, timestamps) on
third-party servers, which contradicts Haku's privacy promise.

| Option | Verdict |
|--------|---------|
| **Supabase Realtime** | ❌ Metadata exposure, contradicts privacy brand |
| **Self-hosted minimal relay** | ✅ Recommended for Phase B1 |
| **WiFi Direct (no relay)** | ✅ Phase B2 — true zero-server |

### Self-hosted relay design

A semantically blind message queue (~100 lines Go / Node.js):
- Accepts: `{ to: uuid, from: uuid, ciphertext: base64 }`
- Stores: max 24 hours
- Delivers: when recipient connects (WebSocket push)
- Knows: sender UUID, recipient UUID, timestamp, blob size — **no plaintext**
- Delete on delivery

Deploy to: **fly.io free tier** (always-on, 256 MB RAM is sufficient)

Supabase MAY be used in future for:
- Non-PII app telemetry (model download stats, crash counts)
- Only with full opt-in consent, completely isolated from A2A messaging

---

## 13. Relay Wire Protocol

```json
// Client → Relay (after WebSocket open)
{ "type": "auth",  "deviceId": "uuid" }

// Client → Relay (send message)
{ "type": "send",  "to": "uuid_b",  "msgId": "...",  "ciphertext": "base64" }

// Relay → Client (deliver incoming)
{ "type": "incoming",  "from": "uuid_a",  "msgId": "...",  "ciphertext": "base64" }

// Relay → Client (ack after storage)
{ "type": "ack",  "msgId": "..." }
```

---

## 14. Task Sequence

- [ ] **TASK-1** — Add 4 tables to `DatabaseHelper` (version 3→4, migration)
- [ ] **TASK-2** — `HakuIdentityService` (device UUID + per-peer key + `upsertPeerWikiPage`)
- [ ] **TASK-3** — `A2AShareSettings` model + `A2APrivacyFilter` service
- [ ] **TASK-4** — `A2APeer`, `A2AMessage`, `A2AContextBundle` models
- [ ] **TASK-5** — `A2AContextFilter` service (vector search → minimal bundle)
- [ ] **TASK-6** — `A2ATransportService` (WebSocket relay + outbox retry)
- [ ] **TASK-7** — `A2AMessageService` (encrypt / decrypt / store / processInbox)
- [ ] **TASK-8** — `A2ADocumentService` (file pick → local copy)
- [ ] **TASK-9** — `PeerPairingScreen` (two-step QR handshake UI)
- [ ] **TASK-10** — `A2APeersListScreen`
- [ ] **TASK-11** — `A2AChatScreen` (full chat UI + context badge + attach)
- [ ] **TASK-12** — `A2APrivacySettingsScreen` (per-peer toggle UI)
- [ ] **TASK-13** — Wire into `MainNavigationScreen` (add 4th tab)

---

## 15. Verification Checklist

- [ ] Pair Device A ↔ Device B via QR → both appear in peers list
- [ ] Wiki page created for each peer on pairing
- [ ] Send message A→B → B receives decrypted text correctly
- [ ] Attach PDF → file stored locally → path referenced in message
- [ ] Kill app mid-send → message retries from outbox on reconnect
- [ ] Privacy filter: manually inspect exported bundle — no location / mood / diary
- [ ] Smart filter: send "Flutter question" → bundle contains only Flutter-related facts
- [ ] Privacy settings toggle: enable "share work" → work facts appear in bundle
- [ ] Chat header shows peer role from Wiki page

---

## 16. Risk Register

| Risk | Mitigation |
|------|-----------|
| QR key leaks (shoulder surfing) | Pairing in-person only, keys rotate-able per peer |
| Relay stores metadata | Open-source relay so user can audit or self-host |
| `a2a_outbox` grows unbounded | `expires_at` field, sweep job deletes after 24 h |
| SLM injects peer facts into wrong context | Namespace Wiki IDs as `a2a_contact:<uuid>` |
| Large context bundle slows message | Hard cap: maxFacts=10, maxWikiPages=3 |
| `mobile_scanner` iOS privacy prompts | NSCameraUsageDescription already in Info.plist (to verify) |
