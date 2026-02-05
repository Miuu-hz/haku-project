import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import '../services/mediapipe_llm_service.dart';

/// 🤖 Model Manager - จัดการโมเดล MediaPipe LLM
class ModelManagerScreen extends ConsumerStatefulWidget {
  const ModelManagerScreen({super.key});

  @override
  ConsumerState<ModelManagerScreen> createState() => _ModelManagerScreenState();
}

class _ModelManagerScreenState extends ConsumerState<ModelManagerScreen> {
  bool _isImporting = false;
  String? _importStatus;
  Map<String, dynamic>? _modelInfo;

  @override
  void initState() {
    super.initState();
    _loadModelInfo();
  }

  Future<void> _loadModelInfo() async {
    final info = await MediaPipeLLMService().validateCustomModel();
    setState(() {
      _modelInfo = info;
    });
  }

  @override
  Widget build(BuildContext context) {
    final llmService = MediaPipeLLMService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('🤖 จัดการโมเดล AI'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // โมเดลปัจจุบัน
            _buildCurrentModelCard(llmService),

            const SizedBox(height: 24),

            // ปุ่ม import
            _buildImportButton(),

            const SizedBox(height: 16),

            // โมเดลที่แนะนำ
            _buildRecommendedModels(),

            if (_importStatus != null) ...[
              const SizedBox(height: 16),
              Text(
                _importStatus!,
                style: TextStyle(
                  color: _importStatus!.contains('สำเร็จ') ? Colors.green : Colors.orange,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentModelCard(MediaPipeLLMService llmService) => Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'โมเดลปัจจุบัน',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (_modelInfo == null)
              const CircularProgressIndicator()
            else if (_modelInfo!['valid'] == true) ...[
              ListTile(
                leading: const Icon(Icons.model_training, color: Colors.green),
                title: Text(
                  path.basename(_modelInfo!['path'] as String),
                  style: const TextStyle(fontSize: 14),
                ),
                subtitle: Text(
                  'ขนาด: ${_modelInfo!['size']}\nสถานะ: ${llmService.isInitialized ? "โหลดแล้ว" : "พร้อมใช้งาน"}',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: llmService.isInitialized
                    ? const Chip(label: Text('กำลังใช้งาน'), backgroundColor: Colors.green)
                    : null,
              ),
            ] else
              Text(
                '❌ ${_modelInfo!['message']}\nกรุณาเลือกไฟล์โมเดล .task',
                style: const TextStyle(color: Colors.orange),
              ),
          ],
        ),
      ),
    );

  Widget _buildImportButton() => SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isImporting ? null : _pickAndSetModel,
        icon: _isImporting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.file_upload),
        label: Text(_isImporting ? 'กำลังตั้งค่า...' : '📁 เลือกไฟล์โมเดล (.task)'),
      ),
    );

  Widget _buildRecommendedModels() => Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'โมเดลที่แนะนำ (MediaPipe)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildModelItem(
              'gemma-3-270m-it-int8.task',
              '~290 MB',
              'Gemma 3 - เร็ว ประหยัดแบต',
            ),
            _buildModelItem(
              'gemma-3-1b-it-int8.task',
              '~1 GB',
              'Gemma 3 - สมดุล',
            ),
            _buildModelItem(
              'gemma-3-4b-it-int8.task',
              '~4 GB',
              'Gemma 3 - คุณภาพสูง',
            ),
            const SizedBox(height: 8),
            const Text(
              '💡 ดาวน์โหลดจาก: kaggle.com/models/google/gemma-3',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            const Text(
              '⚠️ ใช้ไฟล์ .task (MediaPipe format) เท่านั้น',
              style: TextStyle(fontSize: 11, color: Colors.orange),
            ),
          ],
        ),
      ),
    );

  Widget _buildModelItem(String name, String size, String desc) => ListTile(
      dense: true,
      title: Text(name, style: const TextStyle(fontSize: 13)),
      subtitle: Text('$size - $desc', style: const TextStyle(fontSize: 11)),
    );

  Future<void> _pickAndSetModel() async {
    setState(() {
      _isImporting = true;
      _importStatus = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );

      if (result == null || result.files.single.path == null) {
        setState(() {
          _importStatus = 'ยกเลิกการเลือกไฟล์';
          _isImporting = false;
        });
        return;
      }

      final filePath = result.files.single.path!;
      final fileName = path.basename(filePath);

      // ตรวจสอบว่าเป็นไฟล์ .task หรือไม่
      if (!fileName.endsWith('.task')) {
        setState(() {
          _importStatus = '❌ กรุณาเลือกไฟล์ .task เท่านั้น';
          _isImporting = false;
        });
        return;
      }

      setState(() {
        _importStatus = 'กำลังตั้งค่า $fileName...';
      });

      // บันทึก path ลง SharedPreferences
      final llmService = MediaPipeLLMService();
      await llmService.setCustomModelPath(filePath);

      // โหลด model info ใหม่
      await _loadModelInfo();

      setState(() {
        _importStatus = '✅ ตั้งค่าสำเร็จ! กรุณารีสตาร์ทแอพเพื่อโหลดโมเดล';
      });

    } catch (e) {
      setState(() {
        _importStatus = '❌ ผิดพลาด: $e';
      });
    } finally {
      setState(() {
        _isImporting = false;
      });
    }
  }
}
