// 🤖 Automation Screen — mockup UI
//
// แสดงตัวอย่าง Automation Cards (Phase 5 concept)
// - Gold Ticker 1Hr: สุ่มราคาทอง → inject เข้าแชท
// - Stock Ticker 1Hr: สุ่ม 3 หุ้น + ราคา → inject เข้าแชท
// - FAB "+" placeholder (coming soon)

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat_message.dart';
import 'chat_screen.dart' show chatHistoryProvider;

class AutomationScreen extends ConsumerStatefulWidget {
  const AutomationScreen({super.key});

  @override
  ConsumerState<AutomationScreen> createState() => _AutomationScreenState();
}

class _AutomationScreenState extends ConsumerState<AutomationScreen> {
  bool _goldEnabled = true;
  bool _stockEnabled = true;
  final _rng = Random();

  // ── Gold Ticker ─────────────────────────────────────────────

  void _runGoldTicker() {
    // สุ่มราคาทอง 96.5% ช่วง 44,500–46,500 บาท/บาท
    final price = 44500 + _rng.nextInt(2001);
    final change = (_rng.nextDouble() * 400 - 200).round(); // ±200
    final sign = change >= 0 ? '+' : '';
    final msg =
        '🥇 Gold Ticker Update\n'
        'ราคาทอง 96.5% วันนี้: ฿${_fmt(price)}/บาท\n'
        'เปลี่ยนแปลง: $sign${_fmt(change)} บาท\n'
        '📊 (ข้อมูลจำลองจาก Automation)';
    _sendToChat(msg);
  }

  // ── Stock Ticker ─────────────────────────────────────────────

  void _runStockTicker() {
    final stocks = _generateStocks();
    final lines = stocks.map((s) => '${s.$1}: ฿${_fmt(s.$2)}').join('\n');
    final msg =
        '📈 Stock Ticker Update\n'
        '$lines\n'
        '💹 (ข้อมูลจำลองจาก Automation)';
    _sendToChat(msg);
  }

  List<(String, int)> _generateStocks() {
    const consonants = 'BCDFGHJKLMNPQRSTVWXYZ';
    final results = <(String, int)>[];
    final used = <String>{};
    while (results.length < 3) {
      final sym = String.fromCharCodes([
        consonants.codeUnitAt(_rng.nextInt(consonants.length)),
        consonants.codeUnitAt(_rng.nextInt(consonants.length)),
        consonants.codeUnitAt(_rng.nextInt(consonants.length)),
      ]);
      if (used.contains(sym)) continue;
      used.add(sym);
      final price = 50 + _rng.nextInt(451); // 50–500
      results.add((sym, price));
    }
    return results;
  }

  // ── Helpers ──────────────────────────────────────────────────

  String _fmt(int n) {
    // เพิ่ม comma ทุก 3 หลัก
    final s = n.abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return n < 0 ? '-${buf.toString()}' : buf.toString();
  }

  void _sendToChat(String message) {
    ref
        .read(chatHistoryProvider.notifier)
        .addMessage(ChatMessage(
          type: ChatMessageType.assistant,
          content: message,
        ));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('ส่งข้อมูลเข้าแชทแล้ว ✅'),
        duration: Duration(seconds: 2),
        backgroundColor: Color(0xFF2A2A3E),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Automation'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline, color: Colors.white54),
            tooltip: 'เกี่ยวกับ Automation',
            onPressed: _showInfoDialog,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          // 📌 Banner
          _buildBanner(),
          const SizedBox(height: 20),

          // 🥇 Gold Ticker
          _buildAutomationCard(
            emoji: '🥇',
            title: 'Gold Ticker',
            subtitle: 'ส่งราคาทองสุ่มเข้าแชท',
            interval: '1Hr',
            enabled: _goldEnabled,
            onToggle: (v) => setState(() => _goldEnabled = v),
            onRun: _goldEnabled ? _runGoldTicker : null,
          ),
          const SizedBox(height: 12),

          // 📈 Stock Ticker
          _buildAutomationCard(
            emoji: '📈',
            title: 'Stock Ticker',
            subtitle: 'ส่งราคาหุ้น 3 ตัวสุ่มเข้าแชท',
            interval: '1Hr',
            enabled: _stockEnabled,
            onToggle: (v) => setState(() => _stockEnabled = v),
            onRun: _stockEnabled ? _runStockTicker : null,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF9B7CB6),
        tooltip: 'เพิ่ม Automation',
        onPressed: _showComingSoonSnackbar,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  // ── Widgets ──────────────────────────────────────────────────

  Widget _buildBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF9B7CB6).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF9B7CB6).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          const Text('⚡', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Automation ทำงานตามกำหนดเวลาหรือเหตุการณ์\nกดปุ่ม Run เพื่อทดลองทันที',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutomationCard({
    required String emoji,
    required String title,
    required String subtitle,
    required String interval,
    required bool enabled,
    required ValueChanged<bool> onToggle,
    required VoidCallback? onRun,
  }) {
    return Card(
      color: const Color(0xFF1E1E2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$title  •  $interval',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: enabled,
                  onChanged: onToggle,
                  activeThumbColor: const Color(0xFF9B7CB6),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: enabled
                      ? const Color(0xFF9B7CB6)
                      : Colors.white.withValues(alpha: 0.1),
                  foregroundColor: enabled ? Colors.white : Colors.white38,
                  minimumSize: const Size(90, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: onRun,
                icon: const Icon(Icons.play_arrow, size: 16),
                label: const Text('Run'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showComingSoonSnackbar() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('⚙️ Coming soon — สร้าง Automation เองได้ในอนาคต'),
        duration: Duration(seconds: 3),
        backgroundColor: Color(0xFF2A2A3E),
      ),
    );
  }

  void _showInfoDialog() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text(
          'เกี่ยวกับ Automation',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Automation ช่วยให้ Haku ทำงานอัตโนมัติตาม Trigger ที่กำหนด\n\n'
          'Phase 5 (อนาคต):\n'
          '• ตั้งเวลา / เชื่อม WiFi / เสียบชาร์จ\n'
          '• สร้าง Rule แบบ No-Code\n'
          '• ส่งข้อมูลเข้าแชท / แจ้งเตือน\n\n'
          'ตอนนี้เป็น Demo ทดลองใช้งาน',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: 13,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'ตกลง',
              style: TextStyle(color: Color(0xFF9B7CB6)),
            ),
          ),
        ],
      ),
    );
  }
}
