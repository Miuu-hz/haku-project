import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/biometric_service.dart';
import '../services/database_helper.dart';
import '../services/export_service.dart';
import '../services/llm_service.dart';
import '../utils/constants.dart';

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

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPath = prefs.getString(StorageKeys.customLlmModelPath);
    
    // ตรวจสอบสถานะไฟล์ถ้ามี custom path
    Map<String, dynamic>? validation;
    if (savedPath != null && savedPath.isNotEmpty) {
      validation = await LLMService().validateCustomModel();
    }
    
    setState(() {
      _customLlmPath = savedPath;
      _modelValidation = validation;
      _isLoading = false;
    });
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
}
