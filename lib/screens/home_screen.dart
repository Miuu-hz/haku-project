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
import 'chat_screen.dart';
import 'settings_screen.dart';
import 'view_entry_screen.dart';

// ══════════════════════════════════════════════════════════════
// 🎨 Color Palette — matched to HTML CSS vars exactly
// ══════════════════════════════════════════════════════════════

const _kBg          = Color(0xFFF8F9FA);
const _kTextMain    = Color(0xFF1C1C1E);
const _kTextSub     = Color(0xFF6E6E73);
const _kAccentBlue  = Color(0xFF007AFF);
const _kAccentOrange = Color(0xFFFF9500);
const _kAccentGreen = Color(0xFF34C759);
const _kAccentVivid = Color(0xFFFF2D55);
const _kGlassBg     = Color(0xA6FFFFFF); // rgba(255,255,255,0.65)
const _kGlassBorder = Color(0xCCFFFFFF); // rgba(255,255,255,0.8)

// ══════════════════════════════════════════════════════════════
// Provider
// ══════════════════════════════════════════════════════════════

final entriesProvider = FutureProvider<List<Entry>>(
  (ref) => DatabaseHelper.instance.getAllEntries(limit: 50),
);

// ══════════════════════════════════════════════════════════════
// ⏰ Time Period
// ══════════════════════════════════════════════════════════════

enum _Period { morning, midday, evening, night }

_Period _periodOf(int hour) {
  if (hour >= 5 && hour < 12) return _Period.morning;
  if (hour >= 12 && hour < 17) return _Period.midday;
  if (hour >= 17 && hour < 22) return _Period.evening;
  return _Period.night;
}

