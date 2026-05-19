import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/device_command_audit.dart';
import '../services/device_command_gate.dart';

/// 📋 CommandAuditScreen — หน้าแสดงประวัติคำสั่งที่ Haku สั่ง smartphone
///
/// แสดง timeline ของทุกคำสั่ง พร้อมสีระดับความปลอดภัย
class CommandAuditScreen extends StatefulWidget {
  const CommandAuditScreen({super.key});

  @override
  State<CommandAuditScreen> createState() => _CommandAuditScreenState();
}

class _CommandAuditScreenState extends State<CommandAuditScreen> {
  List<AuditLogEntry> _logs = [];
  bool _isLoading = true;
  int _totalCount = 0;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);
    final logs = await DeviceCommandAudit.instance.getRecentLogs(limit: 100);
    final count = await DeviceCommandAudit.instance.getLogCount();
    setState(() {
      _logs = logs;
      _totalCount = count;
      _isLoading = false;
    });
  }

  Future<void> _clearLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2B4D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'ล้างประวัติทั้งหมด?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        content: Text(
          'ประวัติคำสั่ง $_totalCount รายการจะถูกลบถาวร',
          style: TextStyle(color: Colors.white.withAlpha(204)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('ยกเลิก', style: TextStyle(color: Colors.white.withAlpha(153))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('ล้าง'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await DeviceCommandAudit.instance.clearAll();
      await _loadLogs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ล้างประวัติเรียบร้อย')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1F4D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A1F4D),
        elevation: 0,
        title: const Text(
          'ประวัติคำสั่ง',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          if (_totalCount > 0)
            TextButton.icon(
              onPressed: _clearLogs,
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
              label: const Text('ล้าง', style: TextStyle(color: Colors.redAccent)),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF3CDFFF)))
          : _logs.isEmpty
              ? _buildEmptyState()
              : _buildLogList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history_toggle_off_outlined,
            size: 64,
            color: Colors.white.withAlpha(51),
          ),
          const SizedBox(height: 16),
          Text(
            'ยังไม่มีประวัติคำสั่ง',
            style: TextStyle(
              color: Colors.white.withAlpha(128),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Haku จะบันทึกทุกคำสั่งที่สั่ง smartphone ที่นี่',
            style: TextStyle(
              color: Colors.white.withAlpha(77),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogList() {
    // จัดกลุ่มตามวัน
    final grouped = <String, List<AuditLogEntry>>{};
    for (final log in _logs) {
      final dateKey = DateFormat('yyyy-MM-dd').format(log.timestamp);
      grouped.putIfAbsent(dateKey, () => []).add(log);
    }
    final sortedDates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return RefreshIndicator(
      onRefresh: _loadLogs,
      color: const Color(0xFF3CDFFF),
      backgroundColor: const Color(0xFF1A2B4D),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: sortedDates.length,
        itemBuilder: (context, dateIndex) {
          final date = sortedDates[dateIndex];
          final logs = grouped[date]!;
          return _buildDateSection(date, logs);
        },
      ),
    );
  }

  Widget _buildDateSection(String dateKey, List<AuditLogEntry> logs) {
    final date = DateTime.parse(dateKey);
    final now = DateTime.now();
    String dateLabel;
    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      dateLabel = 'วันนี้';
    } else if (date.year == now.year && date.month == now.month && date.day == now.day - 1) {
      dateLabel = 'เมื่อวาน';
    } else {
      dateLabel = DateFormat('d MMM yyyy', 'th').format(date);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(
            dateLabel,
            style: TextStyle(
              color: Colors.white.withAlpha(128),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        ...logs.map((log) => _buildLogCard(log)),
      ],
    );
  }

  Widget _buildLogCard(AuditLogEntry log) {
    final tierColor = _tierColor(log.tier);
    final successColor = log.success ? const Color(0xFF4CAF50) : const Color(0xFFE53935);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x991A2B4D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: tierColor.withAlpha(51),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Time
          SizedBox(
            width: 44,
            child: Text(
              log.timeFormatted,
              style: TextStyle(
                color: Colors.white.withAlpha(102),
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Tier indicator
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: tierColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        log.commandDisplayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (!log.success)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: successColor.withAlpha(38),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'ล้มเหลว',
                          style: TextStyle(
                            color: successColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                // Params summary
                if (log.params.isNotEmpty)
                  Text(
                    _formatParams(log.params),
                    style: TextStyle(
                      color: Colors.white.withAlpha(115),
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (log.error != null)
                  Text(
                    log.error!,
                    style: TextStyle(
                      color: Colors.redAccent.withAlpha(179),
                      fontSize: 11,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 6),
                // Source + Tier chips
                Row(
                  children: [
                    _buildChip(_sourceLabel(log.source), Colors.white.withAlpha(26)),
                    const SizedBox(width: 6),
                    _buildChip(
                      DeviceCommandGate.tierLabelFromString(log.tier),
                      tierColor.withAlpha(38),
                      textColor: tierColor,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(String label, Color bgColor, {Color? textColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor ?? Colors.white.withAlpha(128),
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Color _tierColor(String tier) {
    switch (tier) {
      case 'auto':
        return const Color(0xFF4CAF50);
      case 'notify':
        return const Color(0xFFFFB300);
      case 'confirm':
        return const Color(0xFFFF5722);
      case 'biometric':
        return const Color(0xFF9C27B0);
      default:
        return Colors.grey;
    }
  }

  String _sourceLabel(String source) {
    switch (source) {
      case 'user_chat':
        return 'แชท';
      case 'proactive_trigger':
        return 'อัตโนมัติ';
      case 'llm_tool':
        return 'AI';
      case 'automation':
        return 'ระบบ';
      default:
        return source;
    }
  }

  String _formatParams(Map<String, dynamic> params) {
    if (params.isEmpty) return '';
    final entries = params.entries
        .where((e) => e.value != null && e.value.toString().isNotEmpty)
        .map((e) => '${e.key}: ${e.value}')
        .take(2)
        .join(', ');
    return entries;
  }
}
