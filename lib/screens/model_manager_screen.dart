import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import '../services/llm_service.dart';

/// 🤖 Model Manager - จัดการโมเดล LLM
class ModelManagerScreen extends ConsumerStatefulWidget {
  const ModelManagerScreen({super.key});

  @override
  ConsumerState<ModelManagerScreen> createState() => _ModelManagerScreenState();
}

class _ModelManagerScreenState extends ConsumerState<ModelManagerScreen> {
  bool _isImporting = false;
  String? _importStatus;
  
  @override
  Widget build(BuildContext context) {
    final llmService = LLMService();
    
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

  Widget _buildCurrentModelCard(LLMService llmService) => Card(
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
            FutureBuilder<List<String>>(
              future: llmService.listAvailableModels(),
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Text(
                    '❌ ยังไม่มีโมเดล\nกรุณา import โมเดล .litertlm, .task หรือ .tflite',
                    style: TextStyle(color: Colors.orange),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: snapshot.data!.map((model) => ListTile(
                    leading: const Icon(Icons.model_training),
                    title: Text(model),
                    trailing: model == llmService.currentModelName
                        ? const Chip(label: Text('กำลังใช้งาน'), backgroundColor: Colors.green)
                        : null,
                  )).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );

  Widget _buildImportButton() => SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isImporting ? null : _pickAndImportModel,
        icon: _isImporting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.file_upload),
        label: Text(_isImporting ? 'กำลังนำเข้า...' : '📁 เลือกไฟล์โมเดล (.litertlm, .task, .tflite)'),
      ),
    );

  Widget _buildRecommendedModels() => Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'โมเดลที่แนะนำ',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildModelItem(
              'Gemma 3 270M IT',
              '~180 MB',
              'เร็วที่สุด ใช้งานง่าย',
            ),
            _buildModelItem(
              'Gemma 3 4B IT',
              '~2.8 GB',
              'คุณภาพสูง ตอบโต้ดี',
            ),
            const SizedBox(height: 8),
            const Text(
              '💡 ดาวน์โหลดจาก: Google AI / Kaggle',
              style: TextStyle(fontSize: 12, color: Colors.grey),
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

  Future<void> _pickAndImportModel() async {
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

      setState(() {
        _importStatus = 'กำลัง copy $fileName...';
      });

      final llmService = LLMService();
      final success = await llmService.importModel(filePath);

      if (success) {
        setState(() {
          _importStatus = '✅ นำเข้าสำเร็จ! กรุณารีสตาร์ทแอพ';
        });
      } else {
        setState(() {
          _importStatus = '❌ นำเข้าล้มเหลว';
        });
      }
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
