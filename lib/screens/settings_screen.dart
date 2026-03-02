import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'automation_screen.dart';
import '../services/biometric_service.dart';
import '../services/cloud_llm_provider.dart';
import '../services/database_helper.dart';
import '../services/export_service.dart';
import '../services/google_auth_service.dart';
import '../services/llm_provider_manager.dart';
import '../services/llm_service.dart';
import '../utils/constants.dart';
import '../widgets/profile_editor_widget.dart';

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
  bool _isTestingConnection = false;
  bool? _connectionTestResult;

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
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPath = prefs.getString(StorageKeys.customLlmModelPath);
    
    // ตรวจสอบสถานะไฟล์ถ้ามี custom path
    Map<String, dynamic>? validation;
    if (savedPath != null && savedPath.isNotEmpty) {
      validation = await LLMService().validateCustomModel();
    }
    
    // Load LLM Provider settings
    _selectedProvider = _providerManager.activeType;
    _apiEndpointController.text = prefs.getString('llm_api_endpoint') ?? '';
    _apiKeyController.text = prefs.getString('llm_api_key') ?? '';
    final modeIndex = prefs.getInt('llm_connection_mode') ?? 1;
    _connectionMode = ConnectionMode.values[modeIndex.clamp(0, ConnectionMode.values.length - 1)];

    // Load Google Calendar settings
    await _googleAuth.initialize();
    _autoSyncEnabled = prefs.getBool('google_auto_sync') ?? true;
    _isMockMode = GoogleAuthService.isMockMode;
    
    if (_googleAuth.isSignedIn) {
      await _loadCalendarEvents();
    }
    
    setState(() {
      _customLlmPath = savedPath;
      _modelValidation = validation;
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

  Future<void> _validateModelFile() async {
    final validation = await LLMService().validateCustomModel();
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

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('ตั้งค่า'),
      ),
      body: ListView(
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
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  canUseBiometric
                      ? 'เปิดแอพต้องยืนยันตัวตนก่อน'
                      : 'อุปกรณ์นี้ไม่รองรับ Biometric',
                  style: TextStyle(
                    color: canUseBiometric
                        ? Colors.white.withAlpha(150)
                        : Colors.red.withAlpha(150),
                  ),
                ),
                value: _biometricEnabled && canUseBiometric,
                onChanged: canUseBiometric
                    ? (value) => _toggleBiometric(value)
                    : null,
                activeThumbColor: const Color(0xFF9B7CB6),
              );
            },
          ),
          
          SwitchListTile(
            title: const Text(
              'ล็อกอัตโนมัติ',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              'ล็อกหลังไม่ใช้งาน $_autoLockMinutes นาที',
              style: TextStyle(color: Colors.white.withAlpha(150)),
            ),
            value: _autoLockEnabled,
            onChanged: (value) {
              setState(() => _autoLockEnabled = value);
            },
            activeThumbColor: const Color(0xFF9B7CB6),
          ),
          
          if (_autoLockEnabled)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'เวลาล็อกอัตโนมัติ',
                    style: TextStyle(
                      color: Colors.white.withAlpha(150),
                      fontSize: 12,
                    ),
                  ),
                  Slider(
                    value: _autoLockMinutes.toDouble(),
                    min: 1,
                    max: 10,
                    divisions: 9,
                    label: '$_autoLockMinutes นาที',
                    activeColor: const Color(0xFF9B7CB6),
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
            leading: const Icon(Icons.folder_open, color: Color(0xFF9B7CB6)),
            title: const Text(
              'ตำแหน่งไฟล์โมเดล LLM',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _customLlmPath ?? 'ยังไม่ได้ระบุ (ใช้ค่าเริ่มต้น)',
                  style: TextStyle(
                    color: _modelValidation?['valid'] == true
                        ? Colors.greenAccent.withAlpha(180)
                        : (_customLlmPath != null ? Colors.orangeAccent.withAlpha(180) : Colors.white.withAlpha(150)),
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
                          style: const TextStyle(fontSize: 11, color: Colors.white70),
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
                    icon: const Icon(Icons.refresh, color: Colors.white54, size: 20),
                    onPressed: _validateModelFile,
                    tooltip: 'ตรวจสอบไฟล์',
                  ),
                const Icon(Icons.chevron_right, color: Colors.white54),
              ],
            ),
            onTap: () => _showLlmPathOptions(),
          ),

          const Divider(),

          // 🌐 ส่วน LLM Provider
          _buildSectionHeader('🌐 LLM Provider'),
          _buildProviderSelection(),

          const Divider(),

          // 📅 ส่วน Google Calendar
          _buildSectionHeader('📅 Google Calendar'),
          
          // Mock Mode Toggle
          SwitchListTile(
            title: const Text(
              'Demo Mode',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              _isMockMode 
                  ? 'ใช้ข้อมูลจำลอง (ไม่ต้อง Login)'
                  : 'ใช้งานจริง (ต้องตั้งค่า Google Cloud)',
              style: TextStyle(color: Colors.white.withAlpha(150)),
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
            activeThumbColor: const Color(0xFF9B7CB6),
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
                style: TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                _isMockMode 
                    ? 'ทดลองใช้งานด้วย Demo Account'
                    : 'Sync กับ Google Calendar',
                style: TextStyle(color: Colors.white.withAlpha(150)),
              ),
              trailing: _isGoogleLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF9B7CB6)),
                    )
                  : const Icon(Icons.login, color: Color(0xFF9B7CB6)),
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
                        color: const Color(0xFF9B7CB6),
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
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                '${_googleAuth.userEmail ?? ''} ${_isMockMode ? "(Demo)" : ""}',
                style: TextStyle(color: Colors.white.withAlpha(150)),
              ),
              trailing: TextButton(
                onPressed: _isGoogleLoading ? null : _handleGoogleSignOut,
                child: _isGoogleLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                      )
                    : const Text('Sign Out'),
              ),
            ),
            
            // Auto-sync toggle
            SwitchListTile(
              title: const Text(
                'Auto-sync Objectives',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                'Sync objectives ไป Calendar อัตโนมัติ',
                style: TextStyle(color: Colors.white.withAlpha(150)),
              ),
              value: _autoSyncEnabled,
              onChanged: (value) async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('google_auto_sync', value);
                setState(() => _autoSyncEnabled = value);
              },
              activeThumbColor: const Color(0xFF9B7CB6),
            ),
            
            // Upcoming events
            if (_isGoogleLoading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF9B7CB6)),
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
                      style: TextStyle(
                        color: Colors.white.withAlpha(180),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _loadCalendarEvents,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('รีเฟรช'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF9B7CB6),
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
                    style: TextStyle(
                      color: Colors.white.withAlpha(100),
                      fontSize: 12,
                    ),
                  ),
                ),
            ] else
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'ไม่มีนัดหมายใน 7 วันนี้',
                  style: TextStyle(
                    color: Colors.white.withAlpha(100),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
          const Divider(),

          // ⚡ ส่วน Automation
          _buildSectionHeader('⚡ Automation'),

          ListTile(
            leading: const Icon(Icons.bolt, color: Color(0xFF9B7CB6)),
            title: const Text(
              'Automation',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              'ตั้งค่า Trigger → Action อัตโนมัติ',
              style: TextStyle(color: Colors.white.withAlpha(150)),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.white54),
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

          // 🪪 ส่วนโปรไฟล์ผู้ใช้
          _buildSectionHeader('🪪 โปรไฟล์ของฉัน'),

          ListTile(
            leading: const Icon(Icons.person_outline, color: Color(0xFF9B7CB6)),
            title: const Text(
              'แก้ไขข้อมูลส่วนตัว',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              'ชื่อ, นิสัย, ความชอบ - AI จะจำและเรียนรู้',
              style: TextStyle(color: Colors.white.withAlpha(150)),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.white54),
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
            leading: const Icon(Icons.download, color: Color(0xFF9B7CB6)),
            title: const Text(
              'ส่งออกข้อมูล',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              'JSON, Markdown, CSV',
              style: TextStyle(color: Colors.white.withAlpha(150)),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.white54),
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
          
          ListTile(
            leading: const Icon(Icons.info_outline, color: Color(0xFF9B7CB6)),
            title: const Text(
              'Haku - AI Life Logger',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              'เวอร์ชัน 0.1.0 (Phase 1)',
              style: TextStyle(color: Colors.white.withAlpha(150)),
            ),
          ),
          
          ListTile(
            leading: Icon(Icons.privacy_tip_outlined, color: Colors.white.withAlpha(150)),
            title: const Text(
              'นโยบายความเป็นส่วนตัว',
              style: TextStyle(color: Colors.white),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.white54),
            onTap: () => _showPrivacyInfo(),
          ),
          
          // ข้อความด้านล่าง
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                Icon(
                  Icons.shield_outlined,
                  size: 48,
                  color: Colors.white.withAlpha(50),
                ),
                const SizedBox(height: 16),
                Text(
                  '🔒 ข้อมูลของคุณถูกเข้ารหัสด้วย SQLCipher\n'
                  '📱 เก็บบนเครื่องนี้เท่านั้น\n'
                  '🤖 AI ประมวลผลบนเครื่อง (Offline)',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withAlpha(100),
                    height: 1.8,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF9B7CB6),
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
      backgroundColor: const Color(0xFF1E1E2E),
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
                  color: Colors.white,
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
                    color: Colors.white.withAlpha(15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _customLlmPath!,
                    style: TextStyle(
                      color: Colors.greenAccent.withAlpha(180),
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
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF9B7CB6)),
                  )
                : const Icon(Icons.file_open, color: Color(0xFF9B7CB6)),
              title: const Text('เลือกไฟล์ .task', style: TextStyle(color: Colors.white)),
              subtitle: Text(
                _isPickingModel ? 'กำลังเปิดตัวเลือกไฟล์...' : 'เลือกไฟล์โมเดลจากเครื่อง',
                style: TextStyle(color: Colors.white.withAlpha(150)),
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
        dialogTitle: 'เลือกไฟล์โมเดล (.task)',
      );

      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;

        if (!filePath.endsWith('.task')) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('กรุณาเลือกไฟล์ .task เท่านั้น')),
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

        await LLMService().setCustomModelPath(filePath);
        
        // ตรวจสอบไฟล์ทันทีหลังเลือก
        final validation = await LLMService().validateCustomModel();
        
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
    await LLMService().setCustomModelPath(null);
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
      backgroundColor: const Color(0xFF1E1E2E),
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
                  color: Colors.white,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.code, color: Color(0xFF9B7CB6)),
              title: const Text('JSON', style: TextStyle(color: Colors.white)),
              subtitle: Text('สำหรับโปรแกรมอื่น', style: TextStyle(color: Colors.white.withAlpha(150))),
              onTap: () async {
                Navigator.pop(context);
                final path = await ExportService.exportToJson();
                await ExportService.shareFile(path);
              },
            ),
            ListTile(
              leading: const Icon(Icons.description, color: Color(0xFF9B7CB6)),
              title: const Text('Markdown', style: TextStyle(color: Colors.white)),
              subtitle: Text('อ่านง่าย แชร์ได้', style: TextStyle(color: Colors.white.withAlpha(150))),
              onTap: () async {
                Navigator.pop(context);
                final path = await ExportService.exportToMarkdown();
                await ExportService.shareFile(path);
              },
            ),
            ListTile(
              leading: const Icon(Icons.table_chart, color: Color(0xFF9B7CB6)),
              title: const Text('CSV', style: TextStyle(color: Colors.white)),
              subtitle: Text('สำหรับ Excel/Sheets', style: TextStyle(color: Colors.white.withAlpha(150))),
              onTap: () async {
                Navigator.pop(context);
                final path = await ExportService.exportToCsv();
                await ExportService.shareFile(path);
              },
            ),
            ListTile(
              leading: const Icon(Icons.backup, color: Color(0xFF9B7CB6)),
              title: const Text('Backup ไฟล์ดิบ', style: TextStyle(color: Colors.white)),
              subtitle: Text('ไฟล์ .db (เข้ารหัสแล้ว)', style: TextStyle(color: Colors.white.withAlpha(150))),
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
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text(
          'ลบข้อมูลทั้งหมด?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'การกระทำนี้ไม่สามารถย้อนกลับได้\n'
          'ข้อมูลทั้งหมดจะถูกลบถาวร',
          style: TextStyle(color: Colors.white70),
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
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text(
          'นโยบายความเป็นส่วนตัว',
          style: TextStyle(color: Colors.white),
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
            style: TextStyle(color: Colors.white70, height: 1.6),
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
              color: Colors.white.withAlpha(10),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withAlpha(30)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<ProviderType>(
                value: _selectedProvider,
                isExpanded: true,
                dropdownColor: const Color(0xFF1E1E2E),
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
                            Text(p.name, style: const TextStyle(color: Colors.white, fontSize: 14)),
                            Text(p.description, style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 11)),
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
                style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 12),
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
                Text('Mode:', style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 13)),
                const SizedBox(width: 12),
                ChoiceChip(
                  label: const Text('Direct API'),
                  selected: _connectionMode == ConnectionMode.direct,
                  onSelected: (_) => setState(() => _connectionMode = ConnectionMode.direct),
                  selectedColor: const Color(0xFF9B7CB6),
                  labelStyle: TextStyle(
                    color: _connectionMode == ConnectionMode.direct ? Colors.white : Colors.white70,
                    fontSize: 12,
                  ),
                  backgroundColor: Colors.white.withAlpha(15),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Tunnel'),
                  selected: _connectionMode == ConnectionMode.tunnel,
                  onSelected: (_) => setState(() => _connectionMode = ConnectionMode.tunnel),
                  selectedColor: const Color(0xFF9B7CB6),
                  labelStyle: TextStyle(
                    color: _connectionMode == ConnectionMode.tunnel ? Colors.white : Colors.white70,
                    fontSize: 12,
                  ),
                  backgroundColor: Colors.white.withAlpha(15),
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
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'API Endpoint (Tunnel URL)',
                  labelStyle: TextStyle(color: Colors.white.withAlpha(100)),
                  hintText: 'https://your-tunnel.example.com',
                  hintStyle: TextStyle(color: Colors.white.withAlpha(50)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.white.withAlpha(30)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF9B7CB6)),
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
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                labelText: 'API Key',
                labelStyle: TextStyle(color: Colors.white.withAlpha(100)),
                hintText: 'sk-... / AIza...',
                hintStyle: TextStyle(color: Colors.white.withAlpha(50)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.white.withAlpha(30)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF9B7CB6)),
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
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF9B7CB6)),
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
                              : const Color(0xFF9B7CB6),
                      side: BorderSide(
                        color: _connectionTestResult == true
                            ? Colors.green
                            : _connectionTestResult == false
                                ? Colors.red
                                : const Color(0xFF9B7CB6),
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
                    backgroundColor: const Color(0xFF9B7CB6),
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
          color: Colors.white.withAlpha(10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.white.withAlpha(20),
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
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '🕐 ${event.displayTime}${event.location != null ? ' • 📍 ${event.location}' : ''}',
                    style: TextStyle(
                      color: Colors.white.withAlpha(150),
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
}
