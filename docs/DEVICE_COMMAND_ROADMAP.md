# Haku Device Command — Roadmap & Vision Alignment

> สอดคล้องกับปัญหา 3 ข้อ และเป้าหมาย 3 ข้อของ Haku

## สถานะปัจจุบัน (What we built)

`DeviceCommandService` + `DeviceCommandHandler` + `IntentDetector` ทำงานได้แล้วในโหมด **Passive**:
- ผู้ใช้พิมพ์ "เปิดไฟฉาย" → detect intent → execute
- รองรับ 20+ commands (flash, dial, SMS, settings, maps, etc.)

**แต่ยังไม่สอดคล้องกับวิสัยทัศน์ Haku เต็มที่**

---

## ทิศทางที่ต้องไป (Where we need to go)

### 1. จาก Passive → Proactive (แก้ Pain Point #2: The Prompt Burden)

**ปัญหา**: AI ต้องรอ user พิมพ์คำสั่ง → ไม่ใช่ Haku ที่ต้องการ
**ทางออก**: **Proactive Command Layer**

```
Trigger Event (MVPTriggerService)
         │
         ▼
┌─────────────────────┐
│ ProactiveCommand    │  ← ไม่มี user prompt
│   - ถึงบ้าน → เปิด WiFi
│   - ใกล้นัด → เปิด Maps
│   - เข้าประชุม → DND
│   - กลางคืน → Night Mode
└─────────┬───────────┘
          │
          ▼
   DeviceCommandService.execute()
```

**ตัวอย่าง Use Case**:
| Trigger | Context | Auto Command |
|---------|---------|-------------|
| GPS: ถึงบ้าน (19:00) | กลับจากที่ทำงาน | เปิด WiFi, ปิด mobile data, แจ้งเตือน "กลับถึงบ้านแล้ว" |
| GPS: ถึงที่ทำงาน (08:30) | วันธรรมดา | เปิด DND (Focus Mode), แสดง agenda วันนี้ |
| Calendar: อีก 15 นาทีมีนัด | อยู่นอกสถานที่ | เปิด Maps นำทางไปที่นัด |
| Time: 22:00 | อยู่บ้าน | เปิด Night Mode, ลด brightness, ปิด notification |
| Battery < 20% | ไม่ได้ชาร์จ | เปิด Battery Saver, แจ้งเตือนหาที่ชาร์จ |
| Charging + 22:00 | ชาร์จก่อนนอน | รัน Episodic Memory Consolidation (สรุปความจำ) |

---

### 2. จาก Open-loop → Privacy-Audit (แก้ Pain Point #1: Privacy Leaks)

**ปัญหา**: AI สั่งงานอะไรไปบ้าง user ไม่รู้ → ไม่ต่างจาก AI เจ้าอื่น
**ทางออก**: **Command Audit Trail + Permission Guard**

```
┌─────────────────────────────────────────────────────┐
│           CommandAuditLog (SQLite + SQLCipher)       │
├─────────────────────────────────────────────────────┤
│ timestamp  │ trigger   │ command      │ approved_by  │
│ 08:29:15   │ GPS-Work  │ dnd_on       │ auto         │
│ 08:29:15   │ GPS-Work  │ open_maps    │ biometric    │ ← sensitive
│ 19:05:22   │ GPS-Home  │ wifi_on      │ auto         │
│ 22:00:00   │ time      │ night_mode   │ auto         │
└─────────────────────────────────────────────────────┘
```

**Security Tiers**:
| Tier | Commands | Approval |
|------|----------|----------|
| 🟢 Auto | flashlight, settings, brightness | ไม่ต้องถาม |
| 🟡 Notify | open_app, share_text, open_camera | แจ้งเตือนหลังทำ |
| 🔴 Confirm | dial_phone, send_sms, send_email | ต้อง user กดยืนยัน |
| 🔒 Biometric | factory_reset, uninstall_app, lock_device | ต้อง Face ID/Fingerprint |

---

### 3. จาก Consumer → B2B/Enterprise (แก้ Pain Point #3: Data Sovereignty + Objective #2)

**ปัญหา**: ธุรกิจไทยต้องการ MDM ที่ไม่พึ่ง Google/Apple
**ทางออก**: **Enterprise Device Commands**

```
Haku for Work (MDM Commands)
├── Device Lock         → ล็อกอุปกรณ์พนักงานทันที
├── App Whitelist       → จำกัดแอปที่ใช้ได้ในช่วงงาน
├── Focus Enforce       → บังคับ DND ช่วง Deep Work
├── Camera Disable      → ปิดกล้องใน zone ความลับ
├── Data Wipe           → ล้างข้อมูลเมื่อพนักงานลาออก
├── A2A Team Sync       → ประสานงานระหว่างเครื่องทีม
└── Burnout Prevention  → บังคับพักหลังจากทำงาน X ชั่วโมง
```

