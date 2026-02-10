import 'package:flutter/material.dart';

import '../models/correlation_models.dart';
import '../services/workers/correlation_worker.dart';

/// 🔮 Correlation Card - แสดงผล insights ที่ค้นพบ
/// 
/// ใช้ใน:
/// - Home Screen (แสดง insight เด่น)
/// - Insights Screen (แสดงทั้งหมด)
/// - Widget

class CorrelationCard extends StatefulWidget {
  final CorrelationInsight? insight;
  final VoidCallback? onAnalyzePressed;
  final bool showAnalyzeButton;
  final bool isLoading;

  const CorrelationCard({
    super.key,
    this.insight,
    this.onAnalyzePressed,
    this.showAnalyzeButton = true,
    this.isLoading = false,
  });

  @override
  State<CorrelationCard> createState() => _CorrelationCardState();
}

class _CorrelationCardState extends State<CorrelationCard> {
  final CorrelationWorker _worker = CorrelationWorker();
  List<CorrelationInsight> _insights = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadInsights();
  }

  Future<void> _loadInsights() async {
    if (widget.insight != null) return; // ใช้ insight ที่ส่งมา

    setState(() => _isLoading = true);
    
    try {
      final insights = await _worker.getTopInsights(limit: 5);
      if (mounted) {
        setState(() {
          _insights = insights;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final insight = widget.insight ?? _insights.firstOrNull;

    if (widget.isLoading || _isLoading) {
      return _buildLoadingCard();
    }

    if (insight == null) {
      return _buildEmptyCard();
    }

    return _buildInsightCard(insight);
  }

  /// 🔄 Loading state
  Widget _buildLoadingCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.psychology,
                    color: Colors.purple.shade600,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'กำลังวิเคราะห์...',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      Text(
                        'รอสักครู่นะคะ',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade600,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }

  /// 📭 Empty state
  Widget _buildEmptyCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.lightbulb_outline,
                    color: Colors.grey.shade600,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ยังไม่มีข้อมูลเพียงพอ',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      Text(
                        'บันทึกเพิ่มอีกสัก 5-7 วัน',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade600,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (widget.showAnalyzeButton) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: widget.onAnalyzePressed,
                  icon: const Icon(Icons.auto_fix_high),
                  label: const Text('วิเคราะห์เลย'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// ✨ Insight card
  Widget _buildInsightCard(CorrelationInsight insight) {
    final correlationColor = _getCorrelationColor(insight.correlation);
    final correlationText = _getCorrelationText(insight.correlation);
    final recommendation = insight.getRecommendation();

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.purple.shade50,
              Colors.white,
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.psychology,
                      color: Colors.purple,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ความเชื่อมโยงที่พบ',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        Text(
                          'จากการวิเคราะห์ ${insight.sampleSize} วัน',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.grey.shade600,
                              ),
                        ),
                      ],
                    ),
                  ),
                  // Correlation badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: correlationColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          insight.correlation > 0 ? Icons.trending_up : Icons.trending_down,
                          size: 16,
                          color: correlationColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          correlationText,
                          style: TextStyle(
                            color: correlationColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // Description
              Text(
                insight.description,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      height: 1.5,
                    ),
              ),

              // Entity tags
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildEntityChip(insight.entityAValue, insight.entityAType),
                  const Icon(Icons.sync_alt, size: 16, color: Colors.grey),
                  _buildEntityChip(insight.entityBValue, insight.entityBType),
                ],
              ),

              // Recommendation
              if (recommendation != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lightbulb, color: Colors.amber.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          recommendation,
                          style: TextStyle(
                            color: Colors.amber.shade900,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Analyze button (if showing more)
              if (widget.showAnalyzeButton && _insights.length > 1) ...[
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: () => _showAllInsights(context),
                  icon: const Icon(Icons.arrow_forward),
                  label: Text('ดูทั้งหมด ${_insights.length} รายการ'),
                ),
              ] else if (widget.showAnalyzeButton) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: widget.onAnalyzePressed,
                    icon: const Icon(Icons.refresh),
                    label: const Text('วิเคราะห์ใหม่'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 🏷️ Entity chip
  Widget _buildEntityChip(String value, EntityType type) {
    final icon = _getEntityIcon(type);
    final color = _getEntityColor(type);

    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(value),
      backgroundColor: color.withValues(alpha: 0.1),
      side: BorderSide(color: color.withValues(alpha: 0.3)),
      labelStyle: TextStyle(color: color.shade700, fontSize: 12),
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  /// 🎨 Correlation color
  Color _getCorrelationColor(double correlation) {
    if (correlation.abs() > 0.7) return Colors.green;
    if (correlation.abs() > 0.5) return Colors.orange;
    return Colors.blue;
  }

  /// 📝 Correlation text
  String _getCorrelationText(double correlation) {
    final percent = (correlation.abs() * 100).round();
    if (correlation.abs() > 0.7) return '${percent}%';
    if (correlation.abs() > 0.5) return '${percent}%';
    return '${percent}%';
  }

  /// 🎯 Entity icon
  IconData _getEntityIcon(EntityType type) {
    return switch (type) {
      EntityType.sleepHours => Icons.bedtime,
      EntityType.food => Icons.restaurant,
      EntityType.symptoms => Icons.healing,
      EntityType.activities => Icons.directions_run,
      EntityType.social => Icons.people,
      EntityType.weather => Icons.wb_cloudy,
      EntityType.people => Icons.person,
      EntityType.workStress => Icons.work,
      EntityType.expense => Icons.attach_money,
      EntityType.location => Icons.place,
      EntityType.mood => Icons.mood,
    };
  }

  /// 🎨 Entity color
  MaterialColor _getEntityColor(EntityType type) {
    return switch (type) {
      EntityType.sleepHours => Colors.indigo,
      EntityType.food => Colors.orange,
      EntityType.symptoms => Colors.red,
      EntityType.activities => Colors.green,
      EntityType.social => Colors.purple,
      EntityType.weather => Colors.blue,
      EntityType.people => Colors.pink,
      EntityType.workStress => Colors.brown,
      EntityType.expense => Colors.amber,
      EntityType.location => Colors.teal,
      EntityType.mood => Colors.cyan,
    };
  }

  /// 📋 Show all insights
  void _showAllInsights(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.psychology, color: Colors.purple),
                    const SizedBox(width: 8),
                    Text(
                      'ความเชื่อมโยงทั้งหมด',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // List
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: _insights.length,
                  padding: const EdgeInsets.all(16),
                  itemBuilder: (context, index) {
                    final insight = _insights[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildInsightCard(insight),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 🔮 Correlation Analyze Button - ปุ่มวิเคราะห์
class CorrelationAnalyzeButton extends StatefulWidget {
  final VoidCallback? onAnalysisComplete;

  const CorrelationAnalyzeButton({
    super.key,
    this.onAnalysisComplete,
  });

  @override
  State<CorrelationAnalyzeButton> createState() => _CorrelationAnalyzeButtonState();
}

class _CorrelationAnalyzeButtonState extends State<CorrelationAnalyzeButton> {
  final CorrelationWorker _worker = CorrelationWorker();
  bool _isAnalyzing = false;

  Future<void> _analyze() async {
    setState(() => _isAnalyzing = true);

    try {
      final result = await _worker.runFullAnalysis();
      
      if (mounted) {
        if (result != null && result.insights.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('พบ ${result.insights.length} ความเชื่อมโยง!'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ยังไม่พบความเชื่อมโยงที่ชัดเจน ลองบันทึกเพิ่มอีกสักพัก'),
            ),
          );
        }
      }

      widget.onAnalysisComplete?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาด: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isAnalyzing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: _isAnalyzing ? null : _analyze,
      icon: _isAnalyzing
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.psychology),
      label: Text(_isAnalyzing ? 'กำลังวิเคราะห์...' : 'วิเคราะห์เลย'),
    );
  }
}
