import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../models/entry.dart';
import '../services/summarization_service.dart';
import 'new_entry_screen.dart';

/// 📖 หน้าดู Entry แบบละเอียด
/// 
/// แสดงข้อมูลครบถ้วน:
/// - เนื้อหาเต็ม
/// - วันที่/เวลา
/// - ตำแหน่งที่ตั้ง + แผนที่
/// - อารมณ์ (mood)
/// - แท็ก (tags)
/// - Media (รูป/เสียง)
/// - 📝 สรุปด้วย AI

class ViewEntryScreen extends StatefulWidget {
  final Entry entry;

  const ViewEntryScreen({
    super.key,
    required this.entry,
  });

  @override
  State<ViewEntryScreen> createState() => _ViewEntryScreenState();
}

class _ViewEntryScreenState extends State<ViewEntryScreen> {
  // Cache สรุป AI — เก็บตาม entry id เพื่อไม่ต้อง generate ซ้ำ
  static final Map<int, _SummaryCache> _summaryCache = {};

  String? _summary;
  List<String>? _insights;
  bool _isSummarizing = false;
  bool _showFullText = true;

  @override
  void initState() {
    super.initState();
    // โหลดจาก cache ก่อน
    final cached = widget.entry.id != null ? _summaryCache[widget.entry.id!] : null;
    if (cached != null) {
      _summary = cached.summary;
      _insights = cached.insights;
      _showFullText = false;
      return;
    }
    // ถ้าข้อความยาว ให้สรุปอัตโนมัติ
    if (widget.entry.content.length > 150) {
      _generateSummary();
    }
  }

