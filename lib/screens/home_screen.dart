import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/entry.dart';
import '../models/objective.dart';
import '../services/correlation_service.dart';
import '../services/database_helper.dart';
import '../services/objective_service.dart';
import '../services/scheduler_service.dart';
import '../services/social_battery_service.dart';
import '../services/streak_service.dart';
import '../services/weather_service.dart';
import '../utils/haku_design_tokens.dart';
import '../widgets/caustic_shimmer.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';
import 'view_entry_screen.dart';

// ══════════════════════════════════════════════════════════════
// Provider
// ══════════════════════════════════════════════════════════════

final entriesProvider = FutureProvider<List<Entry>>(
  (ref) => DatabaseHelper.instance.getAllEntries(limit: 50),
);

// ══════════════════════════════════════════════════════════════
// ⏰ Time Period
// ══════════════════════════════════════════════════════════════

String _greetingFor(int hour) {
  if (hour >= 5 && hour < 12) return 'อรุณสวัสดิ์ค่ะ';
  if (hour >= 12 && hour < 17) return 'สวัสดีตอนเที่ยงค่ะ';
  if (hour >= 17 && hour < 22) return 'สวัสดีตอนเย็นค่ะ';
  return 'ราตรีสวัสดิ์ค่ะ';
}

// ══════════════════════════════════════════════════════════════
// 🏠 HomeScreen
// ══════════════════════════════════════════════════════════════

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin {

  // 🌊 Blob animation
  late final AnimationController _blobCtrl;
  late final Animation<double> _blob1X, _blob1Y, _blob1S;
  late final Animation<double> _blob2X, _blob2Y, _blob2S;
  late final Animation<double> _blob3X, _blob3Y, _blob3S;

  // ✨ Card intro
  late final AnimationController _introCtrl;
  late final Animation<double> _headerAnim;
  late final Animation<double> _card1Anim;
  late final Animation<double> _card2Anim;
  late final Animation<double> _card3Anim;
  late final Animation<double> _pillAnim;

  // Dashboard data
  DayForecast? _weather;
  List<Map<String, dynamic>> _todayEvents = [];
  List<Objective> _activeObjectives = [];
  int _streak = 0;
  CorrelationInsight? _topInsight;
  SocialBatteryResult? _socialBattery;
  // mood: list of (dayLabel, avgMood) sorted oldest→newest, only days with entries
  List<({String label, double mood})> _moodHistory = [];

  @override
  void initState() {
    super.initState();

    _blobCtrl = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    )..repeat(reverse: true);

    _blob1X = Tween<double>(begin: 0, end: 30).animate(
        CurvedAnimation(parent: _blobCtrl, curve: Curves.easeInOut));
    _blob1Y = Tween<double>(begin: 0, end: 50).animate(
        CurvedAnimation(parent: _blobCtrl, curve: Curves.easeInOut));
    _blob1S = Tween<double>(begin: 1.0, end: 1.1).animate(
        CurvedAnimation(parent: _blobCtrl, curve: Curves.easeInOut));

    _blob2X = Tween<double>(begin: 0, end: 30).animate(
        CurvedAnimation(parent: _blobCtrl,
            curve: const Interval(0.2, 1.0, curve: Curves.easeInOut)));
    _blob2Y = Tween<double>(begin: 0, end: 50).animate(
        CurvedAnimation(parent: _blobCtrl,
            curve: const Interval(0.2, 1.0, curve: Curves.easeInOut)));
    _blob2S = Tween<double>(begin: 1.0, end: 1.1).animate(
        CurvedAnimation(parent: _blobCtrl,
            curve: const Interval(0.2, 1.0, curve: Curves.easeInOut)));

    _blob3X = Tween<double>(begin: 0, end: 30).animate(
        CurvedAnimation(parent: _blobCtrl,
            curve: const Interval(0.4, 1.0, curve: Curves.easeInOut)));
    _blob3Y = Tween<double>(begin: 0, end: 50).animate(
        CurvedAnimation(parent: _blobCtrl,
            curve: const Interval(0.4, 1.0, curve: Curves.easeInOut)));
    _blob3S = Tween<double>(begin: 1.0, end: 1.1).animate(
        CurvedAnimation(parent: _blobCtrl,
            curve: const Interval(0.4, 1.0, curve: Curves.easeInOut)));

    _introCtrl = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    )..forward();

    _headerAnim = _iv(0.0,  0.5);
    _card1Anim  = _iv(0.1,  0.6);
    _card2Anim  = _iv(0.25, 0.75);
    _card3Anim  = _iv(0.4,  0.9);
    _pillAnim   = _iv(0.55, 1.0);

    _loadDashboardData();
  }

  Animation<double> _iv(double begin, double end) => CurvedAnimation(
    parent: _introCtrl,
    curve: Interval(begin, end, curve: Curves.easeOutCubic),
  );

  @override
  void dispose() {
    _blobCtrl.dispose();
    _introCtrl.dispose();
    super.dispose();
  }

  // ── Data loading ──────────────────────────────────────────

  Future<void> _loadDashboardData() async {
    await Future.wait<void>([
      _loadWeather(),
      _loadCalendarEvents(),
      _loadObjectives(),
      _loadStreak(),
      _loadInsights(),
      _loadSocialBattery(),
      _loadMoodHistory(),
    ]);
  }

  Future<void> _loadMoodHistory() async {
    try {
      final all = await DatabaseHelper.instance.getAllEntries();
      final now = DateTime.now();
      final days = <String, List<int>>{};

      for (var i = 6; i >= 0; i--) {
        final d = now.subtract(Duration(days: i));
        final key = '${d.month}/${d.day}';
        days[key] = [];
      }

      for (final e in all) {
        if (e.mood == null) continue;
        final age = now.difference(e.createdAt).inDays;
        if (age > 6) continue;
        final key = '${e.createdAt.month}/${e.createdAt.day}';
        days[key]?.add(e.mood!);
      }

      final history = days.entries
          .where((kv) => kv.value.isNotEmpty)
          .map((kv) => (
                label: kv.key,
                mood: kv.value.reduce((a, b) => a + b) / kv.value.length,
              ))
          .toList();

      if (mounted) setState(() => _moodHistory = history);
    } catch (_) {}
  }

  Future<void> _loadWeather() async {
    try {
      final today = await WeatherService().getTodayForecast();
      if (mounted && today != null) setState(() => _weather = today);
    } catch (_) {}
  }

  Future<void> _loadCalendarEvents() async {
    try {
      final now      = DateTime.now();
      final dayStart = DateTime(now.year, now.month, now.day);
      final dayEnd   = dayStart.add(const Duration(days: 1));
      final events   = await SchedulerService().getCalendarEvents(dayStart, dayEnd);
      if (mounted) setState(() => _todayEvents = events);
    } catch (_) {}
  }

  Future<void> _loadObjectives() async {
    try {
      final svc = ObjectiveService();
      await svc.initialize();
      final active = svc.objectives
          .where((o) =>
              o.status == ObjectiveStatus.pending ||
              o.status == ObjectiveStatus.inProgress ||
              o.status == ObjectiveStatus.overdue)
          .toList();
      if (mounted) setState(() => _activeObjectives = active);
    } catch (_) {}
  }

  Future<void> _loadStreak() async {
    try {
      final svc = StreakService();
      await svc.initialize();
      if (mounted) setState(() => _streak = svc.currentStreak);
    } catch (_) {}
  }

  Future<void> _loadInsights() async {
    try {
      final insights = await CorrelationService().analyze();
      if (mounted && insights.isNotEmpty) {
        setState(() => _topInsight = insights.first);
      }
    } catch (_) {}
  }

  Future<void> _loadSocialBattery() async {
    try {
      final result = await SocialBatteryService().analyze();
      if (mounted) setState(() => _socialBattery = result);
    } catch (_) {}
  }

  Future<void> _refreshData() async {
    ref.invalidate(entriesProvider);
    await _loadDashboardData();
  }

  // ── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(entriesProvider);
    final now     = DateTime.now();
    final dateStr = DateFormat('EEEEที่ d MMM', 'th').format(now);

    return Stack(
      children: [
        // ① Blob background
        Positioned.fill(
          child: _BlobBackground(
            ctrl: _blobCtrl,
            b1x: _blob1X, b1y: _blob1Y, b1s: _blob1S,
            b2x: _blob2X, b2y: _blob2Y, b2s: _blob2S,
            b3x: _blob3X, b3y: _blob3Y, b3s: _blob3S,
          ),
        ),

        // ② Main scaffold
        Scaffold(
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: true,
          appBar: _buildGlassAppBar(dateStr),
          body: RefreshIndicator(
            onRefresh: _refreshData,
            color: kCrystal400,
            backgroundColor: Colors.white,
            child: CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(
                  child: SizedBox(height: kToolbarHeight + 20),
                ),

                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Intro(
                          anim: _headerAnim,
                          child: _HeaderSection(
                            greeting: _greetingFor(now.hour),
                            dateStr: dateStr,
                            eventCount: _todayEvents.length,
                          ),
                        ),
                        const SizedBox(height: 24),

                        if (_weather != null) ...[
                          _Intro(
                            anim: _card1Anim,
                            child: _WeatherCard(weather: _weather!),
                          ),
                          const SizedBox(height: 20),
                        ],

                        if (_todayEvents.isNotEmpty) ...[
                          _Intro(
                            anim: _card2Anim,
                            child: _CalendarCard(events: _todayEvents),
                          ),
                          const SizedBox(height: 20),
                        ],

                        if (_activeObjectives.isNotEmpty) ...[
                          _Intro(
                            anim: _card3Anim,
                            child: _GoalsCard(objectives: _activeObjectives),
                          ),
                          const SizedBox(height: 20),
                        ],

                        if (_streak > 0) ...[
                          _Intro(
                            anim: _card3Anim,
                            child: _StreakBadge(streak: _streak),
                          ),
                          const SizedBox(height: 20),
                        ],

                        if (_socialBattery != null) ...[
                          _Intro(
                            anim: _card3Anim,
                            child: _SocialBatteryCard(result: _socialBattery!),
                          ),
                          const SizedBox(height: 20),
                        ],

                        if (_topInsight != null) ...[
                          _Intro(
                            anim: _card3Anim,
                            child: _InsightCard(insight: _topInsight!),
                          ),
                          const SizedBox(height: 20),
                        ],

                        if (_moodHistory.length >= 2) ...[
                          _Intro(
                            anim: _card3Anim,
                            child: _MoodTrendCard(history: _moodHistory),
                          ),
                          const SizedBox(height: 20),
                        ],

                        _buildDivider(),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),

                entriesAsync.when(
                  data: (entries) {
                    if (entries.isEmpty) {
                      return SliverToBoxAdapter(child: _buildEmptyState());
                    }
                    return SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 120),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (_, i) => _EntryCard(
                            entry: entries[i],
                            onTap: () => _openEntry(entries[i]),
                            onDelete: () => _deleteEntry(entries[i]),
                          ),
                          childCount: entries.length,
                        ),
                      ),
                    );
                  },
                  loading: () => const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(
                        child: CircularProgressIndicator(color: kCrystal400),
                      ),
                    ),
                  ),
                  error: (e, _) => SliverToBoxAdapter(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('เกิดข้อผิดพลาด: $e',
                            style: const TextStyle(color: kFg3)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ③ Floating bottom action pill
        Positioned(
          bottom: 30,
          left: 24,
          right: 24,
          child: _Intro(
            anim: _pillAnim,
            child: _BottomActionPill(
              onChatTap: () => Navigator.push(
                context,
                MaterialPageRoute<bool>(builder: (_) => const ChatScreen()),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Glass AppBar ────────────────────────────────────────────

  PreferredSizeWidget _buildGlassAppBar(String dateStr) => PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: AppBar(
              backgroundColor: kGlassFill,
              elevation: 0,
              shadowColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              title: Text(
                dateStr,
                style: const TextStyle(
                  color: kFg1,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.settings_outlined, color: kFg1),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<bool>(
                        builder: (_) => const SettingsScreen()),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  // ── Helpers ─────────────────────────────────────────────────

  Widget _buildDivider() => Row(
        children: [
          const Icon(Icons.book_outlined, size: 16, color: kFg3),
          const SizedBox(width: 8),
          const Text(
            'บันทึก',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: kFg3,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Divider(
              color: kFg1.withAlpha(15),
              thickness: 1,
            ),
          ),
        ],
      );

  Widget _buildEmptyState() => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 120),
        child: Column(
          children: [
            Icon(Icons.inbox_outlined,
                size: 56, color: kFg3.withAlpha(100)),
            const SizedBox(height: 12),
            const Text('ยังไม่มีบันทึก',
                style: TextStyle(
                    fontSize: 17,
                    color: kFg3,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            const Text('แตะ "เริ่มบันทึก" เพื่อบันทึกชีวิตของคุณ',
                style: TextStyle(fontSize: 13, color: kFg3),
                textAlign: TextAlign.center),
          ],
        ),
      );

  Future<void> _openEntry(Entry entry) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(builder: (_) => ViewEntryScreen(entry: entry)),
    );
    if (result == true) _refreshData();
  }

  Future<void> _deleteEntry(Entry entry) async {
    if (entry.id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ลบบันทึก?'),
        content: const Text('การลบนี้ไม่สามารถกู้คืนได้'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: kErr),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await DatabaseHelper.instance.deleteEntry(entry.id!);
      _refreshData();
    }
  }
}

// ══════════════════════════════════════════════════════════════
// 🌊 Animated Blob Background
// ══════════════════════════════════════════════════════════════

class _BlobBackground extends StatelessWidget {
  final AnimationController ctrl;
  final Animation<double> b1x, b1y, b1s;
  final Animation<double> b2x, b2y, b2s;
  final Animation<double> b3x, b3y, b3s;

  const _BlobBackground({
    required this.ctrl,
    required this.b1x, required this.b1y, required this.b1s,
    required this.b2x, required this.b2y, required this.b2s,
    required this.b3x, required this.b3y, required this.b3s,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (_, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          return AnimatedBuilder(
            animation: ctrl,
            builder: (_, __) => Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [kFieldTop, kFieldMid, kFieldBot],
                  stops: [0.0, 0.45, 1.0],
                ),
              ),
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned(
                    top: -h * 0.10 + b1y.value,
                    left: -w * 0.10 + b1x.value,
                    child: Transform.scale(
                      scale: b1s.value,
                      child: const _Blob(color: kOrbCyan, size: 360),
                    ),
                  ),
                  Positioned(
                    top: h * 0.20 + b2y.value,
                    right: -w * 0.20 + b2x.value,
                    child: Transform.scale(
                      scale: b2s.value,
                      child: const _Blob(color: kOrbLavender, size: 380),
                    ),
                  ),
                  Positioned(
                    bottom: -h * 0.10 + b3y.value,
                    left: w * 0.20 + b3x.value,
                    child: Transform.scale(
                      scale: b3s.value,
                      child: const _Blob(color: kOrbMagenta, size: 280),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
}

class _Blob extends StatelessWidget {
  final Color color;
  final double size;
  const _Blob({required this.color, required this.size});

  @override
  Widget build(BuildContext context) => ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      );
}

// ══════════════════════════════════════════════════════════════
// ✨ Slide-up fade intro wrapper
// ══════════════════════════════════════════════════════════════

class _Intro extends StatelessWidget {
  final Animation<double> anim;
  final Widget child;
  const _Intro({required this.anim, required this.child});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: anim,
        builder: (_, child) {
          final v = anim.value.clamp(0.0, 1.0);
          return Opacity(
            opacity: v,
            child: Transform.translate(
              offset: Offset(0, 20 * (1 - v)),
              child: child,
            ),
          );
        },
        child: child,
      );
}

// ══════════════════════════════════════════════════════════════
// 🪟 Glass Card — with Caustic Shimmer
// ══════════════════════════════════════════════════════════════

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) => CausticShimmer(
        borderRadius: BorderRadius.circular(kR4),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(kR4),
            boxShadow: const [
              BoxShadow(color: kGlassStroke, blurRadius: 0, spreadRadius: 1),
              BoxShadow(
                color: Color(0x40283C82),
                blurRadius: 28,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(kR4),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: kGlassFill,
                  borderRadius: BorderRadius.all(Radius.circular(kR4)),
                  border: Border(
                    top:    BorderSide(color: kGlassEdge, width: 1),
                    left:   BorderSide(color: kGlassStroke, width: 0.5),
                    right:  BorderSide(color: kGlassStroke, width: 0.5),
                    bottom: BorderSide(color: kGlassStroke, width: 0.5),
                  ),
                ),
                child: child,
              ),
            ),
          ),
        ),
      );
}

// ══════════════════════════════════════════════════════════════
// 📋 Header Section
// ══════════════════════════════════════════════════════════════

class _HeaderSection extends StatelessWidget {
  final String greeting;
  final String dateStr;
  final int eventCount;

  const _HeaderSection({
    required this.greeting,
    required this.dateStr,
    required this.eventCount,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(130),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: kGlassEdge),
                ),
                child: Text(
                  dateStr,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: kCrystal500,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          Text(
            greeting,
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w700,
              color: kFg1,
              height: 1.1,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),

          RichText(
            text: TextSpan(
              style: const TextStyle(
                fontSize: 16,
                color: kFg3,
                height: 1.4,
              ),
              children: [
                const TextSpan(text: 'Haku ประมวลผล '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [kVividMagenta, kVividGold],
                    ).createShader(bounds),
                    child: const Text(
                      'ข้อมูลบนเครื่อง',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const TextSpan(text: ' เรียบร้อยแล้ว'),
                if (eventCount > 0)
                  TextSpan(text: '\nวันนี้คุณมี $eventCount นัดหมายสำคัญ'),
              ],
            ),
          ),
        ],
      );
}

// ══════════════════════════════════════════════════════════════
// 🌤️ Weather Card
// ══════════════════════════════════════════════════════════════

class _WeatherCard extends StatelessWidget {
  final DayForecast weather;
  const _WeatherCard({required this.weather});

  @override
  Widget build(BuildContext context) => _GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: '${weather.maxTemp.round()}°',
                              style: const TextStyle(
                                fontSize: 48,
                                fontWeight: FontWeight.w300,
                                color: kFg1,
                                letterSpacing: -2,
                                height: 1,
                              ),
                            ),
                            const TextSpan(
                              text: 'C',
                              style: TextStyle(
                                fontSize: 24,
                                color: kFg4,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        weather.description,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: kFg3,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  weather.emoji,
                  style: const TextStyle(fontSize: 56),
                ),
              ],
            ),
            const SizedBox(height: 14),

            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(130),
                borderRadius: BorderRadius.circular(kR3),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lightbulb_outline, size: 18, color: kFg3),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _nudge(weather.maxTemp, weather.description),
                      style: const TextStyle(
                        fontSize: 15,
                        color: kFg1,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  String _nudge(double temp, String desc) {
    final d = desc.toLowerCase();
    if (d.contains('ฝน') ||
        d.contains('rain') ||
        d.contains('shower') ||
        d.contains('thunder')) {
      return 'พกร่มไปด้วยนะคะ วันนี้มีฝนตก';
    }
    if (temp > 35) return 'อากาศร้อนมาก ควรพกน้ำและทาครีมกันแดดค่ะ';
    if (temp < 22) return 'อากาศเย็นสบาย ใส่เสื้อกันหนาวด้วยก็ดีค่ะ';
    return 'พกเสื้อคลุมไปด้วยนะคะ ช่วงบ่ายอาจมีฝนตก';
  }
}

