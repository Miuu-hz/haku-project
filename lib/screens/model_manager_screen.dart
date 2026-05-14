import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import '../services/llm_service.dart';
import '../utils/haku_design_tokens.dart';

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

    return HakuAuroraBackground(
      children: [
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: _buildAppBar(),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCurrentModelCard(llmService),
                const SizedBox(height: 24),
                _buildImportButton(),
                const SizedBox(height: 16),
                _buildRecommendedModels(),
                if (_importStatus != null) ...[
                  const SizedBox(height: 16),
                  _buildStatusText(),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: AppBar(
            backgroundColor: kGlassFill,
            elevation: 0,
            shadowColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            iconTheme: const IconThemeData(color: kFg1),
            title: const Text(
              '🤖 จัดการโมเดล AI',
              style: TextStyle(color: kFg1, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusText() {
    final isSuccess = _importStatus!.contains('สำเร็จ');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isSuccess ? kVividMint.withAlpha(20) : kVividGold.withAlpha(20),
        borderRadius: BorderRadius.circular(kR3),
        border: Border.all(
          color: isSuccess ? kVividMint.withAlpha(80) : kVividGold.withAlpha(80),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isSuccess ? Icons.check_circle_outline : Icons.info_outline,
            color: isSuccess ? kVividMint : kVividGold,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _importStatus!,
              style: TextStyle(
                color: isSuccess ? kVividMint : kVividGold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentModelCard(LLMService llmService) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(kR4),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: kGlassFill,
            borderRadius: BorderRadius.circular(kR4),
            border: Border.all(color: kGlassStroke),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'โมเดลปัจจุบัน',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: kFg1,
                ),
              ),
              const SizedBox(height: 8),
              FutureBuilder<List<String>>(
                future: llmService.listAvailableModels(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: kVividGold, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'ยังไม่มีโมเดล\nกรุณา import โมเดล .litertlm, .task หรือ .tflite',
                            style: TextStyle(color: kFg2, fontSize: 13, height: 1.5),
                          ),
                        ),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: snapshot.data!.map((model) {
                      final isActive = model == llmService.currentModelName;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.model_training,
                              size: 18,
                              color: isActive ? kCrystal400 : kFg4,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                model,
                                style: TextStyle(
                                  color: isActive ? kFg1 : kFg2,
                                  fontWeight: isActive
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            if (isActive)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: kVividMint.withAlpha(25),
                                  borderRadius: BorderRadius.circular(kRPill),
                                  border: Border.all(
                                      color: kVividMint.withAlpha(80)),
                                ),
                                child: const Text(
                                  'กำลังใช้งาน',
                                  style: TextStyle(
                                    color: kVividMint,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImportButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.icon(
        onPressed: _isImporting ? null : _pickAndImportModel,
        style: FilledButton.styleFrom(
          backgroundColor: kCrystal400,
          foregroundColor: kFgOnCyan,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kR3),
          ),
        ),
        icon: _isImporting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: kFgOnCyan),
              )
            : const Icon(Icons.file_upload),
        label: Text(
          _isImporting
              ? 'กำลังนำเข้า...'
              : '📁 เลือกไฟล์โมเดล (.litertlm, .task, .tflite)',
        ),
      ),
    );
  }

  Widget _buildRecommendedModels() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(kR4),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: kGlassFill,
            borderRadius: BorderRadius.circular(kR4),
            border: Border.all(color: kGlassStroke),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'โมเดลที่แนะนำ',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: kFg1,
                ),
              ),
              const SizedBox(height: 8),
              _buildModelItem('Gemma 3 270M IT', '~180 MB', 'เร็วที่สุด ใช้งานง่าย'),
              _buildModelItem('Gemma 3 4B IT', '~2.8 GB', 'คุณภาพสูง ตอบโต้ดี'),
              const SizedBox(height: 8),
              const Row(
                children: [
                  Icon(Icons.lightbulb_outline, size: 14, color: kFg4),
                  SizedBox(width: 6),
                  Text(
                    'ดาวน์โหลดจาก: Google AI / Kaggle',
                    style: TextStyle(fontSize: 12, color: kFg4),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModelItem(String name, String size, String desc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.memory, size: 16, color: kFg4),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: kFg1)),
                Text('$size · $desc',
                    style: const TextStyle(fontSize: 11, color: kFg3)),
              ],
            ),
          ),
        ],
      ),
    );
  }

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
