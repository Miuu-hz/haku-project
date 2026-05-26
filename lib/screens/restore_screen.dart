import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/restore_service.dart';

// ── Palette (matches settings_screen.dart) ──────────────────────────────────
const _kBg         = Color(0xFFEBF4FF);
const _kCard       = Color(0xFFF3FAFF);
const _kTextMain   = Color(0xFF050A1E);
const _kTextSub    = Color(0xFF44528A);
const _kTextHint   = Color(0xFF8A93B5);
const _kCrystal    = Color(0xFF3CDFFF);
const _kLavender   = Color(0xFF9B7CB6);
const _kOk         = Color(0xFF1A8A5A);
const _kWarn       = Color(0xFFA0600A);
const _kErr        = Color(0xFFCC3333);

class RestoreScreen extends StatefulWidget {
  const RestoreScreen({super.key});

  @override
  State<RestoreScreen> createState() => _RestoreScreenState();
}

class _RestoreScreenState extends State<RestoreScreen> {
  final _passphraseCtrl = TextEditingController();
  String? _selectedFilePath;
  String? _selectedFileName;
  bool _obscure = true;
  bool _isRestoring = false;
  RestorePhase? _phase;
  double _progress = 0.0;
  RestoreResult? _result;

  @override
  void dispose() {
    _passphraseCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (!mounted) return;
    setState(() {
      _selectedFilePath = file.path;
      _selectedFileName = file.name;
      _result = null;
    });
  }

  Future<void> _startRestore() async {
    if (_selectedFilePath == null) {
      _showSnack('เลือกไฟล์ backup ก่อน');
      return;
    }
    final passphrase = _passphraseCtrl.text.trim();
    if (passphrase.isEmpty) {
      _showSnack('กรอก passphrase ก่อน');
      return;
    }

    setState(() {
      _isRestoring = true;
      _phase = RestorePhase.parsing;
      _progress = 0.0;
      _result = null;
    });

    final result = await RestoreService.restoreFromBundle(
      filePath: _selectedFilePath!,
      passphrase: passphrase,
      onPhase: (phase, progress) {
        if (!mounted) return;
        setState(() {
          _phase = phase;
          _progress = progress;
        });
      },
    );

    if (!mounted) return;
    setState(() {
      _isRestoring = false;
      _result = result;
    });
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _phaseLabel(RestorePhase phase) => switch (phase) {
        RestorePhase.parsing         => 'กำลังถอดรหัส passphrase…',
        RestorePhase.writing         => 'กำลังเขียนฐานข้อมูล…',
        RestorePhase.reopening       => 'กำลังตรวจสอบฐานข้อมูล…',
        RestorePhase.rebuildingIndex => 'กำลัง rebuild vector index…',
        RestorePhase.done            => 'เสร็จแล้ว',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        foregroundColor: _kTextMain,
        title: const Text('นำเข้า Backup'),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Step 1 — pick file
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '1. เลือกไฟล์ backup',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _kTextMain,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _isRestoring ? null : _pickFile,
                      icon: const Icon(Icons.folder_open, color: _kLavender),
                      label: const Text('เลือกไฟล์ .hakubak'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kLavender,
                        side: const BorderSide(color: _kLavender),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    if (_selectedFileName != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.check_circle, size: 14, color: _kOk),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _selectedFileName!,
                              style: const TextStyle(fontSize: 12, color: _kTextSub),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Step 2 — passphrase
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '2. ใส่ passphrase',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _kTextMain,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passphraseCtrl,
                      obscureText: _obscure,
                      enabled: !_isRestoring,
                      style: const TextStyle(color: _kTextMain),
                      decoration: InputDecoration(
                        hintText: 'passphrase ที่ใช้ตอน backup',
                        hintStyle: const TextStyle(color: _kTextHint),
                        filled: true,
                        fillColor: const Color(0xFFE8F0FA),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure ? Icons.visibility_off : Icons.visibility,
                            color: _kTextHint,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Restore button
              FilledButton.icon(
                onPressed: _isRestoring ? null : _startRestore,
                style: FilledButton.styleFrom(
                  backgroundColor: _kLavender,
                  disabledBackgroundColor: _kTextHint,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.restore),
                label: const Text('เริ่มกู้คืนข้อมูล'),
              ),

              // Progress
              if (_isRestoring) ...[
                const SizedBox(height: 24),
                _Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _phase != null ? _phaseLabel(_phase!) : 'กำลังดำเนินการ…',
                        style: const TextStyle(fontSize: 14, color: _kTextSub),
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _progress,
                          backgroundColor: const Color(0xFFDDE6F0),
                          color: _kCrystal,
                          minHeight: 8,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${(_progress * 100).toInt()}%',
                        style: const TextStyle(fontSize: 12, color: _kTextHint),
                        textAlign: TextAlign.end,
                      ),
                    ],
                  ),
                ),
              ],

              // Result
              if (_result != null) ...[
                const SizedBox(height: 16),
                if (_result!.success) ...[
                  _ResultCard(
                    success: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.check_circle, color: _kOk, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'กู้คืนสำเร็จ!',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: _kOk,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'กู้คืน ${_result!.entriesRestored} รายการ',
                          style: const TextStyle(color: _kTextSub),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3CD),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.warning_amber, size: 16, color: _kWarn),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'โมเดล AI จำเป็นต้องดาวน์โหลดใหม่\nไปที่ ตั้งค่า → โมเดล AI',
                                  style: TextStyle(fontSize: 12, color: _kWarn),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('กลับหน้าหลัก'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  _ResultCard(
                    success: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.error, color: _kErr, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'กู้คืนล้มเหลว',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: _kErr,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _result!.error ?? 'เกิดข้อผิดพลาดที่ไม่ทราบสาเหตุ',
                          style: const TextStyle(fontSize: 13, color: _kTextSub),
                        ),
                      ],
                    ),
                  ),
                ],
              ],

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: child,
      );
}

class _ResultCard extends StatelessWidget {
  final bool success;
  final Widget child;
  const _ResultCard({required this.success, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: success ? const Color(0xFFE8F8F0) : const Color(0xFFFFF0F0),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: success ? _kOk : _kErr,
            width: 1.5,
          ),
        ),
        child: child,
      );
}