// ══════════════════════════════════════════════════════════════
// 📅 Calendar Card
// ══════════════════════════════════════════════════════════════

class _CalendarCard extends StatelessWidget {
  final List<Map<String, dynamic>> events;
  const _CalendarCard({required this.events});

  static const _colors = [kCrystal400, kVividGold, kVividMint];

  @override
  Widget build(BuildContext context) {
    final shown = events.take(3).toList();
    final more = events.length > 3 ? events.length - 3 : 0;

    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_today_outlined, size: 18, color: kFg1),
              const SizedBox(width: 8),
              Text(
                'ตารางวันนี้ (${events.length})',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: kFg1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          ...shown.asMap().entries.map((e) {
            final i      = e.key;
            final ev     = e.value;
            final title  = ev['title']    as String? ?? 'กิจกรรม';
            final loc    = ev['location'] as String?;
            final startMs = ev['startTime'] as int?;
            final timeStr = startMs != null
                ? DateFormat('HH:mm')
                    .format(DateTime.fromMillisecondsSinceEpoch(startMs))
                : '--:--';
            final color = _colors[i % _colors.length];
            final isLast = i == shown.length - 1;

            return Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 50,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        timeStr,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: kFg3,
                        ),
                      ),
                    ),
                  ),

                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(200),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: kGlassStroke),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(5),
                            blurRadius: 15,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(width: 4, color: color),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                      12, 14, 16, 14),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: kFg1,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (loc != null) ...[
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            const Icon(Icons.location_on_outlined, size: 12, color: kFg3),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                loc,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  color: kFg3,
                                                ),
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),

          if (more > 0) ...[
            const SizedBox(height: 12),
            Text('+$more นัดอื่น',
                style: const TextStyle(fontSize: 13, color: kFg3)),
          ],
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 🎯 Goals Card
// ══════════════════════════════════════════════════════════════

