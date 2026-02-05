/// 🎯 Constants - ค่าคงที่ที่ใช้ทั่วแอพ
library;

class AppConstants {
  // 🎌 App Info
  static const String appName = 'Haku';
  static const String appNameJp = '箱';  // อ่านว่า "ฮะ-คุ" = กล่อง
  static const String appTagline = 'AI Personal Life Logger';
  static const String appVersion = '0.1.0';
  
  // 📱 การตั้งค่า Location
  static const double locationDistanceFilter = 100.0;  // เมตร
  static const int locationMinAccuracy = 50;           // เมตร
  static const Duration locationTimeout = Duration(seconds: 10);
  
  // 🎨 สีหลัก
  static const int primaryColor = 0xFF6B4E71;      // ม่วงเข้ม
  static const int accentColor = 0xFF9B7CB6;       // ม่วงอ่อน
  static const int backgroundColor = 0xFF121212;   // ดำ
  static const int surfaceColor = 0xFF1E1E2E;      // ดำอมน้ำเงิน
  
  // 📊 Limits
  static const int maxEntryContentLength = 10000;  // ตัวอักษร
  static const int maxTagsPerEntry = 10;
  static const int maxRecentEntries = 50;          // โหลดครั้งแรก
  
  // 💰 Pricing (สำหรับ Phase 4)
  static const double proLifetimePrice = 24.99;    // USD
  static const double modelPackPrice = 4.99;       // USD
  static const int freeEntryLimit = 50;
}

/// 📝 ข้อความต่าง ๆ ในแอพ
class AppStrings {
  // 🏠 Home
  static const String emptyStateTitle = 'ยังไม่มีบันทึก';
  static const String emptyStateSubtitle = 'กดปุ่ม "เขียน" เพื่อเริ่มบันทึกชีวิตของคุณ';
  static const String searchHint = 'ค้นหาบันทึก...';
  
  // ➕ New Entry
  static const String newEntryTitle = 'บันทึกใหม่';
  static const String contentHint = 'วันนี้เป็นยังไงบ้าง?\n\nเล่าให้ Haku ฟังหน่อย...';
  static const String saveButton = 'บันทึก';
  static const String moodQuestion = 'วันนี้รู้สึกยังไง?';
  
  // 😊 Moods
  static const Map<int, String> moodLabels = {
    1: 'แย่มาก',
    2: 'แย่',
    3: 'เฉยๆ',
    4: 'ดี',
    5: 'ดีมาก',
  };
  
  // 📍 Location
  static const String locationCurrent = 'ตำแหน่งปัจจุบัน';
  static const String locationNone = 'ไม่มีตำแหน่ง';
  static const String locationPermissionDenied = 'ไม่สามารถเข้าถึงตำแหน่งได้';
  
  // 📤 Export
  static const String exportTitle = 'ส่งออกข้อมูล';
  static const String exportJson = 'JSON (สำหรับโปรแกรมอื่น)';
  static const String exportMarkdown = 'Markdown (อ่านง่าย)';
  static const String exportCsv = 'CSV (Excel/Sheets)';
  static const String exportBackup = 'Backup ไฟล์ดิบ';
  
  // ⚙️ Settings
  static const String settingsTitle = 'ตั้งค่า';
  static const String settingsPrivacy = 'ความเป็นส่วนตัว';
  static const String settingsNotifications = 'การแจ้งเตือน';
  static const String settingsExport = 'ส่งออกข้อมูล';
  static const String settingsAbout = 'เกี่ยวกับ';
  
  // ℹ️ About
  static const String aboutPrivacy = 'ข้อมูลของคุณเก็บบนเครื่องนี้เท่านั้น';
  static const String aboutOffline = 'ทำงานได้แม้ไม่มีอินเทอร์เน็ต';
  static const String aboutAiLocal = 'AI ประมวลผลบนเครื่อง ไม่ส่งข้อมูลขึ้น Cloud';
}

/// 🔧 Keys สำหรับ SharedPreferences/SecureStorage
class StorageKeys {
  static const String encryptionKey = 'haku_encryption_key';
  static const String onboardingComplete = 'onboarding_complete';
  static const String lastBackupDate = 'last_backup_date';
  static const String userPreferences = 'user_preferences';
  static const String aiModelDownloaded = 'ai_model_downloaded';
  static const String customLlmModelPath = 'custom_llm_model_path';
  static const String llmUseGpu = 'llm_use_gpu';  // true = GPU, false = CPU-only
}
