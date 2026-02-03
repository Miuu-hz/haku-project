# 🎌 Haku (箱) - AI Personal Life Logger

> **Phase 1 FINAL - Privacy-First Journal with Encryption**
> 
> "ข้อมูลของคุณ อยู่กับคุณ ตลอดไป"

## ✅ Phase 1 Features (เสร็จสมบูรณ์)

### 🔐 Security & Privacy
| Feature | รายละเอียด |
|---------|-----------|
| **SQLCipher** | เข้ารหัสฐานข้อมูลด้วย AES-256 |
| **Biometric Lock** | ลายนิ้วมือ / Face ID / PIN |
| **Auto-lock** | ล็อกอัตโนมัติเมื่อไม่ใช้งาน (ปรับได้ 1-10 นาที) |
| **Secure Storage** | Encryption key เก็บใน Android Keystore / iOS Keychain |

### 📝 Core Features
| Feature | รายละเอียด |
|---------|-----------|
| **Journal** | สร้าง อ่าน แก้ไข ลบ บันทึก |
| **Mood Tracking** | ให้คะแนนอารมณ์ 1-5 พร้อม Emoji |
| **Location** | บันทึกตำแหน่งแบบประหยัดแบต (100m filter) |
| **Auto Tags** | ดึง #hashtag อัตโนมัติ |
| **Export** | JSON, Markdown, CSV, Raw Backup |

### 💬 AI Assistant (Mock Mode)
| Feature | รายละเอียด |
|---------|-----------|
| **Chat UI** | หน้าแชทสวยงามพร้อม bubble |
| **Quick Questions** | 6 คำถามพร้อมใช้ |
| **Widget Integration** | กดจากหน้า Home แล้วถาม AI ได้ |
| **Typing Indicator** | แสดงจุดกระพริบตอน AI "คิด" |

### 📱 Android Widgets
| Size | รายละเอียด |
|------|-----------|
| **4x2** | ปุ่มคำถาม 6 ปุ่ม + ลัดเขียน/แชท |
| **4x3** | เพิ่ม preview ข้อความล่าสุด |

### ⚙️ Settings
- Biometric Lock toggle
- Auto-lock timer (1-10 นาที)
- Export หลายรูปแบบ
- Delete all data
- Privacy Policy

---

## 🛠️ Tech Stack

```
Flutter 3.x
├── 🗄️ sqflite_sqlcipher (SQLite + Encryption)
├── 🔐 local_auth (Biometric)
├── 🔒 flutter_secure_storage
├── 📍 geolocator + geocoding
├── 🎨 google_fonts (Noto Sans Thai)
├── 💬 flutter_riverpod (State Management)
└── 📤 share_plus (Export)
```

---

## 🚀 Getting Started

### 1. Prerequisites
```bash
# Flutter SDK
flutter doctor

# Android SDK (API 21+)
# Android Studio or VS Code with Flutter extension
```

### 2. Install Dependencies
```bash
cd haku
flutter pub get
```

### 3. Run
```bash
# Debug
flutter run

# Release APK
flutter build apk --release

# Android App Bundle
flutter build appbundle --release
```

---

## 📁 Project Structure

```
lib/
├── main.dart                 # Entry + App Lifecycle
├── models/
│   ├── entry.dart           # Journal Entry Model
│   └── chat_message.dart    # Chat Message Model
├── screens/
│   ├── onboarding_screen.dart   # First-time setup
│   ├── lock_screen.dart         # Biometric Lock
│   ├── main_navigation_screen.dart  # Bottom Nav
│   ├── home_screen.dart         # Journal List
│   ├── new_entry_screen.dart    # Create Entry
│   ├── view_entry_screen.dart   # View Detail
│   ├── chat_screen.dart         # AI Chat
│   └── settings_screen.dart     # Settings
├── services/
│   ├── database_helper.dart     # SQLCipher DB
│   ├── encryption_service.dart  # Key Management
│   ├── biometric_service.dart   # Face/Fingerprint
│   ├── location_service.dart    # GPS
│   ├── export_service.dart      # JSON/MD/CSV
│   └── ai_service.dart          # Mock AI
└── widgets/
    └── quick_actions_fab.dart   # Expandable FAB
```

---

## 🔒 Security Details

### Encryption Flow
```
1. สร้าง encryption key (256-bit) ตอน First Launch
2. เก็บ key ใน Secure Storage (Keystore/Keychain)
3. เปิด Database ด้วย SQLCipher + key
4. ข้อมูลทั้งหมดถูกเข้ารหัสอัตโนมัติ
```

### Auto-Lock Behavior
```
- แอพไป background → เริ่มจับเวลา
- เกิน 1 นาที (default) → ล็อกหน้าจอ
- กลับมา foreground → ขอสแกนลายนิ้วมือ
```

---

## 🚢 Phase 2 Preview (Coming Soon)

```
🧠 Local LLM Integration (Phi-4 Mini)
🔍 Vector Database (sqlite-vec)
🎯 Semantic Search (RAG Pipeline)
🎙️ Voice Input (Speech-to-Text)
🖼️ Image Support + Auto Caption
```

---

## 📝 License

MIT License - ดู [LICENSE](LICENSE) สำหรับรายละเอียด

---

<p align="center">
  <strong>Phase 1 Complete 🎉</strong><br>
  <em>Ready for Testing</em>
</p>