typedef _GoalStyle = ({double progress, Color color, IconData? icon, String label});

class _GoalsCard extends StatelessWidget {
  final List<Objective> objectives;
  const _GoalsCard({required this.objectives});

  static const _GoalStyle _kDone = (progress: 1.0, color: kVividMint, icon: Icons.check_circle_outline, label: 'เสร็จแล้ว');
  static final Map<ObjectiveStatus, _GoalStyle> _kStyle = {
    ObjectiveStatus.inProgress: (progress: 0.5, color: kCrystal400,  icon: Icons.adjust, label: 'กำลังดำเนินการ'),
    ObjectiveStatus.overdue:    (progress: 0.3, color: kVividMagenta, icon: Icons.warning_amber_rounded, label: 'เกินกำหนดแล้ว'),
    ObjectiveStatus.pending:    (progress: 0.0, color: kVividMint, icon: Icons.radio_button_unchecked, label: 'ยังไม่ได้เริ่มเลย'),
  };

  @override
  Widget build(BuildContext context) {
    final shown = objectives.take(3).toList();

    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.track_changes_outlined, size: 18, color: kFg1),
              SizedBox(width: 8),
              Text(
                'เป้าหมายประจำวัน',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: kFg1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          ...shown.asMap().entries.map((e) {
            final i    = e.key;
            final o    = e.value;
            final isLast = i == shown.length - 1;
            final style    = _kStyle[o.status] ?? _kDone;
            final subLabel = o.dueTime ?? style.label;

            return Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(12),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Icon(style.icon, size: 20, color: style.color),
                  ),
                  const SizedBox(width: 12),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          o.title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: kFg1,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          subLabel,
                          style: const TextStyle(
                              fontSize: 13, color: kFg3),
                        ),
                      ],
                    ),
                  ),

                  _ProgressCircle(value: style.progress, color: style.color),
                ],
              ),
            );
          }),

          if (objectives.length > 3) ...[
            const SizedBox(height: 12),
            Text('+${objectives.length - 3} อื่นๆ',
                style: const TextStyle(fontSize: 13, color: kFg3)),
          ],
        ],
      ),
    );
  }
}