**ตัวอย่าง B2B Use Case**:
- บริษัทก่อสร้าง: หัวหน้าทีมสั่ง "lock all team devices" เมื่อเข้า zone ความลับ
- โรงพยาบาล: ปิด camera อัตโนมัติเมื่อเข้า zone ผู้ป่วย
- โรงเรียน: จำกัด app ใช้ได้แค่ calculator + notes ช่วงสอบ

---

## สถาปัตยกรรมที่เสนอ (Proposed Architecture)

```
┌─────────────────────────────────────────────────────────────────┐
│                        USER LAYER                                │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │ Chat Screen │  │ Settings    │  │ Audit Log Screen        │  │
│  │ (Passive)   │  │ (Permissions│  │ (What AI did today)     │  │
│  └──────┬──────┘  └─────────────┘  └─────────────────────────┘  │
└─────────┼───────────────────────────────────────────────────────┘
          │
┌─────────▼───────────────────────────────────────────────────────┐
│                   PROACTIVE LAYER (NEW)                          │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ ProactiveCommandEngine                                   │   │
│  │  • subscribe to TriggerStream (GPS, Time, Calendar)      │   │
│  │  • match trigger → command mapping (SQLite)              │   │
│  │  • check PermissionGuard before execute                  │   │
│  │  • log to CommandAudit                                   │   │
│  └──────────────────────────────────────────────────────────┘   │
│  ┌─────────────────────┐  ┌─────────────────────────────────┐   │
│  │ Trigger-to-Command  │  │ Context-Aware Decision          │   │
│  │ Mapping Table       │  │ (Should I run this now?)        │   │
│  │  home → wifi_on     │  │  • user_busy? → skip            │   │
│  │  work → dnd_on      │  │  • battery_low? → delay         │   │
│  │  meeting → silent   │  │  • already_done_today? → skip   │   │
│  └─────────────────────┘  └─────────────────────────────────┘   │
└─────────┬───────────────────────────────────────────────────────┘
          │
┌─────────▼───────────────────────────────────────────────────────┐
│                   EXECUTION LAYER (EXISTING)                     │
│  ┌─────────────────────┐  ┌─────────────────────────────────┐   │
│  │ DeviceCommandService│  │ DeviceCommandHandler (Android)  │   │
│  │  (MethodChannel)    │  │  • Intent.startActivity         │   │
│  └─────────────────────┘  │  • CameraManager.torch          │   │
│                           │  • BatteryManager               │   │
│                           └─────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## ไฟล์ที่ต้องสร้างเพิ่ม

| ไฟล์ | บทบาท |
|------|-------|
| `lib/services/device_command_proactive.dart` | Proactive Command Engine |
| `lib/services/device_command_audit.dart` | Audit Log (SQLite encrypted) |
| `lib/services/device_command_gate.dart` | Permission Guard & User Approval |
| `lib/services/device_command_mdm.dart` | Enterprise/B2B Commands |
| `lib/models/command_mapping.dart` | Trigger → Command data model |
| `lib/screens/command_audit_screen.dart` | UI แสดงประวัติคำสั่ง |

---

## ขั้นตอนการพัฒนา (Priority)

### Phase 1: Foundation (ทำตอนนี้)
1. ✅ `DeviceCommandService` — execute commands (เสร็จแล้ว)
2. ✅ `DeviceCommandIntentDetector` — passive intent detection (เสร็จแล้ว)
3. 🔄 `CommandAuditLog` — บันทึกทุกคำสั่งที่ AI สั่ง

### Phase 2: Proactive (สัปดาห์หน้า)
4. `ProactiveCommandEngine` — subscribe กับ `MVPTriggerService`
5. `TriggerCommandMapping` — ตั้งค่า trigger → command
6. `ContextAwareFilter` — ตัดสินใจว่าควรรันหรือไม่

### Phase 3: Security & B2B (อนาคต)
7. `PermissionGuard` — tier-based approval
8. `EnterpriseDeviceCommands` — MDM features
9. `A2ACommandRelay` — สั่งงานข้ามเครื่องในทีม

---

## สรุป: จากบทความ → โค้ด

| ปัญหาในเอกสาร | สิ่งที่ต้องเพิ่มใน Device Command |
|--------------|----------------------------------|
| Privacy Leaks | Audit Log + Permission Guard + Zero Cloud |
| Prompt Burden | Proactive Engine (Trigger → Auto Execute) |
| Data Sovereignty | B2B/MDM Commands + A2A Relay |
| Deep Tech (NPU) | On-device decision (ไม่ต้องถาม LLM ทุกครั้ง) |
| Burnout Prevention | Focus Enforce + Break Reminder Commands |
| National Impact | Haku OS Integration (System-level commands) |