  Future<void> _generateSummary() async {
    if (_isSummarizing) return;

    setState(() => _isSummarizing = true);

    try {
      // ใช้ Future.wait เรียกพร้อมกัน
      final results = await Future.wait([
        SummarizationService().summarizeEntry(widget.entry),
        SummarizationService().extractInsights(widget.entry),
      ]);

      final summary = results[0] as String;
      final insights = results[1] as List<String>;

      // เก็บ cache
      if (widget.entry.id != null) {
        _summaryCache[widget.entry.id!] = _SummaryCache(summary: summary, insights: insights);
      }

      if (mounted) {
        setState(() {
          _summary = summary;
          _insights = insights;
          _isSummarizing = false;
          _showFullText = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSummarizing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('EEEE, d MMMM yyyy', 'th_TH');
    final timeFormat = DateFormat('HH:mm', 'th');
    final moodInfo = Entry.getMoodInfo(widget.entry.mood);
    final moodColor = moodInfo['color'] as int;
    final moodEmoji = moodInfo['emoji'] as String;
    final moodLabel = moodInfo['label'] as String;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('บันทึก'),
        actions: [
          // ✏️ ปุ่มแก้ไข
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _editEntry(context),
          ),
          // 📤 ปุ่มแชร์
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () => _shareEntry(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🗓️ วันที่ + อารมณ์
            Row(
              children: [
                // วันที่
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dateFormat.format(widget.entry.createdAt),
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withAlpha(100),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        timeFormat.format(widget.entry.createdAt),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // อารมณ์ (ถ้ามี)
                if (widget.entry.mood != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Color(moodColor).withAlpha(30),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Color(moodColor).withAlpha(100),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          moodEmoji,
                          style: const TextStyle(fontSize: 24),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          moodLabel,
                          style: TextStyle(
                            color: Color(moodColor),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            
            const Divider(height: 40),
            
            // 📝 เนื้อหา / สรุป
            _buildContentOrSummary(),
            
            const SizedBox(height: 30),
            
            // 📍 ตำแหน่ง (ถ้ามี)
            if (widget.entry.latitude != null && widget.entry.longitude != null)
              _buildLocationCard(),
            
            const SizedBox(height: 20),
            
            // 🏷️ แท็ก (ถ้ามี)
            if (widget.entry.tags.isNotEmpty) _buildTags(),
            
            // 🔍 Insights (ถ้ามี)
            if (_insights != null && _insights!.isNotEmpty)
              _buildInsightsCard(),
            
            // 🎵 Media (ถ้ามี - เตรียมไว้ Phase 2)
            if (widget.entry.mediaType != MediaType.none)
              _buildMediaPlaceholder(),
          ],
        ),
      ),
    );
  }

  /// 📝 แสดงเนื้อหาหรือสรุป
  Widget _buildContentOrSummary() {
    // ถ้ากำลังสรุป แสดง loading
    if (_isSummarizing) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF9B7CB6)),
            ),
            SizedBox(width: 12),
            Text(
              'กำลังสรุปบันทึกด้วย AI...',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    // ถ้ามีสรุป แสดงสรุป + ตัวเลือกดูเต็ม
    if (_summary != null && !_showFullText) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 16, color: Color(0xFF9B7CB6)),
              const SizedBox(width: 8),
              const Text(
                'สรุปด้วย AI',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF9B7CB6),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() => _showFullText = true),
                icon: const Icon(Icons.article_outlined, size: 16),
                label: const Text('ดูเต็ม'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white70,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 32),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Summary text
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF9B7CB6).withAlpha(20),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF9B7CB6).withAlpha(50)),
            ),
            child: Text(
              _summary!,
              style: const TextStyle(
                fontSize: 16,
                height: 1.6,
                color: Colors.white,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      );
    }

    // แสดงเนื้อหาเต็ม
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ถ้ามีสรุป ให้แสดงปุ่มกลับไปดูสรุป
        if (_summary != null)
          Row(
            children: [
              const Icon(Icons.article_outlined, size: 16, color: Colors.white54),
              const SizedBox(width: 8),
              const Text(
                'เนื้อหาเต็ม',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white54,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() => _showFullText = false),
                icon: const Icon(Icons.auto_awesome, size: 16),
                label: const Text('ดูสรุป'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF9B7CB6),
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 32),
                ),
              ),
            ],
          ),
        const SizedBox(height: 8),
        SelectableText(
          widget.entry.content,
          style: const TextStyle(
            fontSize: 17,
            height: 1.8,
            color: Colors.white,
          ),
        ),
        // ปุ่มสรุปถ้าข้อความยาวและยังไม่มีสรุป
        if (_summary == null && widget.entry.content.length > 150)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: OutlinedButton.icon(
              onPressed: _generateSummary,
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('สรุปด้วย AI'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF9B7CB6),
                side: const BorderSide(color: Color(0xFF9B7CB6)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 🔍 Insights Card
  Widget _buildInsightsCard() => Container(
    margin: const EdgeInsets.only(top: 20),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF1E1E2E),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.lightbulb_outline, size: 18, color: Color(0xFFFFCA28)),
            const SizedBox(width: 8),
            Text(
              'ประเด็นสำคัญ',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white.withAlpha(180),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ..._insights!.map((insight) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('• ', style: TextStyle(color: Color(0xFFFFCA28), fontSize: 16)),
              Expanded(
                child: Text(
                  insight,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ],
          ),
        )),
      ],
    ),
  );

  /// 📍 การ์ดแสดงตำแหน่ง
  Widget _buildLocationCard() => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.location_on,
                color: Color(0xFF9B7CB6),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'ตำแหน่ง',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withAlpha(150),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (widget.entry.locationName != null)
            Text(
              widget.entry.locationName!,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white,
              ),
            ),
          const SizedBox(height: 8),
          Text(
            '${widget.entry.latitude!.toStringAsFixed(6)}, ${widget.entry.longitude!.toStringAsFixed(6)}',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withAlpha(70),
              fontFamily: 'monospace',
            ),
          ),
          // TODO: Phase 2 - แสดงแผนที่ Mini ตรงนี้
        ],
      ),
    );

  /// 🏷️ แสดงแท็ก
  Widget _buildTags() => Wrap(
      spacing: 10,
      runSpacing: 10,
      children: widget.entry.tags.map((tag) => Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF9B7CB6).withAlpha(30),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFF9B7CB6).withAlpha(50),
            ),
          ),
          child: Text(
            '#$tag',
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF9B7CB6),
              fontWeight: FontWeight.w500,
            ),
          ),
        )).toList(),
    );

  /// 🎵 Placeholder สำหรับ Media
  Widget _buildMediaPlaceholder() => Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withAlpha(20),
        ),
      ),
      child: Row(
        children: [
          Icon(
            widget.entry.mediaType == MediaType.image
                ? Icons.image_outlined
                : Icons.mic_outlined,
            color: Colors.white.withAlpha(100),
            size: 32,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.entry.mediaType == MediaType.image
                      ? 'รูปภาพ'
                      : 'เสียงบันทึก',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'ฟีเจอร์นี้จะพร้อมใช้งานใน Phase 2',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withAlpha(70),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

  /// ✏️ แก้ไข Entry
  Future<void> _editEntry(BuildContext context) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute<bool>(
        builder: (context) => NewEntryScreen(existingEntry: widget.entry),
      ),
    );

    if (result == true && context.mounted) {
      // ล้าง cache เพราะเนื้อหาอาจเปลี่ยน
      if (widget.entry.id != null) {
        _summaryCache.remove(widget.entry.id!);
      }
      Navigator.pop(context, true);  // กลับไป refresh หน้า home
    }
  }

  /// 📤 แชร์ Entry
  Future<void> _shareEntry(BuildContext context) async {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E2E),
      builder: (sheetContext) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'แชร์บันทึก',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.copy, color: Colors.white70),
              title: const Text('คัดลอกข้อความ', style: TextStyle(color: Colors.white)),
              onTap: () {
                Clipboard.setData(ClipboardData(text: widget.entry.content));
                Navigator.pop(sheetContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('คัดลอกแล้ว')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.share, color: Colors.white70),
              title: const Text('แชร์ไปยังแอพอื่น', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(sheetContext);
                Share.share(_buildShareText());
              },
            ),
            ListTile(
              leading: const Icon(Icons.download, color: Colors.white70),
              title: const Text('แชร์เป็น Markdown', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(sheetContext);
                Share.share(_buildMarkdownText());
              },
            ),
          ],
        ),
      ),
    );
  }

  String _buildShareText() {
    final dateFormat = DateFormat('d MMM yyyy HH:mm', 'th');
    final buffer = StringBuffer();
    buffer.writeln(dateFormat.format(widget.entry.createdAt));
    if (widget.entry.mood != null) {
      final moodInfo = Entry.getMoodInfo(widget.entry.mood);
      buffer.writeln('${moodInfo['emoji']} ${moodInfo['label']}');
    }
    buffer.writeln();
    buffer.writeln(widget.entry.content);
    if (widget.entry.locationName != null) {
      buffer.writeln();
      buffer.writeln('📍 ${widget.entry.locationName}');
    }
    if (widget.entry.tags.isNotEmpty) {
      buffer.writeln();
      buffer.writeln(widget.entry.tags.map((t) => '#$t').join(' '));
    }
    return buffer.toString();
  }

  String _buildMarkdownText() {
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm', 'th');
    final buffer = StringBuffer();
    buffer.writeln('# บันทึก ${dateFormat.format(widget.entry.createdAt)}');
    buffer.writeln();
    if (widget.entry.mood != null) {
      final moodInfo = Entry.getMoodInfo(widget.entry.mood);
      buffer.writeln('**อารมณ์:** ${moodInfo['emoji']} ${moodInfo['label']}');
      buffer.writeln();
    }
    buffer.writeln(widget.entry.content);
    if (widget.entry.locationName != null) {
      buffer.writeln();
      buffer.writeln('**สถานที่:** ${widget.entry.locationName}');
    }
    if (widget.entry.tags.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('**แท็ก:** ${widget.entry.tags.map((t) => '`#$t`').join(' ')}');
    }
    return buffer.toString();
  }
}

class _SummaryCache {
  final String summary;
  final List<String> insights;

  _SummaryCache({required this.summary, required this.insights});
}
