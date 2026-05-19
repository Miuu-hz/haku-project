import 'package:flutter/material.dart';

import '../services/device_command_gate.dart';
import '../services/device_command_service.dart';

/// 🛡️ Inline Confirmation Card สำหรับแชท
///
/// แสดงเมื่อ AI ตรวจพบ sensitive command (dial_phone, send_sms, ฯลฯ)
/// ผู้ใช้กด "ยืนยัน" หรือ "ยกเลิก" ในแชท bubble ได้เลย
/// แทนการแสดง AlertDialog แบบ modal ที่บังหน้าจอทั้งหมด
class DeviceCommandConfirmationCard extends StatelessWidget {
  final String command;
  final Map<String, dynamic> params;
  final VoidCallback? onConfirmed;
  final VoidCallback? onCancelled;

  const DeviceCommandConfirmationCard({
    super.key,
    required this.command,
    required this.params,
    this.onConfirmed,
    this.onCancelled,
  });

  @override
  Widget build(BuildContext context) {
    final tier = DeviceCommandGate.getTier(command);
    final tierColor = _tierColor(tier);
    final icon = _commandIcon(command);
    final summary = DeviceCommandGate.summarizeCommand(command, params);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF1E1E2E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: tierColor.withAlpha(100)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: tierColor.withAlpha(50),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: tierColor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ยืนยันคำสั่ง',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'ระดับ: ${DeviceCommandGate.tierLabel(tier)}',
                        style: TextStyle(
                          color: Colors.white.withAlpha(150),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Command Details
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF121212),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: Colors.white.withAlpha(200)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      summary,
                      style: TextStyle(
                        color: Colors.white.withAlpha(230),
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      onCancelled?.call();
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white.withAlpha(150),
                      side: BorderSide(color: Colors.white.withAlpha(30)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('ยกเลิก'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      await _execute(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3CDFFF),
                      foregroundColor: const Color(0xFF0A1F4D),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'ยืนยัน',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _execute(BuildContext context) async {
    final result = await DeviceCommandService.execute(
      command,
      params: params,
      context: context,
      source: 'chat_inline',
      skipApproval: true, // User กดยืนยันแล้วจาก card
    );

    if (!context.mounted) return;

    final success = result['success'] == true;
    final message = success
        ? '✅ ทำสำเร็จแล้วค่ะ'
        : '❌ ${result['error'] ?? 'ทำไม่สำเร็จ'}';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    if (success) {
      onConfirmed?.call();
    }
  }

  Color _tierColor(CommandTier tier) {
    switch (tier) {
      case CommandTier.auto:
        return Colors.green;
      case CommandTier.notify:
        return Colors.yellow;
      case CommandTier.confirm:
        return Colors.orange;
      case CommandTier.biometric:
        return Colors.red;
    }
  }

  IconData _commandIcon(String command) {
    switch (command) {
      case 'dial_phone':
        return Icons.phone;
      case 'send_sms':
        return Icons.sms;
      case 'send_email':
        return Icons.email;
      case 'create_contact':
        return Icons.contact_page;
      case 'open_app':
        return Icons.open_in_new;
      case 'open_camera':
        return Icons.camera_alt;
      case 'open_gallery':
        return Icons.photo_library;
      case 'open_url':
        return Icons.link;
      case 'share_text':
        return Icons.share;
      case 'flashlight_on':
      case 'flashlight_off':
        return Icons.flashlight_on;
      default:
        return Icons.settings;
    }
  }
}
