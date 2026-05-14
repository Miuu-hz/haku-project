import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';

import '../models/entry.dart';
import '../services/summarization_service.dart';
import '../utils/haku_design_tokens.dart';
import 'new_entry_screen.dart';

class ViewEntryScreen extends StatefulWidget {
  final Entry entry;

  const ViewEntryScreen({super.key, required this.entry});

  @override
  State<ViewEntryScreen> createState() => _ViewEntryScreenState();
}

class _ViewEntryScreenState extends State<ViewEntryScreen> {
  static final Map<int, _SummaryCache> _summaryCache = {};

  String? _summary;
  List<String>? _insights;
  bool _isSummarizing = false;
  bool _showFullText = true;

  @override
  void initState() {
    super.initState();
    final cached = widget.entry.id != null ? _summaryCache[widget.entry.id!] : null;
    if (cached != null) {
      _summary = cached.summary;
      _insights = cached.insights;
      _showFullText = false;
      return;
    }
    if (widget.entry.content.length > 150) {
      _generateSummary();
    }
  }

  Future<void> _generateSummary() async {
    if (_isSummarizing) return;
    setState(() => _isSummarizing = true);
    try {
      final results = await Future.wait([
        SummarizationService().summarizeEntry(widget.entry),
        SummarizationService().extractInsights(widget.entry),
      ]);
      final summary = results[0] as String;
      final insights = results[1] as List<String>;
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
      if (mounted) setState(() => _isSummarizing = false);
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

    return HakuAuroraBackground(
      children: [
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: _buildAppBar(context),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date + mood row
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dateFormat.format(widget.entry.createdAt),
                            style: const TextStyle(fontSize: 14, color: kFg3),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            timeFormat.format(widget.entry.createdAt),
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: kFg1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.entry.mood != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Color(moodColor).withAlpha(30),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Color(moodColor).withAlpha(100)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(moodEmoji, style: const TextStyle(fontSize: 24)),
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

                Divider(height: 40, color: kFg1.withAlpha(15)),

                _buildContentOrSummary(),

                const SizedBox(height: 30),

                if (widget.entry.latitude != null &&
                    widget.entry.longitude != null)
                  _buildLocationCard(),

                const SizedBox(height: 20),

                if (widget.entry.tags.isNotEmpty) _buildTags(),

                if (_insights != null && _insights!.isNotEmpty)
                  _buildInsightsCard(),

                if (widget.entry.mediaType != MediaType.none)
                  _buildMediaPlaceholder(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) => PreferredSize(
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
                'บันทึก',
                style: TextStyle(color: kFg1, fontWeight: FontWeight.w600),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, color: kFg1),
                  onPressed: () => _editEntry(context),
                ),
                IconButton(
                  icon: const Icon(Icons.share_outlined, color: kFg1),
                  onPressed: () => _shareEntry(context),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _buildContentOrSummary() {
    if (_isSummarizing) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(kR4),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: kGlassFill,
              borderRadius: BorderRadius.circular(kR4),
              border: Border.all(color: kGlassStroke),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: kLavender500),
                ),
                SizedBox(width: 12),
                Text('กำลังสรุปบันทึกด้วย AI...',
                    style: TextStyle(color: kFg3)),
              ],
            ),
          ),
        ),
      );
    }

    if (_summary != null && !_showFullText) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 16, color: kLavender500),
              const SizedBox(width: 8),
              const Text(
                'สรุปด้วย AI',
                style: TextStyle(
                  fontSize: 12,
                  color: kLavender500,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() => _showFullText = true),
                icon: const Icon(Icons.article_outlined, size: 16),
                label: const Text('ดูเต็ม'),
                style: TextButton.styleFrom(
                  foregroundColor: kFg3,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 32),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(kR4),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: kLavender500.withAlpha(18),
                  borderRadius: BorderRadius.circular(kR4),
                  border: Border.all(color: kLavender500.withAlpha(50)),
                ),
                child: Text(
                  _summary!,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.6,
                    color: kFg1,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_summary != null)
          Row(
            children: [
              const Icon(Icons.article_outlined, size: 16, color: kFg4),
              const SizedBox(width: 8),
              const Text(
                'เนื้อหาเต็ม',
                style: TextStyle(fontSize: 12, color: kFg4, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() => _showFullText = false),
                icon: const Icon(Icons.auto_awesome, size: 16),
                label: const Text('ดูสรุป'),
                style: TextButton.styleFrom(
                  foregroundColor: kLavender500,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 32),
                ),
              ),
            ],
          ),
        const SizedBox(height: 8),
        SelectableText(
          widget.entry.content,
          style: const TextStyle(fontSize: 17, height: 1.8, color: kFg1),
        ),
        if (_summary == null && widget.entry.content.length > 150)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: OutlinedButton.icon(
              onPressed: _generateSummary,
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('สรุปด้วย AI'),
              style: OutlinedButton.styleFrom(
                foregroundColor: kLavender500,
                side: const BorderSide(color: kLavender500),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildInsightsCard() => _GlassCard(
        margin: const EdgeInsets.only(top: 20),
        accentColor: kVividGold,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.lightbulb_outline, size: 18, color: kVividGold),
                SizedBox(width: 8),
                Text(
                  'ประเด็นสำคัญ',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: kFg1,
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
                      const Text('• ',
                          style: TextStyle(color: kVividGold, fontSize: 16)),
                      Expanded(
                        child: Text(insight,
                            style: const TextStyle(color: kFg1, fontSize: 14)),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      );

  Widget _buildLocationCard() => _GlassCard(
        accentColor: kCrystal400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.location_on, color: kLavender500, size: 20),
                SizedBox(width: 8),
                Text(
                  'ตำแหน่ง',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: kFg1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (widget.entry.locationName != null)
              Text(
                widget.entry.locationName!,
                style: const TextStyle(fontSize: 16, color: kFg1),
              ),
            const SizedBox(height: 8),
            Text(
              '${widget.entry.latitude!.toStringAsFixed(6)}, '
              '${widget.entry.longitude!.toStringAsFixed(6)}',
              style: const TextStyle(
                fontSize: 12,
                color: kFg4,
                fontFamily: 'monospace',
              ),
            ),
            if (widget.entry.latitude != null &&
                widget.entry.longitude != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: 200,
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: LatLng(
                          widget.entry.latitude!, widget.entry.longitude!),
                      initialZoom: 15,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.none,
                      ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.haku.app',
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: LatLng(widget.entry.latitude!,
                                widget.entry.longitude!),
                            width: 40,
                            height: 40,
                            child: const Icon(Icons.location_on,
                                color: kErr, size: 40),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      );

  Widget _buildTags() => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: widget.entry.tags
              .map((tag) => Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: kCrystal400.withAlpha(20),
                      borderRadius: BorderRadius.circular(20),
                      border:
                          Border.all(color: kCrystal400.withAlpha(60)),
                    ),
                    child: Text(
                      '#$tag',
                      style: const TextStyle(
                        fontSize: 14,
                        color: kCrystal600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ))
              .toList(),
        ),
      );

  Widget _buildMediaPlaceholder() => _GlassCard(
        margin: const EdgeInsets.only(top: 20),
        accentColor: kFg4,
        child: Row(
          children: [
            Icon(
              widget.entry.mediaType == MediaType.image
                  ? Icons.image_outlined
                  : Icons.mic_outlined,
              color: kFg4,
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
                        color: kFg1),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'ฟีเจอร์นี้จะพร้อมใช้งานใน Phase 2',
                    style: TextStyle(fontSize: 12, color: kFg4),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Future<void> _editEntry(BuildContext context) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute<bool>(
        builder: (context) => NewEntryScreen(existingEntry: widget.entry),
      ),
    );
    if (result == true && context.mounted) {
      if (widget.entry.id != null) _summaryCache.remove(widget.entry.id!);
      Navigator.pop(context, true);
    }
  }

  Future<void> _shareEntry(BuildContext context) async {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kFieldTop,
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
                  color: kFg1),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading:
                  const Icon(Icons.copy, color: kFg3),
              title: const Text('คัดลอกข้อความ',
                  style: TextStyle(color: kFg1)),
              onTap: () {
                Clipboard.setData(
                    ClipboardData(text: widget.entry.content));
                Navigator.pop(sheetContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('คัดลอกแล้ว')),
                );
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.share, color: kFg3),
              title: const Text('แชร์ไปยังแอพอื่น',
                  style: TextStyle(color: kFg1)),
              onTap: () {
                Navigator.pop(sheetContext);
                Share.share(_buildShareText());
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.download, color: kFg3),
              title: const Text('แชร์เป็น Markdown',
                  style: TextStyle(color: kFg1)),
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
      buffer
          .writeln('**แท็ก:** ${widget.entry.tags.map((t) => '`#$t`').join(' ')}');
    }
    return buffer.toString();
  }
}

// ── Glass card helper ──────────────────────────────────────────

class _GlassCard extends StatelessWidget {
  final Widget child;
  final Color accentColor;
  final EdgeInsetsGeometry margin;

  const _GlassCard({
    required this.child,
    this.accentColor = kCrystal400,
    this.margin = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: margin,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(kR4),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              decoration: BoxDecoration(
                color: kGlassFill,
                borderRadius: BorderRadius.circular(kR4),
                border: Border.all(color: kGlassStroke, width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(kR4)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: child,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _SummaryCache {
  final String summary;
  final List<String> insights;
  _SummaryCache({required this.summary, required this.insights});
}