// ── Circular progress ─────────

class _ProgressCircle extends StatelessWidget {
  final double value; // 0.0 – 1.0
  final Color color;
  const _ProgressCircle({required this.value, required this.color});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 44,
        height: 44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: value,
              strokeWidth: 4,
              backgroundColor: const Color(0xFFE5E5EA),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
            Container(
              width: 36,
              height: 36,
              decoration:
                  const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Text(
                '${(value * 100).round()}%',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      );
}

// ══════════════════════════════════════════════════════════════
// 🍅 Focus Streak badge
// ══════════════════════════════════════════════════════════════

class _StreakBadge extends StatelessWidget {
  final int streak;
  const _StreakBadge({required this.streak});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: CausticShimmer(
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(165),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: kGlassEdge),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.local_fire_department_outlined, size: 18, color: kVividGold),
                  const SizedBox(width: 8),
                  const Text('Focus Streak',
                      style: TextStyle(fontSize: 13, color: kFg3)),
                  const SizedBox(width: 8),
                  Text(
                    '$streak วัน',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: kVividGold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

// ══════════════════════════════════════════════════════════════
// ⬇️ Floating Bottom Action Pill
// ══════════════════════════════════════════════════════════════

class _BottomActionPill extends StatelessWidget {
  final VoidCallback onChatTap;
  const _BottomActionPill({required this.onChatTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onChatTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(100),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(50),
                blurRadius: 40,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
                decoration: BoxDecoration(
                  color: kField0.withAlpha(215),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome, size: 18, color: kVividGold),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Haku AI',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFF7BEBFF), kCrystal400],
                        ),
                        borderRadius: BorderRadius.circular(100),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x723CDFFF),
                            blurRadius: 24,
                          ),
                        ],
                      ),
                      child: const Text(
                        'เริ่มบันทึก',
                        style: TextStyle(
                          color: kFgOnCyan,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

// ══════════════════════════════════════════════════════════════
// 🗒️ Journal Entry Card (glass + shimmer)
// ══════════════════════════════════════════════════════════════

class _EntryCard extends StatelessWidget {
  final Entry entry;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _EntryCard({
    required this.entry,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM yyyy · HH:mm', 'th');
    final moodInfo   = Entry.getMoodInfo(entry.mood);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: CausticShimmer(
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.all(Radius.circular(18)),
            boxShadow: [
              BoxShadow(color: kGlassStroke, blurRadius: 0, spreadRadius: 1),
              BoxShadow(
                color: Color(0x30283C82),
                blurRadius: 20,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                decoration: const BoxDecoration(
                  color: kGlassFill,
                  borderRadius: BorderRadius.all(Radius.circular(18)),
                  border: Border(
                    top:    BorderSide(color: kGlassEdge, width: 1),
                    left:   BorderSide(color: kGlassStroke, width: 0.5),
                    right:  BorderSide(color: kGlassStroke, width: 0.5),
                    bottom: BorderSide(color: kGlassStroke, width: 0.5),
                  ),
                ),
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(18),
                  splashColor: const Color(0x0A3CDFFF),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              dateFormat.format(entry.createdAt),
                              style: const TextStyle(fontSize: 12, color: kFg3),
                            ),
                            const Spacer(),
                            if (entry.mediaType != MediaType.none) ...[
                              Icon(
                                entry.mediaType == MediaType.image
                                    ? Icons.image_outlined
                                    : Icons.mic_outlined,
                                size: 15,
                                color: kFg3,
                              ),
                              const SizedBox(width: 6),
                            ],
                            Text(moodInfo['emoji'] as String,
                                style: const TextStyle(fontSize: 16)),
                          ],
                        ),
                        const SizedBox(height: 10),

                        Text(
                          entry.content,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.5,
                            color: kFg1,
                          ),
                        ),

                        if (entry.locationName != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.location_on_outlined,
                                  size: 13, color: kFg3),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  entry.locationName!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      const TextStyle(fontSize: 12, color: kFg3),
                                ),
                              ),
                            ],
                          ),
                        ],

                        if (entry.tags.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: entry.tags
                                .map(
                                  (tag) => Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: kCrystal400.withAlpha(20),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      '#$tag',
                                      style: const TextStyle(
                                          fontSize: 12, color: kCrystal600),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// ⚡ Social Battery Card
// ══════════════════════════════════════════════════════════════

class _SocialBatteryCard extends StatelessWidget {
  final SocialBatteryResult result;
  const _SocialBatteryCard({required this.result});

  static const _trendIcon = {
    BatteryTrend.draining:   Icons.trending_down,
    BatteryTrend.stable:     Icons.trending_flat,
    BatteryTrend.recharging: Icons.trending_up,
  };

  static const _trendColor = {
    BatteryTrend.draining:   kVividMagenta,
    BatteryTrend.stable:     kVividGold,
    BatteryTrend.recharging: kVividMint,
  };

  @override
  Widget build(BuildContext context) {
    final pct   = result.level / 100.0;
    final color = pct >= 0.6
        ? kVividMint
        : pct >= 0.35
            ? kVividGold
            : kVividMagenta;
    final trendColor = _trendColor[result.trend]!;
    final trendIcon  = _trendIcon[result.trend]!;

    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt_outlined, size: 18, color: kFg1),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'พลังงานสังคม',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: kFg1,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: trendColor.withAlpha(30),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(trendIcon, size: 12, color: trendColor),
                    const SizedBox(width: 4),
                    Text(
                      '${result.level}%',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: trendColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 10,
              backgroundColor: const Color(0xFFE5E5EA),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(130),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.lightbulb_outline, size: 16, color: kFg3),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    result.message,
                    style: const TextStyle(
                      fontSize: 14,
                      color: kFg1,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 🔍 Hidden Correlation Insight Card
// ══════════════════════════════════════════════════════════════

class _InsightCard extends StatelessWidget {
  final CorrelationInsight insight;
  const _InsightCard({required this.insight});

  @override
  Widget build(BuildContext context) {
    final accent = insight.isPositive ? kVividMint : kVividGold;
    final pct    = (insight.confidence * 100).round();

    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights_outlined, size: 18, color: kFg1),
              const SizedBox(width: 8),
              const Text(
                'ค้นพบ Pattern',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: kFg1,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.withAlpha(30),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$pct%',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: accent.withAlpha(18),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accent.withAlpha(50)),
            ),
            child: Text(
              insight.message,
              style: const TextStyle(
                fontSize: 15,
                color: kFg1,
                height: 1.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 8),

          Text(
            'จาก ${insight.sampleSize} บันทึก · ${insight.hitCount} ครั้งที่ตรงกัน',
            style: const TextStyle(fontSize: 12, color: kFg3),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 📈 Mood Trend Card (7-day sparkline)
// ══════════════════════════════════════════════════════════════

class _MoodTrendCard extends StatelessWidget {
  final List<({String label, double mood})> history;
  const _MoodTrendCard({required this.history});

  @override
  Widget build(BuildContext context) {
    final avg = history.map((h) => h.mood).reduce((a, b) => a + b) / history.length;
    final trend = history.length >= 2
        ? history.last.mood - history.first.mood
        : 0.0;
    final trendIcon = trend > 0.3 ? '↑' : trend < -0.3 ? '↓' : '→';
    final trendColor = trend > 0.3
        ? const Color(0xFF34C759)
        : trend < -0.3
            ? const Color(0xFFFF3B30)
            : kFg2;

    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('📈', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              const Text(
                'อารมณ์ 7 วัน',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kFg1),
              ),
              const Spacer(),
              Text(
                '${avg.toStringAsFixed(1)}/5 $trendIcon',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: trendColor),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 72,
            child: CustomPaint(
              painter: _MoodSparklinePainter(history),
              size: Size.infinite,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: history
                .map((h) => Text(h.label, style: const TextStyle(fontSize: 10, color: kFg3)))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _MoodSparklinePainter extends CustomPainter {
  final List<({String label, double mood})> history;
  _MoodSparklinePainter(this.history);

  @override
  void paint(Canvas canvas, Size size) {
    if (history.length < 2) return;

    const minMood = 1.0;
    const maxMood = 5.0;
    final n = history.length;
    final stepX = size.width / (n - 1);

    double moodToY(double m) =>
        size.height - ((m - minMood) / (maxMood - minMood)) * size.height;

    // Gradient fill under line
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [kCrystal400.withAlpha(80), kCrystal400.withAlpha(0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final fillPath = Path();
    fillPath.moveTo(0, size.height);
    for (var i = 0; i < n; i++) {
      fillPath.lineTo(i * stepX, moodToY(history[i].mood));
    }
    fillPath.lineTo((n - 1) * stepX, size.height);
    fillPath.close();
    canvas.drawPath(fillPath, fillPaint);

    // Line
    final linePaint = Paint()
      ..color = kCrystal400
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final linePath = Path();
    for (var i = 0; i < n; i++) {
      final x = i * stepX;
      final y = moodToY(history[i].mood);
      i == 0 ? linePath.moveTo(x, y) : linePath.lineTo(x, y);
    }
    canvas.drawPath(linePath, linePaint);

    // Dots
    final dotPaint = Paint()..color = kCrystal500;
    final dotBg = Paint()..color = Colors.white;
    for (var i = 0; i < n; i++) {
      final x = i * stepX;
      final y = moodToY(history[i].mood);
      canvas.drawCircle(Offset(x, y), 5, dotBg);
      canvas.drawCircle(Offset(x, y), 3.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_MoodSparklinePainter old) => old.history != history;
}
