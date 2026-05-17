import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'automation_screen.dart';
import '../models/llm_model_config.dart';
import '../services/background_task_service.dart';
import '../utils/haku_design_tokens.dart';
import '../services/biometric_service.dart';
import '../services/cloud_llm_provider.dart';
import '../services/database_helper.dart';
import '../services/export_service.dart';
import '../services/google_auth_service.dart';
import '../services/litert_llm_provider.dart';
import '../services/llm_provider_manager.dart';
import '../services/llm_settings_service.dart';
import '../services/model_manager_service.dart';
import '../utils/constants.dart';
import '../widgets/profile_editor_widget.dart';

// ══════════════════════════════════════════════════════════════
// 🎨 Haku Crystal — Settings palette
// ══════════════════════════════════════════════════════════════

const _kSField      = Color(0xFFF3FAFF);   // aurora field — pearl top
const _kSTextMain   = Color(0xFF050A1E);   // fg-1 dark navy
const _kSTextSub    = Color(0xFF44528A);   // fg-3 slate blue
const _kSTextHint   = Color(0xFF8A93B5);   // fg-4 muted
const _kSCrystal    = Color(0xFF3CDFFF);   // crystal-400 primary action
const _kSLavender   = Color(0xFF9B7CB6);   // lavender-500 secondary/heritage
const _kSOk         = Color(0xFF1A8A5A);   // dark green readable on light bg
const _kSWarn       = Color(0xFFA0600A);   // dark amber readable on light bg
const _kSGlassStroke = Color(0x14505A8C); // rgba(80,90,140,0.08)

