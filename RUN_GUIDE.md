# 🚀 วิธีรัน Haku บน Android Studio (Windows)

## ⚠️ แก้ Error ก่อน

### Error: "Cannot resolve symbol 'Properties'"
เกิดจากไฟล์ `local.properties` ไม่มีหรือผิด path

**วิธีแก้:**

1. **หา Android SDK Path** ของคุณ:
   - เปิด Android Studio
   - ไปที่: File → Settings → Appearance & Behavior → System Settings → Android SDK
   - ดู path ที่เขียนไว้ (เช่น `C:\Users\haiki\AppData\Local\Android\Sdk`)

2. **หา Flutter SDK Path**:
   - เปิด Terminal (CMD/PowerShell)
   - พิมพ์: `where flutter`
   - จะได้เช่น `C:\flutter\bin\flutter.exe` → เอา `C:\flutter`

3. **แก้ไขไฟล์ `android/local.properties`**:

```properties
sdk.dir=C:\\Users\\haiki\\AppData\\Local\\Android\\Sdk
flutter.sdk=C:\\flutter
flutter.buildMode=debug
flutter.versionName=0.1.0
flutter.versionCode=1
```

**เปลี่ยน `haiki` เป็นชื่อ user ของคุณ**

---

## 🎯 ขั้นตอนการรัน

### Step 1: เปิด Terminal ใน Android Studio
```bash
# ไปที่โฟลเดอร์ haku
cd F:\Haku Project\haku

# ดาวน์โหลด dependencies
flutter pub get
```

### Step 2: ตรวจสอบว่า Flutter พร้อม
```bash
flutter doctor
```

ต้องขึ้น ✅ แบบนี้:
```
[✓] Flutter (Channel stable, 3.x.x)
[✓] Android toolchain - develop for Android devices
[✓] Android Studio (version 202x.x)
```

ถ้ามี ❌ ติดตั้งตามที่แนะนำ

### Step 3: สร้าง Emulator (ถ้ายังไม่มี)
1. Android Studio → Device Manager
2. Create Device
3. เลือก: Pixel 7 → API 34 (Android 14) → Download
4. Finish

### Step 4: รัน!
```bash
# วิธีที่ 1: รันผ่าน Terminal
flutter run

# วิธีที่ 2: รันผ่าน Android Studio
# กดปุ่ม ▶️ (Run) ที่แถบด้านบน
```

---

## 🛠️ ถ้ายังมี Error

### Error: `flutter` command not found
**แก้:** เพิ่ม Flutter เข้า Environment Variable
1. Windows Search: "Environment Variables"
2. System Properties → Environment Variables
3. Path → Edit → New
4. เพิ่ม: `C:\flutter\bin`
5. Restart Android Studio

### Error: Gradle sync failed
```bash
cd android
.\gradlew clean
.\gradlew build
cd ..
flutter clean
flutter pub get
flutter run
```

### Error: minSdkVersion
ถ้าบอกว่า minSdk ต่ำกว่า 21:
ไปที่ `android/app/build.gradle` แก้:
```gradle
defaultConfig {
    minSdkVersion 21  // หรือสูงกว่า
    targetSdkVersion 34
}
```

---

## 📱 ถ้าอยากรันบนมือถือจริง

1. **เปิด Developer Options บนมือถือ**:
   - Settings → About Phone → แตะ Build Number 7 ครั้ง

2. **เปิด USB Debugging**:
   - Developer Options → USB Debugging → ON

3. **เสียบสาย USB** เข้าคอม

4. **อนุญาต** บนมือถือเมื่อถาม

5. **รัน**:
   ```bash
   flutter devices  # ดูว่าเจอมือถือไหม
   flutter run -d <device_id>
   ```

---

## ✅ Checklist ก่อนรัน

- [ ] `local.properties` มี SDK path ถูกต้อง
- [ ] `flutter doctor` ขึ้น ✅ ทุกอัน
- [ ] มี Emulator หรือมือถือเสียบอยู่
- [ ] `flutter pub get` สำเร็จ (ไม่มี error)

---

**พร้อมแล้วกด ▶️ ได้เลย!** 🎉