String _periodGreeting(_Period p) {
  switch (p) {
    case _Period.morning: return 'อรุณสวัสดิ์ค่ะ! ☀️';
    case _Period.midday:  return 'สวัสดีตอนเที่ยงค่ะ 🌤️';
    case _Period.evening: return 'สวัสดีตอนเย็นค่ะ 🌇';
    case _Period.night:   return 'ราตรีสวัสดิ์ค่ะ 🌙';
  }
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

  // 🌊 Blob animation (CSS: 10s alternate ease-in-out, translate+scale)
  late final AnimationController _blobCtrl;
  late final Animation<double> _blob1X, _blob1Y, _blob1S;
  late final Animation<double> _blob2X, _blob2Y, _blob2S;
  late final Animation<double> _blob3X, _blob3Y, _blob3S;

  // ✨ Card intro (CSS: slideUpFade 0.6s + staggered delays)
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

  @override
  void initState() {
    super.initState();

    // CSS: float 10s infinite alternate ease-in-out
    // translate(30px, 50px) scale(1.1)
    _blobCtrl = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    )..repeat(reverse: true);

    // Blob 1 (no delay)
    _blob1X = Tween<double>(begin: 0, end: 30).animate(
        CurvedAnimation(parent: _blobCtrl, curve: Curves.easeInOut));
    _blob1Y = Tween<double>(begin: 0, end: 50).animate(
        CurvedAnimation(parent: _blobCtrl, curve: Curves.easeInOut));
    _blob1S = Tween<double>(begin: 1.0, end: 1.1).animate(
        CurvedAnimation(parent: _blobCtrl, curve: Curves.easeInOut));

    // Blob 2 (animation-delay: -2s → starts at 20% offset)
    _blob2X = Tween<double>(begin: 0, end: 30).animate(
        CurvedAnimation(parent: _blobCtrl,
            curve: const Interval(0.2, 1.0, curve: Curves.easeInOut)));
    _blob2Y = Tween<double>(begin: 0, end: 50).animate(
        CurvedAnimation(parent: _blobCtrl,
            curve: const Interval(0.2, 1.0, curve: Curves.easeInOut)));
    _blob2S = Tween<double>(begin: 1.0, end: 1.1).animate(
        CurvedAnimation(parent: _blobCtrl,
            curve: const Interval(0.2, 1.0, curve: Curves.easeInOut)));

    // Blob 3 (animation-delay: -4s → starts at 40% offset)
    _blob3X = Tween<double>(begin: 0, end: 30).animate(
        CurvedAnimation(parent: _blobCtrl,
            curve: const Interval(0.4, 1.0, curve: Curves.easeInOut)));
    _blob3Y = Tween<double>(begin: 0, end: 50).animate(
        CurvedAnimation(parent: _blobCtrl,
            curve: const Interval(0.4, 1.0, curve: Curves.easeInOut)));
    _blob3S = Tween<double>(begin: 1.0, end: 1.1).animate(
        CurvedAnimation(parent: _blobCtrl,
            curve: const Interval(0.4, 1.0, curve: Curves.easeInOut)));

    // Intro staggered
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
    ]);
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
    final now    = DateTime.now();
    final period = _periodOf(now.hour);
    final dateStr = DateFormat('EEEEที่ d MMM', 'th').format(now);

    return Stack(
      children: [
        // ① Blob background (fills entire screen behind everything)
        Positioned.fill(
          child: _BlobBackground(
            ctrl: _blobCtrl,
            b1x: _blob1X, b1y: _blob1Y, b1s: _blob1S,
            b2x: _blob2X, b2y: _blob2Y, b2s: _blob2S,
            b3x: _blob3X, b3y: _blob3Y, b3s: _blob3S,
          ),
        ),

        // ② Main scaffold — transparent so blobs show through glass cards
        Scaffold(
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: true,
          appBar: _buildGlassAppBar(dateStr),
          body: RefreshIndicator(
            onRefresh: _refreshData,
            color: _kAccentBlue,
            backgroundColor: Colors.white,
            child: CustomScrollView(
              slivers: [
                // Safe area gap below AppBar
                const SliverToBoxAdapter(
                  child: SizedBox(height: kToolbarHeight + 20),
                ),

                // ─── Dashboard cards ───
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        _Intro(
                          anim: _headerAnim,
                          child: _HeaderSection(
                            period: period,
                            dateStr: dateStr,
                            eventCount: _todayEvents.length,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Card 1: Weather
                        if (_weather != null) ...[
                          _Intro(
                            anim: _card1Anim,
                            child: _WeatherCard(weather: _weather!),
                          ),
                          const SizedBox(height: 20),
                        ],

                        // Card 2: Calendar
                        if (_todayEvents.isNotEmpty) ...[
                          _Intro(
                            anim: _card2Anim,
                            child: _CalendarCard(events: _todayEvents),
                          ),
                          const SizedBox(height: 20),
                        ],

                        // Card 3: Goals
                        if (_activeObjectives.isNotEmpty) ...[
                          _Intro(
                            anim: _card3Anim,
                            child: _GoalsCard(objectives: _activeObjectives),
                          ),
                          const SizedBox(height: 20),
                        ],

                        // Streak badge (small pill below goals)
                        if (_streak > 0) ...[
                          _Intro(
                            anim: _card3Anim,
                            child: _StreakBadge(streak: _streak),
                          ),
                          const SizedBox(height: 20),
                        ],

                        // Card 4: Social Battery
                        if (_socialBattery != null) ...[
                          _Intro(
                            anim: _card3Anim,
                            child: _SocialBatteryCard(result: _socialBattery!),
                          ),
                          const SizedBox(height: 20),
                        ],

                        // Card 5: Hidden Correlation insight
                        if (_topInsight != null) ...[
                          _Intro(
                            anim: _card3Anim,
                            child: _InsightCard(insight: _topInsight!),
                          ),
                          const SizedBox(height: 20),
                        ],

                        // Journal section divider
                        _buildDivider(),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),

                // ─── Journal entries ───
                entriesAsync.when(
                  data: (entries) {
                    if (entries.isEmpty) {
                      return SliverToBoxAdapter(child: _buildEmptyState());
                    }
                    return SliverPadding(
                      // 120px bottom padding: clears the floating pill
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
                        child: CircularProgressIndicator(color: _kAccentBlue),
                      ),
                    ),
                  ),
                  error: (e, _) => SliverToBoxAdapter(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('เกิดข้อผิดพลาด: $e',
                            style: const TextStyle(color: _kTextSub)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ③ Floating bottom action pill (on top, z-order above Scaffold)
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
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: AppBar(
              backgroundColor: Colors.white.withValues(alpha:0.5),
              elevation: 0,
              shadowColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              title: Text(
                dateStr,
                style: const TextStyle(
                  color: _kTextMain,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.settings_outlined, color: _kTextMain),
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
          const Text('📖', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 8),
          const Text(
            'บันทึก',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _kTextSub,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Divider(
              color: Colors.black.withValues(alpha:0.1),
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
                size: 56, color: _kTextSub.withValues(alpha:0.4)),
            const SizedBox(height: 12),
            const Text('ยังไม่มีบันทึก',
                style: TextStyle(
                    fontSize: 17,
                    color: _kTextSub,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            const Text('แตะ "เริ่มบันทึก" เพื่อบันทึกชีวิตของคุณ',
                style: TextStyle(fontSize: 13, color: _kTextSub),
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
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
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
            builder: (_, __) => ColoredBox(
              color: _kBg,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  // Blob 1: soft pink — top:-10% left:-10% w:300 h:300
                  Positioned(
                    top: -h * 0.10 + b1y.value,
                    left: -w * 0.10 + b1x.value,
                    child: Transform.scale(
                      scale: b1s.value,
                      child: const _Blob(color: Color(0x99FFB6C1), size: 300),
                    ),
                  ),
                  // Blob 2: vivid sky blue — top:20% right:-20% w:400 h:400
                  Positioned(
                    top: h * 0.20 + b2y.value,
                    right: -w * 0.20 + b2x.value,
                    child: Transform.scale(
                      scale: b2s.value,
                      child: const _Blob(color: Color(0x9987CEFA), size: 400),
                    ),
                  ),
                  // Blob 3: light cyan — bottom:-10% left:20% w:350 h:350
                  Positioned(
                    bottom: -h * 0.10 + b3y.value,
                    left: w * 0.20 + b3x.value,
                    child: Transform.scale(
                      scale: b3s.value,
                      child: const _Blob(color: Color(0x99E0FFFF), size: 350),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
}

/// Blurred circle — CSS: border-radius:50%; filter:blur(60px); opacity:0.6
class _Blob extends StatelessWidget {
  final Color color;
  final double size;
  const _Blob({required this.color, required this.size});

  @override
  Widget build(BuildContext context) => ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
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
// 🪟 Glass Card — backdrop blur + semi-transparent white
// ══════════════════════════════════════════════════════════════

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha:0.04),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: Colors.white.withValues(alpha:0.8),
              blurRadius: 0,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _kGlassBg,
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: _kGlassBorder),
              ),
              child: child,
            ),
          ),
        ),
      );
}

// ══════════════════════════════════════════════════════════════
// 📋 Header Section
// ══════════════════════════════════════════════════════════════

class _HeaderSection extends StatelessWidget {
  final _Period period;
  final String dateStr;
  final int eventCount;

  const _HeaderSection({
    required this.period,
    required this.dateStr,
    required this.eventCount,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date chip — glass pill with blur
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha:0.5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _kGlassBorder),
                ),
                child: Text(
                  dateStr,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _kAccentBlue,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Greeting (34px bold — matches HTML .greeting)
          Text(
            _periodGreeting(period),
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w700,
              color: _kTextMain,
              height: 1.1,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),

          // Insight with gradient highlight text
          RichText(
            text: TextSpan(
              style: const TextStyle(
                fontSize: 16,
                color: _kTextSub,
                height: 1.4,
              ),
              children: [
                const TextSpan(text: 'Haku ประมวลผล '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [_kAccentVivid, _kAccentOrange],
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
            // Big temp row (matches HTML .weather-row)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Temperature with small "C" suffix
                      RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: '${weather.maxTemp.round()}°',
                              style: const TextStyle(
                                fontSize: 48,
                                fontWeight: FontWeight.w300,
                                color: _kTextMain,
                                letterSpacing: -2,
                                height: 1,
                              ),
                            ),
                            const TextSpan(
                              text: 'C',
                              style: TextStyle(
                                fontSize: 24,
                                color: Color(0xFF8E8E93),
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
                          color: _kTextSub,
                        ),
                      ),
                    ],
                  ),
                ),
                // Weather icon (56px, matches HTML .weather-icon)
                Text(
                  weather.emoji,
                  style: const TextStyle(fontSize: 56),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Nudge pill — matches HTML .weather-desc
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha:0.5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Text('💡', style: TextStyle(fontSize: 15)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _nudge(weather.maxTemp, weather.description),
                      style: const TextStyle(
                        fontSize: 15,
                        color: _kTextMain,
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
      return 'พกร่มไปด้วยนะคะ วันนี้มีฝนตก ☔';
    }
    if (temp > 35) return 'อากาศร้อนมาก ควรพกน้ำและทาครีมกันแดดค่ะ 🧴';
    if (temp < 22) return 'อากาศเย็นสบาย ใส่เสื้อกันหนาวด้วยก็ดีค่ะ 🧥';
    return 'พกเสื้อคลุมไปด้วยนะคะ ช่วงบ่ายอาจมีฝนตก 🌂';
  }
}

// ══════════════════════════════════════════════════════════════
// 📅 Calendar Card — Agenda style with time column
// ══════════════════════════════════════════════════════════════

class _CalendarCard extends StatelessWidget {
  final List<Map<String, dynamic>> events;
  const _CalendarCard({required this.events});

  static const _colors = [_kAccentBlue, _kAccentOrange, _kAccentGreen];

  @override
  Widget build(BuildContext context) {
    final shown = events.take(3).toList();
    final more = events.length > 3 ? events.length - 3 : 0;

    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card title
          Row(
            children: [
              const Text('📅', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text(
                'ตารางวันนี้ (${events.length})',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: _kTextMain,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Agenda items
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
                  // Time column — 50px (matches HTML .time-col)
                  SizedBox(
                    width: 50,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        timeStr,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _kTextSub,
                        ),
                      ),
                    ),
                  ),

                  // Event card with left color bar
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha:0.8),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.white.withValues(alpha:0.9)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha:0.02),
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
                              // Left color bar (::before pseudo-element)
                              Container(width: 4, color: color),
                              // Content
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
                                          color: _kTextMain,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (loc != null) ...[
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            const Text('📍',
                                                style:
                                                    TextStyle(fontSize: 12)),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                loc,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  color: _kTextSub,
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
                style: const TextStyle(fontSize: 13, color: _kTextSub)),
          ],
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 🎯 Goals Card with circular progress
// ══════════════════════════════════════════════════════════════

class _GoalsCard extends StatelessWidget {
  final List<Objective> objectives;
  const _GoalsCard({required this.objectives});

  @override
  Widget build(BuildContext context) {
    final shown = objectives.take(3).toList();

    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card title
          const Row(
            children: [
              Text('🎯', style: TextStyle(fontSize: 18)),
              SizedBox(width: 8),
              Text(
                'เป้าหมายประจำวัน',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: _kTextMain,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Goal items
          ...shown.asMap().entries.map((e) {
            final i    = e.key;
            final o    = e.value;
            final isLast = i == shown.length - 1;
            final progress = _progressOf(o.status);
            final color    = _colorOf(o.status);
            final icon     = _iconOf(o.status);
            final subLabel = o.dueTime ?? _statusLabel(o.status);

            return Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Row(
                children: [
                  // Icon box — matches HTML .goal-icon (40×40, rounded 14px)
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha:0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(icon, style: const TextStyle(fontSize: 20)),
                  ),
                  const SizedBox(width: 12),

                  // Goal text
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          o.title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _kTextMain,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          subLabel,
                          style: const TextStyle(
                              fontSize: 13, color: _kTextSub),
                        ),
                      ],
                    ),
                  ),

                  // Circular progress (CSS: conic-gradient + inner white circle)
                  _ProgressCircle(value: progress, color: color),
                ],
              ),
            );
          }),

          if (objectives.length > 3) ...[
            const SizedBox(height: 12),
            Text('+${objectives.length - 3} อื่นๆ',
                style: const TextStyle(fontSize: 13, color: _kTextSub)),
          ],
        ],
      ),
    );
  }

  static double _progressOf(ObjectiveStatus s) {
    switch (s) {
      case ObjectiveStatus.inProgress: return 0.5;
      case ObjectiveStatus.overdue:    return 0.3;
      case ObjectiveStatus.pending:    return 0.0;
      default:                          return 1.0;
    }
  }

  static Color _colorOf(ObjectiveStatus s) {
    switch (s) {
      case ObjectiveStatus.inProgress: return _kAccentBlue;
      case ObjectiveStatus.overdue:    return _kAccentVivid;
      default:                          return _kAccentGreen;
    }
  }

  static String _iconOf(ObjectiveStatus s) {
    switch (s) {
      case ObjectiveStatus.inProgress: return '🔵';
      case ObjectiveStatus.overdue:    return '⚠️';
      case ObjectiveStatus.pending:    return '⚪';
      default:                          return '✅';
    }
  }

  static String _statusLabel(ObjectiveStatus s) {
    switch (s) {
      case ObjectiveStatus.inProgress: return 'กำลังดำเนินการ';
      case ObjectiveStatus.overdue:    return 'เกินกำหนดแล้ว';
      case ObjectiveStatus.pending:    return 'ยังไม่ได้เริ่มเลย';
      default:                          return 'เสร็จแล้ว';
    }
  }
}

// ── Circular progress — CSS conic-gradient equivalent ─────────

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
            // White inner circle (like CSS .progress-inner)
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
// 🍅 Focus Streak badge (small pill below goals)
// ══════════════════════════════════════════════════════════════

class _StreakBadge extends StatelessWidget {
  final int streak;
  const _StreakBadge({required this.streak});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha:0.65),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _kGlassBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🍅', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                const Text('Focus Streak',
                    style: TextStyle(fontSize: 13, color: _kTextSub)),
                const SizedBox(width: 8),
                Text(
                  '$streak วัน 🔥',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _kAccentOrange,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

// ══════════════════════════════════════════════════════════════
// ⬇️ Floating Bottom Action Pill — matches HTML .bottom-action
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
                color: Colors.black.withValues(alpha:0.2),
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
                  color: Colors.black.withValues(alpha:0.85),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  children: [
                    const Text('✨',
                        style: TextStyle(
                            fontSize: 18, color: Color(0xFFFFD60A))),
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
                    // White "เริ่มบันทึก" button
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: const Text(
                        'เริ่มบันทึก',
                        style: TextStyle(
                          color: Colors.black,
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
// 🗒️ Journal Entry Card (light theme)
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
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.04),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date + mood row
              Row(
                children: [
                  Text(
                    dateFormat.format(entry.createdAt),
                    style: const TextStyle(fontSize: 12, color: _kTextSub),
                  ),
                  const Spacer(),
                  if (entry.mediaType != MediaType.none) ...[
                    Icon(
                      entry.mediaType == MediaType.image
                          ? Icons.image_outlined
                          : Icons.mic_outlined,
                      size: 15,
                      color: _kTextSub,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(moodInfo['emoji'] as String,
                      style: const TextStyle(fontSize: 16)),
                ],
              ),
              const SizedBox(height: 10),

              // Content
              Text(
                entry.content,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: _kTextMain,
                ),
              ),

              // Location
              if (entry.locationName != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined,
                        size: 13, color: _kTextSub),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        entry.locationName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(fontSize: 12, color: _kTextSub),
                      ),
                    ),
                  ],
                ),
              ],

              // Tags
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
                            color: _kAccentBlue.withValues(alpha:0.08),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '#$tag',
                            style: const TextStyle(
                                fontSize: 12, color: _kAccentBlue),
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
    );
  }
}

// ══════════════════════════════════════════════════════════════
// ⚡ Social Battery Card (3.2)
// ══════════════════════════════════════════════════════════════

class _SocialBatteryCard extends StatelessWidget {
  final SocialBatteryResult result;
  const _SocialBatteryCard({required this.result});

  static const _trendIcon = {
    BatteryTrend.draining:   '↓',
    BatteryTrend.stable:     '→',
    BatteryTrend.recharging: '↑',
  };

  static const _trendColor = {
    BatteryTrend.draining:   _kAccentVivid,
    BatteryTrend.stable:     _kAccentOrange,
    BatteryTrend.recharging: _kAccentGreen,
  };

  @override
  Widget build(BuildContext context) {
    final pct   = result.level / 100.0;
    final color = pct >= 0.6
        ? _kAccentGreen
        : pct >= 0.35
            ? _kAccentOrange
            : _kAccentVivid;
    final trendColor = _trendColor[result.trend]!;
    final trendIcon  = _trendIcon[result.trend]!;

    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
          Row(
            children: [
              const Text('⚡', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'พลังงานสังคม',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: _kTextMain,
                  ),
                ),
              ),
              // Trend badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: trendColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$trendIcon ${result.level}%',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: trendColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Progress bar
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

          // Message
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Text('💡', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    result.message,
                    style: const TextStyle(
                      fontSize: 14,
                      color: _kTextMain,
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
// 🔍 Hidden Correlation Insight Card (3.1)
// ══════════════════════════════════════════════════════════════

class _InsightCard extends StatelessWidget {
  final CorrelationInsight insight;
  const _InsightCard({required this.insight});

  @override
  Widget build(BuildContext context) {
    final accent = insight.isPositive ? _kAccentGreen : _kAccentOrange;
    final pct    = (insight.confidence * 100).round();

    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
          Row(
            children: [
              const Text('🔍', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              const Text(
                'ค้นพบ Pattern',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: _kTextMain,
                ),
              ),
              const Spacer(),
              // Confidence chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
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

          // Insight message
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accent.withValues(alpha: 0.2)),
            ),
            child: Text(
              insight.message,
              style: const TextStyle(
                fontSize: 15,
                color: _kTextMain,
                height: 1.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Sample size note
          Text(
            'จาก ${insight.sampleSize} บันทึก · ${insight.hitCount} ครั้งที่ตรงกัน',
            style: const TextStyle(fontSize: 12, color: _kTextSub),
          ),
        ],
      ),
    );
  }
}