/// ⚙️ หน้าตั้งค่า
///
/// รวมการตั้งค่าทั้งหมด:
/// - ความปลอดภัย (Biometric, Auto-lock)
/// - การส่งออกข้อมูล
/// - ข้อมูลแอพ

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _biometricEnabled = false;
  bool _autoLockEnabled = true;
  int _autoLockMinutes = 1;
  bool _isLoading = true;
  bool _isPickingModel = false;
  String? _customLlmPath;
  Map<String, dynamic>? _modelValidation;
  
  // LLM Provider
  final _providerManager = LLMProviderManager();
  ProviderType _selectedProvider = ProviderType.onDevice;
  final _apiEndpointController = TextEditingController();
  final _apiKeyController = TextEditingController();
  ConnectionMode _connectionMode = ConnectionMode.direct;

  // LLM Settings (user overrides)
  LLMModelConfig _modelConfig = LLMModelConfig.unknown;
  bool _hasLlmOverride = false;
  String _accelerator = 'GPU'; // CPU / GPU / NPU
  int _userMaxTokens = 1024;
  double _userTemperature = 0.8;
  int _userTopK = 40;
  double _userTopP = 0.95;

  // Google Places API
  final _googlePlacesKeyController = TextEditingController();
  bool _isTestingConnection = false;
  bool? _connectionTestResult;

  // Model Gallery
  final _hfTokenController = TextEditingController();
  bool _hfTokenVisible = false;
  final Map<String, double> _downloadProgress = {};
  final Set<String> _activeDownloads = {};
  Set<String> _localFilenames = {};

  // Benchmark
  bool _isBenchmarking = false;
  String? _benchmarkResult;

  // Proactive AI toggles
  bool _proactiveMorningEnabled = true;
  bool _proactiveEveningEnabled = true;
  bool _proactiveLocationEnabled = true;
  bool _proactiveChargingEnabled = true;

  // Google Calendar
  final _googleAuth = GoogleAuthService();
  bool _googleSignedIn = false;
  bool _isGoogleLoading = false;
  bool _autoSyncEnabled = true;
  List<CalendarEvent> _upcomingEvents = [];
  bool _isMockMode = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _apiEndpointController.dispose();
    _apiKeyController.dispose();
    _googlePlacesKeyController.dispose();
    _hfTokenController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPath = await ModelManagerService().getActiveModelPath();

    // ตรวจสอบสถานะไฟล์ถ้ามี path
    Map<String, dynamic>? validation;
    if (savedPath != null && savedPath.isNotEmpty) {
      validation = await _validateModelFile(savedPath);
    }
    
    // Load LLM Provider settings
    _selectedProvider = _providerManager.activeType;
    _apiEndpointController.text = prefs.getString('llm_api_endpoint') ?? '';
    _apiKeyController.text = prefs.getString('llm_api_key') ?? '';
    _googlePlacesKeyController.text = prefs.getString('google_places_api_key') ?? '';
    final modeIndex = prefs.getInt('llm_connection_mode') ?? 1;
    _connectionMode = ConnectionMode.values[modeIndex.clamp(0, ConnectionMode.values.length - 1)];

    // Load Google Calendar settings
    await _googleAuth.initialize();
    _autoSyncEnabled = prefs.getBool('google_auto_sync') ?? true;
    _isMockMode = GoogleAuthService.isMockMode;
    
    if (_googleAuth.isSignedIn) {
      await _loadCalendarEvents();
    }

    // Load GPU/CPU preference
    // migrate legacy llm_use_gpu → llm_accelerator
    String accelerator = prefs.getString(StorageKeys.llmAccelerator) ?? '';
    if (accelerator.isEmpty) {
      final legacyGpu = prefs.getBool(StorageKeys.llmUseGpu) ?? true;
      accelerator = legacyGpu ? 'GPU' : 'CPU';
    }

    if (!mounted) return;
    setState(() => _accelerator = accelerator);

    // Load LLM model config + user overrides
    _modelConfig = _providerManager.modelConfig;
    _hasLlmOverride = await LlmSettingsService().hasOverride(_modelConfig.modelId);
    if (_hasLlmOverride) {
      final effective = await LlmSettingsService().loadEffectiveConfig(_modelConfig);
      _userMaxTokens = effective.maxNumTokens;
      _userTemperature = effective.defaultTemperature;
      _userTopK = effective.defaultTopK;
      _userTopP = effective.defaultTopP;
    } else {
      _userMaxTokens = _modelConfig.maxNumTokens;
      _userTemperature = _modelConfig.defaultTemperature;
      _userTopK = _modelConfig.defaultTopK;
      _userTopP = _modelConfig.defaultTopP;
    }
    
    await _scanLocalModels();

    // Load proactive AI settings
    final proactiveMorning = prefs.getBool('proactive_morning_enabled') ?? true;
    final proactiveEvening = prefs.getBool('proactive_evening_enabled') ?? true;
    final proactiveLocation = prefs.getBool('proactive_location_enabled') ?? true;
    final proactiveCharging = prefs.getBool('proactive_charging_enabled') ?? true;

    setState(() {
      _customLlmPath = savedPath;
      _modelValidation = validation;
      _proactiveMorningEnabled = proactiveMorning;
      _proactiveEveningEnabled = proactiveEvening;
      _proactiveLocationEnabled = proactiveLocation;
      _proactiveChargingEnabled = proactiveCharging;
      _googleSignedIn = _googleAuth.isSignedIn;
      _isLoading = false;
    });
  }
  
  Future<void> _loadCalendarEvents() async {
    setState(() => _isGoogleLoading = true);
    try {
      final events = await _googleAuth.getUpcomingEvents(maxResults: 5);
      setState(() => _upcomingEvents = events);
    } catch (e) {
      debugPrint('⚠️ Load calendar events error: $e');
    } finally {
      setState(() => _isGoogleLoading = false);
    }
  }

  Future<Map<String, dynamic>> _validateModelFile(String path) async {
    final file = File(path);
    if (!await file.exists()) return {'valid': false, 'message': 'ไม่พบไฟล์'};
    final stat = await file.stat();
    final mb = stat.size / 1024 / 1024;
    return {'valid': true, 'message': 'ไฟล์พร้อมใช้งาน', 'sizeMB': mb};
  }

  Future<void> _scanLocalModels() async {
    final results = <String>{};
    for (final m in _kRemoteModels) {
      if (await ModelManagerService().hasFile(m.filename)) {
        results.add(m.filename);
      }
    }
    if (mounted) setState(() => _localFilenames = results);
  }

  Future<void> _refreshModelValidation() async {
    final path = await ModelManagerService().getActiveModelPath();
    final validation = path != null
        ? await _validateModelFile(path)
        : {'valid': false, 'message': 'ยังไม่ได้เลือกไฟล์'};
    setState(() => _modelValidation = validation);
    
    if (!mounted) return;
    
    final isValid = validation['valid'] == true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${validation['message']}\n${validation['path'] ?? ''}'),
        backgroundColor: isValid ? Colors.green : Colors.orange,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return HakuAuroraBackground(
      children: [
        Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: kGlassFill,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'ตั้งค่า',
          style: TextStyle(color: _kSTextMain, fontWeight: FontWeight.w600),
        ),
        iconTheme: const IconThemeData(color: _kSTextMain),
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: const SizedBox.expand(),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          // 🔒 ส่วนความปลอดภัย
          _buildSectionHeader('🔐 ความปลอดภัย'),
          
          FutureBuilder<bool>(
            future: BiometricService.canCheckBiometrics(),
            builder: (context, snapshot) {
              final canUseBiometric = snapshot.data ?? false;
              
              return SwitchListTile(
                title: const Text(
                  'ล็อกด้วยลายนิ้วมือ / ใบหน้า',
                  style: TextStyle(color: _kSTextMain),
                ),
                subtitle: Text(
                  canUseBiometric
                      ? 'เปิดแอพต้องยืนยันตัวตนก่อน'
                      : 'อุปกรณ์นี้ไม่รองรับ Biometric',
                  style: TextStyle(
                    color: canUseBiometric
                        ? _kSTextSub
                        : Colors.red.withAlpha(150),
                  ),
                ),
                value: _biometricEnabled && canUseBiometric,
                onChanged: canUseBiometric
                    ? (value) => _toggleBiometric(value)
                    : null,
                activeThumbColor: _kSCrystal,
              );
            },
          ),
          
          SwitchListTile(
            title: const Text(
              'ล็อกอัตโนมัติ',
              style: TextStyle(color: _kSTextMain),
            ),
            subtitle: Text(
              'ล็อกหลังไม่ใช้งาน $_autoLockMinutes นาที',
              style: const TextStyle(color: _kSTextSub),
            ),
            value: _autoLockEnabled,
            onChanged: (value) {
              setState(() => _autoLockEnabled = value);
            },
            activeThumbColor: _kSCrystal,
          ),
          
          if (_autoLockEnabled)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'เวลาล็อกอัตโนมัติ',
                    style: TextStyle(
                      color: _kSTextSub,
                      fontSize: 12,
                    ),
                  ),
                  Slider(
                    value: _autoLockMinutes.toDouble(),
                    min: 1,
                    max: 10,
                    divisions: 9,
                    label: '$_autoLockMinutes นาที',
                    activeColor: _kSCrystal,
                    onChanged: (value) {
                      setState(() => _autoLockMinutes = value.round());
                    },
                  ),
                ],
              ),
            ),
          
          const Divider(),

          // 🤖 ส่วน AI Model
          _buildSectionHeader('🤖 โมเดล AI'),

          ListTile(
            leading: const Icon(Icons.folder_open, color: _kSLavender),
            title: const Text(
              'ตำแหน่งไฟล์โมเดล LLM',
              style: TextStyle(color: _kSTextMain),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _customLlmPath ?? 'ยังไม่ได้ระบุ (ใช้ค่าเริ่มต้น)',
                  style: TextStyle(
                    color: _modelValidation?['valid'] == true
                        ? _kSOk
                        : (_customLlmPath != null ? _kSWarn : _kSTextSub),
                    fontSize: 12,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (_modelValidation != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        _modelValidation!['valid'] == true ? Icons.check_circle : Icons.warning,
                        size: 12,
                        color: _modelValidation!['valid'] == true ? Colors.green : Colors.orange,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _modelValidation!['message'] as String,
                        style: TextStyle(
                          fontSize: 11,
                          color: _modelValidation!['valid'] == true ? Colors.green : Colors.orange,
                        ),
                      ),
                      if (_modelValidation!['size'] != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          '(${'${_modelValidation!['size']}'})',
                          style: const TextStyle(fontSize: 11, color: _kSTextSub),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_customLlmPath != null)
                  IconButton(
                    icon: const Icon(Icons.refresh, color: _kSTextHint, size: 20),
                    onPressed: _refreshModelValidation,
                    tooltip: 'ตรวจสอบไฟล์',
                  ),
                const Icon(Icons.chevron_right, color: _kSTextHint),
              ],
            ),
            onTap: () => _showLlmPathOptions(),
          ),

          const Divider(),

          // 📦 Model Gallery
          _buildSectionHeader('📦 ดาวน์โหลดโมเดล'),
          buildModelGallerySection(),

          const Divider(),

          // ⚡ Benchmark
          _buildSectionHeader('⚡ ทดสอบประสิทธิภาพโมเดล'),
          _buildBenchmarkSection(),

          const Divider(),

          // 🌐 ส่วน LLM Provider
          _buildSectionHeader('🌐 LLM Provider'),
          _buildProviderSelection(),

          const Divider(),

          // 🎛️ ส่วน LLM Settings (เหมือน Google Gallery)
          _buildSectionHeader('🎛️ LLM Settings'),
          _buildLlmSettingsSection(),

          const Divider(),

          // 🔍 ส่วน Web Search
          _buildSectionHeader('🔍 Web Search'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Google Places API Key (สำหรับ "ใกล้ฉัน")',
                  style: TextStyle(color: _kSTextSub, fontSize: 13),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _googlePlacesKeyController,
                  style: const TextStyle(color: _kSTextMain, fontSize: 13),
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: 'AIza... (ไม่ใส่ = ใช้ SearXNG ทั่วไป)',
                    hintStyle: const TextStyle(color: _kSTextHint, fontSize: 12),
                    filled: true,
                    fillColor: const Color(0x0F000000),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _kSGlassStroke),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _kSGlassStroke),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.save, color: _kSLavender, size: 20),
                      tooltip: 'บันทึก',
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('google_places_api_key', _googlePlacesKeyController.text.trim());
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('บันทึก Google Places API Key แล้ว'),
                            backgroundColor: Colors.green,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'รับ key ฟรีได้ที่ console.cloud.google.com → Places API',
                  style: TextStyle(color: _kSTextHint, fontSize: 11),
                ),
              ],
            ),
          ),

          const Divider(),

          // 📅 ส่วน Google Calendar
          _buildSectionHeader('📅 Google Calendar'),
          
          // Mock Mode Toggle
          SwitchListTile(
            title: const Text(
              'Demo Mode',
              style: TextStyle(color: _kSTextMain),
            ),
            subtitle: Text(
              _isMockMode 
                  ? 'ใช้ข้อมูลจำลอง (ไม่ต้อง Login)'
                  : 'ใช้งานจริง (ต้องตั้งค่า Google Cloud)',
              style: const TextStyle(color: _kSTextSub),
            ),
            value: _isMockMode,
            onChanged: (value) async {
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              GoogleAuthService.setMockMode(value);
              if (mounted) {
                setState(() => _isMockMode = value);
              }
              if (value && _googleAuth.isSignedIn) {
                // ถ้าเปิด mock ตอน signed in ให้ reload
                await _googleAuth.signOut();
                if (mounted) {
                  setState(() => _googleSignedIn = false);
                }
              }
              scaffoldMessenger.showSnackBar(
                SnackBar(
                  content: Text(value ? '🎭 Demo Mode เปิดแล้ว' : '🔰 Real Mode'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            activeThumbColor: _kSCrystal,
            secondary: Icon(
              _isMockMode ? Icons.theater_comedy : Icons.cloud_off,
              color: _isMockMode ? Colors.orange : Colors.grey,
            ),
          ),
          
          if (!_googleSignedIn) ...[
            // Not signed in - Show Sign In button
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Center(
                  child: Text(
                    'G',
                    style: TextStyle(
                      color: Color(0xFF4285F4),
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              title: const Text(
                'Sign in with Google',
                style: TextStyle(color: _kSTextMain),
              ),
              subtitle: Text(
                _isMockMode 
                    ? 'ทดลองใช้งานด้วย Demo Account'
                    : 'Sync กับ Google Calendar',
                style: const TextStyle(color: _kSTextSub),
              ),
              trailing: _isGoogleLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: _kSLavender),
                    )
                  : const Icon(Icons.login, color: _kSLavender),
              onTap: _isGoogleLoading ? null : _handleGoogleSignIn,
            ),
          ] else ...[
            // Signed in - Show user info
            ListTile(
              leading: _googleAuth.userPhoto != null
                  ? CircleAvatar(
                      backgroundImage: NetworkImage(_googleAuth.userPhoto!),
                      radius: 20,
                    )
                  : Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _kSLavender,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Center(
                        child: Text(
                          (_googleAuth.userName ?? 'U')[0].toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
              title: Text(
                _googleAuth.userName ?? 'User',
                style: const TextStyle(color: _kSTextMain),
              ),
              subtitle: Text(
                '${_googleAuth.userEmail ?? ''} ${_isMockMode ? "(Demo)" : ""}',
                style: const TextStyle(color: _kSTextSub),
              ),
              trailing: TextButton(
                onPressed: _isGoogleLoading ? null : _handleGoogleSignOut,
                child: _isGoogleLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: _kSTextSub),
                      )
                    : const Text('Sign Out'),
              ),
            ),
            
            // Auto-sync toggle
            SwitchListTile(
              title: const Text(
                'Auto-sync Objectives',
                style: TextStyle(color: _kSTextMain),
              ),
              subtitle: const Text(
                'Sync objectives ไป Calendar อัตโนมัติ',
                style: TextStyle(color: _kSTextSub),
              ),
              value: _autoSyncEnabled,
              onChanged: (value) async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('google_auto_sync', value);
                setState(() => _autoSyncEnabled = value);
              },
              activeThumbColor: _kSCrystal,
            ),
            
            // Upcoming events
            if (_isGoogleLoading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _kSLavender),
                  ),
                ),
              )
            else if (_upcomingEvents.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'นัดหมายที่กำลังจะมาถึง (${_upcomingEvents.length})',
                      style: const TextStyle(
                        color: _kSTextSub,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _loadCalendarEvents,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('รีเฟรช'),
                      style: TextButton.styleFrom(
                        foregroundColor: _kSLavender,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(60, 30),
                      ),
                    ),
                  ],
                ),
              ),
              ..._upcomingEvents.take(3).map((event) => _buildEventTile(event)),
              if (_upcomingEvents.length > 3)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text(
                    '+ ${_upcomingEvents.length - 3} รายการอื่น',
                    style: const TextStyle(
                      color: _kSTextHint,
                      fontSize: 12,
                    ),
                  ),
                ),
            ] else
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'ไม่มีนัดหมายใน 7 วันนี้',
                  style: TextStyle(
                    color: _kSTextHint,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
          const Divider(),

          // ⚡ ส่วน Automation
          _buildSectionHeader('⚡ Automation'),

          ListTile(
            leading: const Icon(Icons.bolt, color: _kSLavender),
            title: const Text(
              'Automation',
              style: TextStyle(color: _kSTextMain),
            ),
            subtitle: const Text(
              'ตั้งค่า Trigger → Action อัตโนมัติ',
              style: TextStyle(color: _kSTextSub),
            ),
            trailing: const Icon(Icons.chevron_right, color: _kSTextHint),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (context) => const AutomationScreen(),
                ),
              );
            },
          ),

          const Divider(),

          // 🔔 ส่วน Proactive AI
          _buildSectionHeader('🔔 Proactive AI'),
          _buildProactiveSection(),

          const Divider(),

          // 🪪 ส่วนโปรไฟล์ผู้ใช้
          _buildSectionHeader('🪪 โปรไฟล์ของฉัน'),

          ListTile(
            leading: const Icon(Icons.person_outline, color: _kSLavender),
            title: const Text(
              'แก้ไขข้อมูลส่วนตัว',
              style: TextStyle(color: _kSTextMain),
            ),
            subtitle: const Text(
              'ชื่อ, นิสัย, ความชอบ - AI จะจำและเรียนรู้',
              style: TextStyle(color: _kSTextSub),
            ),
            trailing: const Icon(Icons.chevron_right, color: _kSTextHint),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (context) => const ProfileEditorWidget(),
                ),
              );
            },
          ),

          const Divider(),

          // 📤 ส่วนข้อมูล
          _buildSectionHeader('📤 ข้อมูลของคุณ'),
          
          ListTile(
            leading: const Icon(Icons.download, color: _kSLavender),
            title: const Text(
              'ส่งออกข้อมูล',
              style: TextStyle(color: _kSTextMain),
            ),
            subtitle: const Text(
              'JSON, Markdown, CSV',
              style: TextStyle(color: _kSTextSub),
            ),
            trailing: const Icon(Icons.chevron_right, color: _kSTextHint),
            onTap: () => _showExportOptions(),
          ),
          
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text(
              'ลบข้อมูลทั้งหมด',
              style: TextStyle(color: Colors.red),
            ),
            subtitle: Text(
              'ลบบันทึกทั้งหมดถาวร',
              style: TextStyle(color: Colors.red.withAlpha(150)),
            ),
            onTap: () => _showDeleteConfirmation(),
          ),
          
          const Divider(),
          
          // ℹ️ เกี่ยวกับ
          _buildSectionHeader('ℹ️ เกี่ยวกับ'),
          
          const ListTile(
            leading: Icon(Icons.info_outline, color: _kSLavender),
            title: Text(
              'Haku - AI Life Logger',
              style: TextStyle(color: _kSTextMain),
            ),
            subtitle: Text(
              'เวอร์ชัน 0.1.0 (Phase 1)',
              style: TextStyle(color: _kSTextSub),
            ),
          ),
          
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined, color: _kSTextSub),
            title: const Text(
              'นโยบายความเป็นส่วนตัว',
              style: TextStyle(color: _kSTextMain),
            ),
            trailing: const Icon(Icons.chevron_right, color: _kSTextHint),
            onTap: () => _showPrivacyInfo(),
          ),
          
          // ข้อความด้านล่าง
          const Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              children: [
                Icon(
                  Icons.shield_outlined,
                  size: 48,
                  color: _kSTextHint,
                ),
                SizedBox(height: 16),
                Text(
                  '🔒 ข้อมูลของคุณถูกเข้ารหัสด้วย SQLCipher\n'
                  '📱 เก็บบนเครื่องนี้เท่านั้น\n'
                  '🤖 AI ประมวลผลบนเครื่อง (Offline)',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: _kSTextHint,
                    height: 1.8,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  ],
  );
  }

  // ─── Proactive AI Handlers ──────────────────────────────────────

  Future<void> _toggleProactiveMorning(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('proactive_morning_enabled', value);
    setState(() => _proactiveMorningEnabled = value);
    await BackgroundTaskService.cancelDailyTriggers();
    await BackgroundTaskService.scheduleDailyTriggers();
  }

  Future<void> _toggleProactiveEvening(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('proactive_evening_enabled', value);
    setState(() => _proactiveEveningEnabled = value);
    await BackgroundTaskService.cancelDailyTriggers();
    await BackgroundTaskService.scheduleDailyTriggers();
  }

  Future<void> _toggleProactiveLocation(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('proactive_location_enabled', value);
    setState(() => _proactiveLocationEnabled = value);
  }

  Future<void> _toggleProactiveCharging(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('proactive_charging_enabled', value);
    setState(() => _proactiveChargingEnabled = value);
  }

  Widget _buildProactiveSection() {
    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.wb_sunny_outlined, color: _kSCrystal),
          title: const Text('แจ้งเตือนตอนเช้า (09:00)',
              style: TextStyle(color: _kSTextMain)),
          subtitle: const Text('Agenda + สภาพอากาศ ทุกเช้า',
              style: TextStyle(color: _kSTextSub, fontSize: 12)),
          value: _proactiveMorningEnabled,
          activeThumbColor: _kSCrystal,
          onChanged: _toggleProactiveMorning,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.nightlight_round, color: _kSLavender),
          title: const Text('สรุปตอนเย็น (20:00)',
              style: TextStyle(color: _kSTextMain)),
          subtitle: const Text('สรุปวันนี้ + เตรียมพรุ่งนี้',
              style: TextStyle(color: _kSTextSub, fontSize: 12)),
          value: _proactiveEveningEnabled,
          activeThumbColor: _kSCrystal,
          onChanged: _toggleProactiveEvening,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.location_on_outlined, color: _kSCrystal),
          title: const Text('Trigger จาก GPS',
              style: TextStyle(color: _kSTextMain)),
          subtitle: const Text('ถามความรู้สึกเมื่อออกจากสถานที่ใหม่',
              style: TextStyle(color: _kSTextSub, fontSize: 12)),
          value: _proactiveLocationEnabled,
          activeThumbColor: _kSCrystal,
          onChanged: _toggleProactiveLocation,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.bolt, color: _kSLavender),
          title: const Text('ประมวลผลเมื่อชาร์จ',
              style: TextStyle(color: _kSTextMain)),
          subtitle: const Text('รวบรวม memory + RAG เมื่อเสียบชาร์จ',
              style: TextStyle(color: _kSTextSub, fontSize: 12)),
          value: _proactiveChargingEnabled,
          activeThumbColor: _kSCrystal,
          onChanged: _toggleProactiveCharging,
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: _kSLavender,
        ),
      ),
    );

  Future<void> _toggleBiometric(bool enable) async {
    if (enable) {
      // ทดสอบสแกนก่อนเปิด
      final didAuthenticate = await BiometricService.authenticate();
      if (didAuthenticate) {
        setState(() => _biometricEnabled = true);
      }
    } else {
      setState(() => _biometricEnabled = false);
    }
  }

  void _showLlmPathOptions() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _kSField,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'ตำแหน่งไฟล์โมเดล LLM',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _kSTextMain,
                ),
              ),
            ),
            if (_customLlmPath != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0x0F000000),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _customLlmPath!,
                    style: const TextStyle(
                      color: _kSOk,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            ListTile(
              leading: _isPickingModel 
                ? const SizedBox(
                    width: 20, 
                    height: 20, 
                    child: CircularProgressIndicator(strokeWidth: 2, color: _kSLavender),
                  )
                : const Icon(Icons.file_open, color: _kSLavender),
              title: const Text('เลือกไฟล์โมเดล', style: TextStyle(color: _kSTextMain)),
              subtitle: Text(
                _isPickingModel ? 'กำลังเปิดตัวเลือกไฟล์...' : 'เลือกไฟล์โมเดลจากเครื่อง',
                style: const TextStyle(color: _kSTextSub),
              ),
              onTap: _isPickingModel 
                ? null 
                : () async {
                    Navigator.pop(context);
                    await _pickLlmModelFile();
                  },
            ),
            if (_customLlmPath != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('ล้างค่า (ใช้ค่าเริ่มต้น)', style: TextStyle(color: Colors.redAccent)),
                subtitle: Text(
                  'กลับไปใช้ตำแหน่งเริ่มต้นของแอพ',
                  style: TextStyle(color: Colors.redAccent.withAlpha(150)),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  await _clearCustomLlmPath();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickLlmModelFile() async {
    // ป้องกันการกดซ้ำขณะกำลังเลือกไฟล์
    if (_isPickingModel) return;
    
    setState(() => _isPickingModel = true);
    
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        dialogTitle: 'เลือกไฟล์โมเดล (.litertlm, .task, .tflite)',
      );

      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;

        if (!filePath.toLowerCase().endsWith('.litertlm') &&
            !filePath.toLowerCase().endsWith('.task') &&
            !filePath.toLowerCase().endsWith('.tflite')) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('กรุณาเลือกไฟล์ .litertlm, .task หรือ .tflite')),
          );
          return;
        }

        // ตรวจสอบว่าไฟล์มีอยู่จริง
        final file = File(filePath);
        if (!await file.exists()) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('❌ ไม่พบไฟล์ที่เลือก')),
          );
          return;
        }

        await ModelManagerService().setActiveModelPath(filePath);
        // ตั้ง custom model path ใน LiteRTLLMProvider ถ้า onDevice active อยู่
        if (LLMProviderManager().activeType == ProviderType.onDevice) {
          final p = LLMProviderManager().provider;
          if (p is LiteRTLLMProvider) await p.setCustomModelPath(filePath);
        }

        // ตรวจสอบไฟล์ทันทีหลังเลือก
        final validation = await _validateModelFile(filePath);
        
        setState(() {
          _customLlmPath = filePath;
          _modelValidation = validation;
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ บันทึกตำแหน่งโมเดลแล้ว\n${validation['valid'] == true ? 'ไฟล์พร้อมใช้งาน' : '⚠️ ${validation['message']}'}'),
            backgroundColor: validation['valid'] == true ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isPickingModel = false);
      }
    }
  }

  Future<void> _clearCustomLlmPath() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(StorageKeys.customLlmModelPath);
    setState(() {
      _customLlmPath = null;
      _modelValidation = null;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ล้างค่าตำแหน่งโมเดลแล้ว ใช้ค่าเริ่มต้น')),
    );
  }

  void _showExportOptions() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _kSField,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'ส่งออกข้อมูล',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _kSTextMain,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.code, color: _kSLavender),
              title: const Text('JSON', style: TextStyle(color: _kSTextMain)),
              subtitle: const Text('สำหรับโปรแกรมอื่น', style: TextStyle(color: _kSTextSub)),
              onTap: () async {
                Navigator.pop(context);
                final path = await ExportService.exportToJson();
                await ExportService.shareFile(path);
              },
            ),
            ListTile(
              leading: const Icon(Icons.description, color: _kSLavender),
              title: const Text('Markdown', style: TextStyle(color: _kSTextMain)),
              subtitle: const Text('อ่านง่าย แชร์ได้', style: TextStyle(color: _kSTextSub)),
              onTap: () async {
                Navigator.pop(context);
                final path = await ExportService.exportToMarkdown();
                await ExportService.shareFile(path);
              },
            ),
            ListTile(
              leading: const Icon(Icons.table_chart, color: _kSLavender),
              title: const Text('CSV', style: TextStyle(color: _kSTextMain)),
              subtitle: const Text('สำหรับ Excel/Sheets', style: TextStyle(color: _kSTextSub)),
              onTap: () async {
                Navigator.pop(context);
                final path = await ExportService.exportToCsv();
                await ExportService.shareFile(path);
              },
            ),
            ListTile(
              leading: const Icon(Icons.backup, color: _kSLavender),
              title: const Text('Backup ไฟล์ดิบ', style: TextStyle(color: _kSTextMain)),
              subtitle: const Text('ไฟล์ .db (เข้ารหัสแล้ว)', style: TextStyle(color: _kSTextSub)),
              onTap: () async {
                Navigator.pop(context);
                final path = await ExportService.createRawBackup();
                await ExportService.shareFile(path);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _kSField,
        title: const Text(
          'ลบข้อมูลทั้งหมด?',
          style: TextStyle(color: _kSTextMain),
        ),
        content: const Text(
          'การกระทำนี้ไม่สามารถย้อนกลับได้\n'
          'ข้อมูลทั้งหมดจะถูกลบถาวร',
          style: TextStyle(color: _kSTextSub),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () async {
              await DatabaseHelper.instance.deleteDatabaseFile();
              if (!context.mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('ลบข้อมูลทั้งหมดแล้ว')),
              );
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('ลบถาวร'),
          ),
        ],
      ),
    );
  }

  void _showPrivacyInfo() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _kSField,
        title: const Text(
          'นโยบายความเป็นส่วนตัว',
          style: TextStyle(color: _kSTextMain),
        ),
        content: const SingleChildScrollView(
          child: Text(
            'Haku (箱) - AI Personal Life Logger\n\n'
            '1. ข้อมูลทั้งหมดถูกเก็บบนเครื่องของคุณเท่านั้น\n'
            '2. ใช้ SQLCipher เข้ารหัสฐานข้อมูล\n'
            '3. AI ประมวลผลบนเครื่อง ไม่ส่งข้อมูลขึ้น Cloud\n'
            '4. ไม่มีการเก็บบัญชีผู้ใช้หรือ analytics\n'
            '5. คุณเป็นเจ้าของข้อมูลแบบสมบูรณ์\n\n'
            'หากมีคำถามเพิ่มเติม สามารถติดต่อเราได้',
            style: TextStyle(color: _kSTextSub, height: 1.6),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('เข้าใจแล้ว'),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 🎛️ LLM Settings Methods
  // ═══════════════════════════════════════════════════════════

  Widget _buildLlmSettingsSection() {
    final config = _modelConfig;
    final isUnknown = config.modelId == 'unknown';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Model info card
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0x0A000000),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _kSGlassStroke),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.memory, color: _kSLavender, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      config.displayName,
                      style: const TextStyle(
                        color: _kSTextMain,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (_hasLlmOverride) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withAlpha(80),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'CUSTOM',
                          style: TextStyle(color: Colors.orangeAccent, fontSize: 10),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Context: ${config.maxNumTokens} tokens • '
                  'System Prompt: ${config.supportsSystemInstruction ? "✅" : "❌"}',
                  style: const TextStyle(color: _kSTextHint, fontSize: 11),
                ),
              ],
            ),
          ),
        ),

        if (isUnknown)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'โหลดโมเดลก่อนจึงจะปรับค่าได้',
              style: TextStyle(color: Colors.orange.withAlpha(180), fontSize: 12),
            ),
          )
        else ...[
          // Accelerator selector — CPU / GPU / NPU
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Inference Backend', style: TextStyle(color: _kSTextMain, fontSize: 14)),
                const SizedBox(height: 4),
                Text(
                  _accelerator == 'GPU' ? 'GPU — เร็วสุด (ต้องการ OpenCL)'
                  : _accelerator == 'NPU' ? 'NPU — ประหยัดแบตที่สุด (Hexagon)'
                  : 'CPU — เสถียร รองรับทุกเครื่อง',
                  style: const TextStyle(color: _kSTextSub, fontSize: 12),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'CPU', label: Text('CPU'), icon: Icon(Icons.developer_board, size: 16)),
                    ButtonSegment(value: 'GPU', label: Text('GPU'), icon: Icon(Icons.memory, size: 16)),
                    ButtonSegment(value: 'NPU', label: Text('NPU'), icon: Icon(Icons.electric_bolt, size: 16)),
                  ],
                  selected: {_accelerator},
                  style: ButtonStyle(
                    iconColor: WidgetStateProperty.resolveWith((s) =>
                        s.contains(WidgetState.selected) ? _kSCrystal : _kSTextSub),
                  ),
                  onSelectionChanged: (v) async {
                    final selected = v.first;
                    setState(() => _accelerator = selected);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString(StorageKeys.llmAccelerator, selected);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('$selected mode — โหลดโมเดลใหม่เพื่อใช้งาน'),
                      duration: const Duration(seconds: 2),
                    ));
                  },
                ),
              ],
            ),
          ),

          // Max Tokens slider
          _buildSliderTile(
            icon: Icons.expand,
            label: 'Max Context Tokens',
            subtitle: 'ขนาด context window ทั้งหมด',
            value: _userMaxTokens.toDouble(),
            min: 512,
            max: config.maxNumTokens.toDouble(),
            divisions: ((config.maxNumTokens - 512) / 512).round(),
            displayValue: _userMaxTokens.toString(),
            onChanged: (v) => setState(() => _userMaxTokens = v.round()),
          ),

          // Temperature slider
          _buildSliderTile(
            icon: Icons.thermostat,
            label: 'Temperature',
            subtitle: 'ความสร้างสรรค์ (ต่ำ = ตรงประเด็น, สูง = สร้างสรรค์)',
            value: _userTemperature,
            min: 0.0,
            max: 2.0,
            divisions: 20,
            displayValue: _userTemperature.toStringAsFixed(2),
            onChanged: (v) => setState(() => _userTemperature = v),
          ),

          // Top-K slider
          _buildSliderTile(
            icon: Icons.filter_list,
            label: 'Top-K',
            subtitle: 'จำนวน token ที่พิจารณาต่อ step',
            value: _userTopK.toDouble(),
            min: 1,
            max: 100,
            divisions: 99,
            displayValue: _userTopK.toString(),
            onChanged: (v) => setState(() => _userTopK = v.round()),
          ),

          // Top-P slider
          _buildSliderTile(
            icon: Icons.pie_chart_outline,
            label: 'Top-P',
            subtitle: 'Nucleus sampling (ความน่าจะอนุมาน)',
            value: _userTopP,
            min: 0.0,
            max: 1.0,
            divisions: 20,
            displayValue: _userTopP.toStringAsFixed(2),
            onChanged: (v) => setState(() => _userTopP = v),
          ),

          // Action buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _resetLlmSettings,
                    icon: const Icon(Icons.restore, size: 16),
                    label: const Text('Reset Default', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kSTextSub,
                      side: const BorderSide(color: _kSGlassStroke),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saveLlmSettings,
                    icon: const Icon(Icons.save, size: 16),
                    label: const Text('Apply', style: TextStyle(fontSize: 12)),
                    style: FilledButton.styleFrom(backgroundColor: _kSCrystal),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSliderTile({
    required IconData icon,
    required String label,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String displayValue,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: _kSLavender),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(color: _kSTextMain, fontSize: 13)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _kSLavender.withAlpha(40),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  displayValue,
                  style: const TextStyle(color: _kSLavender, fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(color: _kSTextHint, fontSize: 11)),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            activeColor: _kSCrystal,
            inactiveColor: _kSGlassStroke,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Future<void> _saveLlmSettings() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    await LlmSettingsService().saveOverride(
      _modelConfig.modelId,
      maxTokens: _userMaxTokens,
      temperature: _userTemperature,
      topK: _userTopK,
      topP: _userTopP,
    );
    setState(() => _hasLlmOverride = true);

    // Reload provider ด้วยค่าใหม่ (ถ้าเป็น on-device)
    if (_providerManager.activeType == ProviderType.onDevice) {
      await _providerManager.provider.dispose();
      await _providerManager.provider.initialize(maxTokens: _userMaxTokens);
    }

    scaffoldMessenger.showSnackBar(
      const SnackBar(content: Text('✅ บันทึกการตั้งค่า LLM แล้ว'), backgroundColor: Colors.green),
    );
  }

  Future<void> _resetLlmSettings() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    await LlmSettingsService().clearOverride(_modelConfig.modelId);
    setState(() {
      _hasLlmOverride = false;
      _userMaxTokens = _modelConfig.maxNumTokens;
      _userTemperature = _modelConfig.defaultTemperature;
      _userTopK = _modelConfig.defaultTopK;
      _userTopP = _modelConfig.defaultTopP;
    });

    // Reload provider ด้วยค่า default
    if (_providerManager.activeType == ProviderType.onDevice) {
      await _providerManager.provider.dispose();
      await _providerManager.provider.initialize();
    }

    scaffoldMessenger.showSnackBar(
      const SnackBar(content: Text('🔄 รีเซ็ตเป็น default แล้ว'), backgroundColor: Colors.green),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 🌐 LLM Provider Methods
  // ═══════════════════════════════════════════════════════════

  Widget _buildProviderSelection() {
    final providers = _providerManager.getAvailableProviders();
    final isCloud = _selectedProvider != ProviderType.onDevice;

    return Column(
      children: [
        // Provider dropdown
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0x0A000000),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _kSGlassStroke),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<ProviderType>(
                value: _selectedProvider,
                isExpanded: true,
                dropdownColor: _kSField,
                items: providers.map((p) => DropdownMenuItem(
                  value: p.type,
                  child: Row(
                    children: [
                      Text(p.icon, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(p.name, style: const TextStyle(color: _kSTextMain, fontSize: 14)),
                            Text(p.description, style: const TextStyle(color: _kSTextHint, fontSize: 11)),
                          ],
                        ),
                      ),
                    ],
                  ),
                )).toList(),
                onChanged: (type) {
                  if (type == null) return;
                  setState(() {
                    _selectedProvider = type;
                    _connectionTestResult = null;
                  });
                },
              ),
            ),
          ),
        ),

        // Active provider indicator
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Icon(
                _providerManager.provider.isInitialized ? Icons.circle : Icons.circle_outlined,
                size: 10,
                color: _providerManager.provider.isInitialized ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 8),
              Text(
                'Active: ${_providerManager.providerName}',
                style: const TextStyle(color: _kSTextSub, fontSize: 12),
              ),
            ],
          ),
        ),

        // Cloud-only fields
        if (isCloud) ...[
          // Connection mode toggle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Text('Mode:', style: TextStyle(color: _kSTextSub, fontSize: 13)),
                const SizedBox(width: 12),
                ChoiceChip(
                  label: const Text('Direct API'),
                  selected: _connectionMode == ConnectionMode.direct,
                  onSelected: (_) => setState(() => _connectionMode = ConnectionMode.direct),
                  selectedColor: _kSCrystal,
                  labelStyle: TextStyle(
                    color: _connectionMode == ConnectionMode.direct ? _kSTextMain : _kSTextSub,
                    fontSize: 12,
                  ),
                  backgroundColor: const Color(0x0F000000),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Tunnel'),
                  selected: _connectionMode == ConnectionMode.tunnel,
                  onSelected: (_) => setState(() => _connectionMode = ConnectionMode.tunnel),
                  selectedColor: _kSCrystal,
                  labelStyle: TextStyle(
                    color: _connectionMode == ConnectionMode.tunnel ? _kSTextMain : _kSTextSub,
                    fontSize: 12,
                  ),
                  backgroundColor: const Color(0x0F000000),
                ),
              ],
            ),
          ),

          // API Endpoint (tunnel mode only)
          if (_connectionMode == ConnectionMode.tunnel)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: _apiEndpointController,
                style: const TextStyle(color: _kSTextMain, fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'API Endpoint (Tunnel URL)',
                  labelStyle: const TextStyle(color: _kSTextHint),
                  hintText: 'https://your-tunnel.example.com',
                  hintStyle: const TextStyle(color: _kSTextHint),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _kSGlassStroke),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _kSLavender),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
            ),

          // API Key
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              controller: _apiKeyController,
              obscureText: true,
              style: const TextStyle(color: _kSTextMain, fontSize: 14),
              decoration: InputDecoration(
                labelText: 'API Key',
                labelStyle: const TextStyle(color: _kSTextHint),
                hintText: 'sk-... / AIza...',
                hintStyle: const TextStyle(color: _kSTextHint),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _kSGlassStroke),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _kSLavender),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
          ),
        ],

        // Action buttons
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Test connection
              if (isCloud)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isTestingConnection ? null : _testProviderConnection,
                    icon: _isTestingConnection
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: _kSLavender),
                          )
                        : Icon(
                            _connectionTestResult == true
                                ? Icons.check_circle
                                : _connectionTestResult == false
                                    ? Icons.error
                                    : Icons.wifi_find,
                            size: 18,
                          ),
                    label: Text(
                      _connectionTestResult == true
                          ? 'Connected'
                          : _connectionTestResult == false
                              ? 'Failed'
                              : 'Test',
                      style: const TextStyle(fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _connectionTestResult == true
                          ? Colors.green
                          : _connectionTestResult == false
                              ? Colors.red
                              : _kSLavender,
                      side: BorderSide(
                        color: _connectionTestResult == true
                            ? Colors.green
                            : _connectionTestResult == false
                                ? Colors.red
                                : _kSLavender,
                      ),
                    ),
                  ),
                ),
              if (isCloud) const SizedBox(width: 8),
              // Apply button
              Expanded(
                child: FilledButton.icon(
                  onPressed: _applyProviderChange,
                  icon: const Icon(Icons.save, size: 18),
                  label: const Text('Apply', style: TextStyle(fontSize: 13)),
                  style: FilledButton.styleFrom(
                    backgroundColor: _kSCrystal,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _testProviderConnection() async {
    setState(() {
      _isTestingConnection = true;
      _connectionTestResult = null;
    });

    try {
      final result = await _providerManager.testConnection(
        _selectedProvider,
        apiEndpoint: _apiEndpointController.text.trim().isNotEmpty
            ? _apiEndpointController.text.trim()
            : null,
        apiKey: _apiKeyController.text.trim().isNotEmpty
            ? _apiKeyController.text.trim()
            : null,
        mode: _connectionMode,
      );

      if (!mounted) return;
      setState(() => _connectionTestResult = result);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result ? 'Connection successful' : 'Connection failed'),
          backgroundColor: result ? Colors.green : Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _connectionTestResult = false);
      // แสดง error message จริงจาก API
      final errorMsg = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg, maxLines: 3, overflow: TextOverflow.ellipsis),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) setState(() => _isTestingConnection = false);
    }
  }

  Future<void> _applyProviderChange() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      await _providerManager.switchProvider(
        _selectedProvider,
        apiEndpoint: _apiEndpointController.text.trim().isNotEmpty
            ? _apiEndpointController.text.trim()
            : null,
        apiKey: _apiKeyController.text.trim().isNotEmpty
            ? _apiKeyController.text.trim()
            : null,
        mode: _connectionMode,
      );

      // โหลดโมเดลทันทีหลัง switch (on-device)
      if (_selectedProvider == ProviderType.onDevice) {
        await _providerManager.provider.initialize();
      }

      // Reload LLM settings for new provider
      _modelConfig = _providerManager.modelConfig;
      _hasLlmOverride = await LlmSettingsService().hasOverride(_modelConfig.modelId);
      if (_hasLlmOverride) {
        final effective = await LlmSettingsService().loadEffectiveConfig(_modelConfig);
        _userMaxTokens = effective.maxNumTokens;
        _userTemperature = effective.defaultTemperature;
        _userTopK = effective.defaultTopK;
        _userTopP = effective.defaultTopP;
      } else {
        _userMaxTokens = _modelConfig.maxNumTokens;
        _userTemperature = _modelConfig.defaultTemperature;
        _userTopK = _modelConfig.defaultTopK;
        _userTopP = _modelConfig.defaultTopP;
      }

      if (!mounted) return;
      setState(() {});

      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Switched to ${_providerManager.providerName}'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Switch failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 📅 Google Calendar Methods
  // ═══════════════════════════════════════════════════════════

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isGoogleLoading = true);
    try {
      final success = await _googleAuth.signIn();
      if (success) {
        await _loadCalendarEvents();
        setState(() => _googleSignedIn = true);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isMockMode 
                ? '🎭 Demo Mode: Signed in as demo@haku.app' 
                : '✅ Signed in as ${_googleAuth.userEmail}'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Sign in failed'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $e')),
      );
    } finally {
      setState(() => _isGoogleLoading = false);
    }
  }

  Future<void> _handleGoogleSignOut() async {
    setState(() => _isGoogleLoading = true);
    try {
      await _googleAuth.signOut();
      setState(() {
        _googleSignedIn = false;
        _upcomingEvents = [];
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Signed out')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $e')),
      );
    } finally {
      setState(() => _isGoogleLoading = false);
    }
  }

  Widget _buildEventTile(CalendarEvent event) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0x0A000000),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _kSGlassStroke,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF4285F4).withAlpha(30),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    event.displayDate.split('/')[0],
                    style: const TextStyle(
                      color: Color(0xFF4285F4),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '/${event.displayDate.split('/')[1]}',
                    style: TextStyle(
                      color: const Color(0xFF4285F4).withAlpha(180),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: const TextStyle(
                      color: _kSTextMain,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '🕐 ${event.displayTime}${event.location != null ? ' • 📍 ${event.location}' : ''}',
                    style: const TextStyle(
                      color: _kSTextSub,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // ⚡ Benchmark
  // ═══════════════════════════════════════════════════════════

  Widget _buildBenchmarkSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'วัดความเร็ว inference ของโมเดลปัจจุบัน\n(รัน 3 ครั้ง, prompt 10 words)',
            style: TextStyle(fontSize: 13, color: _kSTextSub, height: 1.5),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _isBenchmarking ? null : _runBenchmark,
                icon: _isBenchmarking
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.speed_rounded, size: 18),
                label: Text(_isBenchmarking ? 'กำลังทดสอบ...' : 'เริ่มทดสอบ'),
                style: FilledButton.styleFrom(backgroundColor: _kSCrystal),
              ),
              if (_benchmarkResult != null) ...[
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    _benchmarkResult!,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _kSTextMain,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _runBenchmark() async {
    final provider = _providerManager.provider;
    if (!provider.isInitialized) {
      setState(() => _benchmarkResult = 'โหลดโมเดลก่อนแล้วค่อยทดสอบ');
      return;
    }

    setState(() { _isBenchmarking = true; _benchmarkResult = null; });

    const prompt = 'Hello! Please count from one to five briefly.';
    const runs = 3;
    var totalMs = 0;

    try {
      for (var i = 0; i < runs; i++) {
        final sw = Stopwatch()..start();
        await provider.generate(prompt);
        sw.stop();
        totalMs += sw.elapsedMilliseconds;
      }

      final avgMs = totalMs ~/ runs;
      // rough tokens/sec: assume ~20 output tokens per run
      const estimatedOutputTokens = 20;
      final tokensPerSec = (estimatedOutputTokens * 1000 / avgMs).toStringAsFixed(1);

      setState(() => _benchmarkResult = 'เฉลี่ย ${avgMs}ms · ~$tokensPerSec tok/s');
    } catch (e) {
      setState(() => _benchmarkResult = 'Error: $e');
    } finally {
      setState(() => _isBenchmarking = false);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 📦 Model Gallery
  // ═══════════════════════════════════════════════════════════

  Widget buildModelGallerySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // HF Token field
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            controller: _hfTokenController,
            obscureText: !_hfTokenVisible,
            style: const TextStyle(color: _kSTextMain, fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Hugging Face Token (สำหรับโมเดล gated)',
              labelStyle: const TextStyle(color: _kSTextHint, fontSize: 12),
              hintText: 'hf_...',
              hintStyle: const TextStyle(color: _kSTextHint, fontSize: 12),
              filled: true,
              fillColor: const Color(0x0A000000),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _kSGlassStroke),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              suffixIcon: IconButton(
                icon: Icon(_hfTokenVisible ? Icons.visibility_off : Icons.visibility,
                    size: 18, color: _kSTextHint),
                onPressed: () => setState(() => _hfTokenVisible = !_hfTokenVisible),
              ),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'รับ token ฟรีได้ที่ huggingface.co/settings/tokens',
            style: TextStyle(color: _kSTextHint, fontSize: 11),
          ),
        ),
        const SizedBox(height: 12),
        // Model cards
        ..._kRemoteModels.map((m) => _buildModelCard(m)),
      ],
    );
  }

  Widget _buildModelCard(_RemoteModel m) {
    final isDownloading = _activeDownloads.contains(m.filename);
    final isLocal = _localFilenames.contains(m.filename);
    final progress = _downloadProgress[m.filename] ?? 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          color: isLocal ? const Color(0x12000000) : const Color(0x0A000000),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isLocal
                ? _kSLavender.withAlpha(100)
                : _kSGlassStroke,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title row
              Row(
                children: [
                  Expanded(
                    child: Text(
                      m.name,
                      style: const TextStyle(
                        color: _kSTextMain,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: m.badgeColor.withAlpha(50),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: m.badgeColor.withAlpha(120)),
                    ),
                    child: Text(
                      m.badge,
                      style: TextStyle(color: m.badgeColor, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // Specs row
              Text(
                '${m.sizeLabel} • ${m.contextLabel} tokens • ${m.quantLabel}',
                style: const TextStyle(color: _kSTextHint, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                m.description,
                style: const TextStyle(color: _kSTextSub, fontSize: 13),
              ),
              const SizedBox(height: 12),

              // Action row
              if (isDownloading) ...[
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: progress,
                              backgroundColor: _kSGlassStroke,
                              valueColor: AlwaysStoppedAnimation<Color>(m.badgeColor),
                              minHeight: 6,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${(progress * 100).toInt()}%  •  ${(progress * m.sizeGB).toStringAsFixed(1)} / ${m.sizeGB} GB',
                            style: const TextStyle(color: _kSTextHint, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: () {
                        ModelManagerService().cancelDownload(m.filename);
                        setState(() => _activeDownloads.remove(m.filename));
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(60, 32),
                      ),
                      child: const Text('ยกเลิก', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ] else if (isLocal) ...[
                Row(
                  children: [
                    const Icon(Icons.check_circle, color: _kSLavender, size: 16),
                    const SizedBox(width: 6),
                    const Text(
                      'ดาวน์โหลดแล้ว',
                      style: TextStyle(color: _kSTextSub, fontSize: 13),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () => _activateModel(m),
                      style: FilledButton.styleFrom(
                        backgroundColor: _kSCrystal,
                        foregroundColor: _kSTextMain,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        minimumSize: const Size(0, 32),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                      child: const Text('ใช้งาน'),
                    ),
                  ],
                ),
              ] else ...[
                // Download buttons
                if (m.gdriveUrl != null && m.gdriveUrl!.isNotEmpty) ...[
                  // มี Google Drive link → ให้เลือกแหล่งดาวน์โหลด
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // 🌐 Google Drive (ไม่ต้อง login)
                      FilledButton.icon(
                        onPressed: () => _startModelDownload(m, useGDrive: true),
                        icon: const Icon(Icons.cloud_download, size: 16),
                        label: Text('Drive ${m.sizeLabel}', style: const TextStyle(fontSize: 12)),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF34A853),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          minimumSize: const Size(0, 32),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 🤗 HuggingFace (ต้องมี Token)
                      OutlinedButton.icon(
                        onPressed: () => _startModelDownload(m, useGDrive: false),
                        icon: const Icon(Icons.download, size: 16),
                        label: Text('HF ${m.sizeLabel}', style: const TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _kSTextSub,
                          side: const BorderSide(color: _kSGlassStroke),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          minimumSize: const Size(0, 32),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  // มีแค่ HuggingFace
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: () => _startModelDownload(m),
                      icon: const Icon(Icons.download, size: 16),
                      label: Text('ดาวน์โหลด ${m.sizeLabel}', style: const TextStyle(fontSize: 12)),
                      style: FilledButton.styleFrom(
                        backgroundColor: _kSGlassStroke,
                        foregroundColor: _kSTextMain,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        minimumSize: const Size(0, 32),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startModelDownload(_RemoteModel m, {bool useGDrive = false}) async {
    final token = _hfTokenController.text.trim();
    setState(() {
      _activeDownloads.add(m.filename);
      _downloadProgress[m.filename] = 0.0;
    });

    // 🌐 เลือกแหล่งดาวน์โหลด
    String url;
    String? authToken;
    if (useGDrive && m.gdriveUrl != null && m.gdriveUrl!.isNotEmpty) {
      url = m.gdriveUrl!;
      authToken = null; // Google Drive ไม่ต้อง token
      debugPrint('🌐 Downloading from Google Drive: ${m.name}');
    } else {
      url = 'https://huggingface.co/${m.hfRepo}/resolve/main/${m.filename}';
      authToken = token.isNotEmpty ? token : null;
      debugPrint('🌐 Downloading from HuggingFace: ${m.name}');
    }

    final ok = await ModelManagerService().downloadModel(
      url,
      m.filename,
      onProgress: (p) {
        if (mounted) setState(() => _downloadProgress[m.filename] = p);
      },
      hfToken: authToken,
    );

    if (!mounted) return;
    setState(() => _activeDownloads.remove(m.filename));

    if (ok) {
      await _scanLocalModels();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('✅ ดาวน์โหลด ${m.name} สำเร็จ'),
        backgroundColor: Colors.green,
        action: SnackBarAction(
          label: 'ใช้งาน',
          textColor: Colors.white,
          onPressed: () => _activateModel(m),
        ),
      ));
    } else {
      final source = useGDrive ? 'Google Drive' : 'HuggingFace';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('❌ ดาวน์โหลดจาก $source ล้มเหลว — ตรวจสอบลิงก์หรือพื้นที่เก็บข้อมูล'),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ));
    }
  }

  Future<void> _activateModel(_RemoteModel m) async {
    final path = await ModelManagerService().modelPath(m.filename);
    await ModelManagerService().setActiveModelPath(path);
    if (LLMProviderManager().activeType == ProviderType.onDevice) {
      final p = LLMProviderManager().provider;
      if (p is LiteRTLLMProvider) await p.setCustomModelPath(path);
    }
    final validation = await _validateModelFile(path);
    if (!mounted) return;
    setState(() {
      _customLlmPath = path;
      _modelValidation = validation;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('✅ ใช้งาน ${m.name} แล้ว'),
      backgroundColor: Colors.green,
    ));
  }
}

// ═══════════════════════════════════════════════════════════
// 📦 Remote Model Catalog
// ═══════════════════════════════════════════════════════════

class _RemoteModel {
  final String name;
  final String badge;
  final Color badgeColor;
  final double sizeGB;
  final String contextLabel;
  final String quantLabel;
  final String description;
  final String filename;
  final String hfRepo;
  final String? gdriveUrl;   // ⭐ Google Drive direct link (ไม่ต้อง HF Token)

  const _RemoteModel({
    required this.name,
    required this.badge,
    required this.badgeColor,
    required this.sizeGB,
    required this.contextLabel,
    required this.quantLabel,
    required this.description,
    required this.filename,
    required this.hfRepo,
    this.gdriveUrl,
  });

  String get sizeLabel {
    if (sizeGB >= 1.0) return '${sizeGB.toStringAsFixed(1)} GB';
    return '${(sizeGB * 1024).round()} MB';
  }
}

const _kRemoteModels = <_RemoteModel>[
  _RemoteModel(
    name: 'Gemma 3 1B',
    badge: '⚡ เร็วสุด',
    badgeColor: Color(0xFF4FC3F7),
    sizeGB: 0.50,
    contextLabel: '1K',
    quantLabel: 'INT4',
    description: 'เบาที่สุด ใช้แบตน้อย เหมาะกับมือถือทุกรุ่น',
    filename: 'gemma3-1b-it-int4.litertlm',
    hfRepo: 'google/gemma-3-1b-it-litert-lm',
    gdriveUrl: 'https://drive.google.com/file/d/1ArY52BPfJgq40zEbSF7V8VN4N8XehlLP/view?usp=sharing',
  ),
  _RemoteModel(
    name: 'Gemma 4 E2B',
    badge: '⭐ แนะนำ',
    badgeColor: Color(0xFFFFB74D),
    sizeGB: 2.2,
    contextLabel: '4K',
    quantLabel: 'INT4',
    description: 'สมดุลระหว่างความเร็วและคุณภาพ รองรับบทสนทนายาว',
    filename: 'gemma4-e2b-it-int4.litertlm',
    hfRepo: 'google/gemma-4-e2b-it-litert-lm',
    gdriveUrl: 'https://drive.google.com/file/d/1Hu2TNwpfIIHj7l8z51jb8ogglmMJjFTN/view?usp=sharing',
  ),
  _RemoteModel(
    name: 'Gemma 4 E4B',
    badge: '🏆 ดีสุด',
    badgeColor: Color(0xFFCE93D8),
    sizeGB: 4.5,
    contextLabel: '8K',
    quantLabel: 'INT4',
    description: 'คุณภาพสูงสุด เข้าใจภาษาไทยได้ดี เหมาะกับเครื่องแรง',
    filename: 'gemma4-e4b-it-int4.litertlm',
    hfRepo: 'google/gemma-4-e4b-it-litert-lm',
    gdriveUrl: 'https://drive.google.com/file/d/19Mukj47cxxOtDTUhGRQ9hpqfZYZxksDw/view?usp=sharing',
  ),
];
