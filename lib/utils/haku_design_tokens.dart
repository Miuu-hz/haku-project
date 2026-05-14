import 'dart:ui';

import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════
// 🎨 Haku Crystal — Design Tokens
// Matched to .claude/Haku Design System/colors_and_type.css
// ═══════════════════════════════════════════════════════════════

// ---------- Field (aurora pearl gradient) ----------
const kFieldTop = Color(0xFFF3FAFF);
const kFieldMid = Color(0xFFE6EFFF);
const kFieldBot = Color(0xFFF3E6FF);

// ---------- Aurora orbs (vivid, low opacity) ----------
const kOrbCyan = Color(0xD950D7FF); // rgba(80,215,255,0.85)
const kOrbLavender = Color(0xCCC39BFF); // rgba(195,155,255,0.80)
const kOrbMagenta = Color(0xB3FF8CD7); // rgba(255,140,215,0.70)
const kOrbLime = Color(0x73A8FF82); // rgba(168,255,130,0.45)

// ---------- Foreground text ----------
const kFg1 = Color(0xFF050A1E); // primary text on light glass
const kFg2 = Color(0xFF1F2A55); // secondary
const kFg3 = Color(0xFF44528A); // tertiary / hint
const kFg4 = Color(0xFF8A93B5); // disabled / divider-on-glass
const kFgOnCyan = Color(0xFF04141A);

// ---------- Crystal primary ----------
const kCrystal50 = Color(0xFFE6FBFF);
const kCrystal100 = Color(0xFFC4F4FF);
const kCrystal200 = Color(0xFF93ECFF);
const kCrystal300 = Color(0xFF5FE2FF);
const kCrystal400 = Color(0xFF3CDFFF); // CORE primary
const kCrystal500 = Color(0xFF1FC4E8);
const kCrystal600 = Color(0xFF0EA1C4);
const kCrystal700 = Color(0xFF0C7E9B);
const kCrystal900 = Color(0xFF0A1F4D); // navy outline of the cube

// ---------- Lavender (Haku heritage) ----------
const kLavender300 = Color(0xFFC8B3DF);
const kLavender400 = Color(0xFFB69BD2);
const kLavender500 = Color(0xFF9B7CB6); // secondary
const kLavender600 = Color(0xFF7E5D9B);
const kLavender700 = Color(0xFF6B4E71);

// ---------- Vivid accents (Now-Brief categories) ----------
const kVividLime = Color(0xFFA8FF60);
const kVividMagenta = Color(0xFFFF6BD0);
const kVividGold = Color(0xFFFFD66B);
const kVividCoral = Color(0xFFFF8C66);
const kVividMint = Color(0xFF5FFFC7);

// ---------- Semantic ----------
const kOk = Color(0xFF5FFFC7);
const kWarn = Color(0xFFFFD66B);
const kErr = Color(0xFFFF6B8A);
const kInfo = kCrystal400;

// ---------- Glass surface ----------
const kGlassFill = Color(0xB8FFFFFF); // rgba(255,255,255,0.72)
const kGlassFillStrong = Color(0xE0FFFFFF); // rgba(255,255,255,0.88)
const kGlassFillSoft = Color(0x8CFFFFFF); // rgba(255,255,255,0.55)
const kGlassEdge = Color(0xA6FFFFFF); // rgba(255,255,255,0.65)
const kGlassStroke = Color(0x14505A8C); // rgba(80,90,140,0.08)

// ---------- Field deep (for dark accents) ----------
const kField0 = Color(0xFF050817);
const kField1 = Color(0xFF070B1A);
const kField2 = Color(0xFF0E1638);
const kField3 = Color(0xFF141F4A);

// ═══════════════════════════════════════════════════════════════
// Typography helpers (Inter + Noto Sans Thai via Google Fonts in main.dart)
// ═══════════════════════════════════════════════════════════════

const TextStyle kDisplay = TextStyle(
  fontSize: 56,
  fontWeight: FontWeight.w700,
  height: 1.05,
  letterSpacing: -0.02,
  color: kFg1,
);

const TextStyle kH1 = TextStyle(
  fontSize: 36,
  fontWeight: FontWeight.w700,
  height: 1.1,
  color: kFg1,
);

const TextStyle kH2 = TextStyle(
  fontSize: 28,
  fontWeight: FontWeight.w600,
  height: 1.2,
  color: kFg1,
);

const TextStyle kH3 = TextStyle(
  fontSize: 22,
  fontWeight: FontWeight.w600,
  height: 1.25,
  color: kFg1,
);

const TextStyle kH4 = TextStyle(
  fontSize: 18,
  fontWeight: FontWeight.w600,
  height: 1.3,
  color: kFg1,
);

const TextStyle kBody = TextStyle(
  fontSize: 15,
  fontWeight: FontWeight.w400,
  height: 1.5,
  color: kFg1,
);

const TextStyle kBodyMd = TextStyle(
  fontSize: 15,
  fontWeight: FontWeight.w500,
  height: 1.5,
  color: kFg1,
);

const TextStyle kLabel = TextStyle(
  fontSize: 13,
  fontWeight: FontWeight.w500,
  height: 1.3,
  color: kFg1,
);

const TextStyle kCaption = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w500,
  height: 1.35,
  color: kFg3,
);

const TextStyle kEyebrow = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w600,
  height: 1.0,
  letterSpacing: 1.8,
  color: kFg3,
);

const TextStyle kNumeral = TextStyle(
  fontSize: 64,
  fontWeight: FontWeight.w700,
  height: 1.0,
  color: kFg1,
);

// ═══════════════════════════════════════════════════════════════
// Radii
// ═══════════════════════════════════════════════════════════════

const double kR1 = 6;
const double kR2 = 10;
const double kR3 = 16;
const double kR4 = 22;
const double kR5 = 28;
const double kR6 = 36;
const double kRPill = 999;

// ═══════════════════════════════════════════════════════════════
// Shadows / Glows
// ═══════════════════════════════════════════════════════════════

const List<BoxShadow> kShadowGlass1 = [
  BoxShadow(
    color: Color(0xD9FFFFFF),
    blurRadius: 0,
    offset: Offset(0, 1),
  ),
  BoxShadow(
    color: Color(0x14505A8C),
    blurRadius: 0,
    spreadRadius: 1,
  ),
  BoxShadow(
    color: Color(0x40283C82),
    blurRadius: 28,
    offset: Offset(0, 10),
  ),
];

const List<BoxShadow> kShadowGlass2 = [
  BoxShadow(
    color: Color(0xF2FFFFFF),
    blurRadius: 0,
    offset: Offset(0, 1),
  ),
  BoxShadow(
    color: Color(0x1A505A8C),
    blurRadius: 0,
    spreadRadius: 1,
  ),
  BoxShadow(
    color: Color(0x4D283C82),
    blurRadius: 40,
    offset: Offset(0, 18),
  ),
];

const List<BoxShadow> kGlowCyan = [
  BoxShadow(
    color: Color(0x593CDFFF),
    blurRadius: 0,
    spreadRadius: 1,
  ),
  BoxShadow(
    color: Color(0x733CDFFF),
    blurRadius: 24,
  ),
  BoxShadow(
    color: Color(0x403CDFFF),
    blurRadius: 64,
  ),
];

const List<BoxShadow> kGlowLavender = [
  BoxShadow(
    color: Color(0x59B69BE2),
    blurRadius: 0,
    spreadRadius: 1,
  ),
  BoxShadow(
    color: Color(0x73B69BE2),
    blurRadius: 24,
  ),
  BoxShadow(
    color: Color(0x409B7CB6),
    blurRadius: 64,
  ),
];

// ═══════════════════════════════════════════════════════════════
// Gradients
// ═══════════════════════════════════════════════════════════════

const LinearGradient kFieldGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [kFieldTop, kFieldMid, kFieldBot],
  stops: [0.0, 0.45, 1.0],
);

// ═══════════════════════════════════════════════════════════════
// Reusable Glass Card
// ═══════════════════════════════════════════════════════════════

class HakuGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final List<BoxShadow>? shadow;
  final Color? fillColor;
  const HakuGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = kR4,
    this.shadow,
    this.fillColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadow ?? kShadowGlass1,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: fillColor ?? kGlassFill,
              borderRadius: BorderRadius.circular(radius),
              border: const Border(
                top: BorderSide(color: kGlassEdge, width: 1),
                left: BorderSide(color: kGlassStroke, width: 0.5),
                right: BorderSide(color: kGlassStroke, width: 0.5),
                bottom: BorderSide(color: kGlassStroke, width: 0.5),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Aurora Background (fills screen with gradient + animated orbs)
// ═══════════════════════════════════════════════════════════════

class HakuAuroraBackground extends StatelessWidget {
  final List<Widget> children;
  final bool showOrbs;
  const HakuAuroraBackground({
    super.key,
    this.children = const [],
    this.showOrbs = true,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Base gradient
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(gradient: kFieldGradient),
          ),
        ),
        // Orbs (4 total: cyan, lavender, magenta, lime)
        if (showOrbs)
          Positioned.fill(
            child: LayoutBuilder(
              builder: (_, constraints) {
                final w = constraints.maxWidth;
                final h = constraints.maxHeight;
                return Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Positioned(
                      top: -h * 0.10,
                      left: -w * 0.10,
                      child: const _AuroraOrb(color: kOrbCyan, size: 360),
                    ),
                    Positioned(
                      top: h * 0.20,
                      right: -w * 0.20,
                      child: const _AuroraOrb(color: kOrbLavender, size: 380),
                    ),
                    Positioned(
                      top: h * 0.36,
                      right: -w * 0.20,
                      child: const _AuroraOrb(color: kOrbMagenta, size: 260),
                    ),
                    Positioned(
                      bottom: -h * 0.10,
                      left: -w * 0.15,
                      child: const _AuroraOrb(color: kOrbLime, size: 220),
                    ),
                  ],
                );
              },
            ),
          ),
        ...children,
      ],
    );
  }
}

class _AuroraOrb extends StatelessWidget {
  final Color color;
  final double size;
  const _AuroraOrb({required this.color, required this.size});

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

// ═══════════════════════════════════════════════════════════════
// Glass AppBar
// ═══════════════════════════════════════════════════════════════

class HakuGlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool centerTitle;
  const HakuGlassAppBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.centerTitle = true,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return PreferredSize(
      preferredSize: preferredSize,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: AppBar(
            backgroundColor: kGlassFill,
            elevation: 0,
            shadowColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            centerTitle: centerTitle,
            title: title,
            actions: actions,
            leading: leading,
            iconTheme: const IconThemeData(color: kFg1),
            actionsIconTheme: const IconThemeData(color: kFg1),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Floating Glass Nav Pill
// ═══════════════════════════════════════════════════════════════

class HakuGlassNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  // destinations param kept for API compat but not used — labels are hardcoded
  final List<NavigationDestination> destinations;
  const HakuGlassNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.destinations,
  });

  static const _tabs = [
    (icon: Icons.book_outlined, activeIcon: Icons.book_rounded, label: 'บันทึก'),
    (icon: Icons.chat_bubble_outline, activeIcon: Icons.chat_bubble_rounded, label: 'Haku AI'),
    (icon: Icons.settings_outlined, activeIcon: Icons.settings_rounded, label: 'ตั้งค่า'),
  ];

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(kRPill),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: kGlassFillStrong,
            borderRadius: BorderRadius.circular(kRPill),
            boxShadow: kShadowGlass2,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < _tabs.length; i++)
                _NavPillTab(
                  icon: _tabs[i].icon,
                  activeIcon: _tabs[i].activeIcon,
                  label: _tabs[i].label,
                  isActive: currentIndex == i,
                  onTap: () => onTap(i),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavPillTab extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  const _NavPillTab({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: isActive
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF7BEBFF), kCrystal400],
                )
              : null,
          borderRadius: BorderRadius.circular(kRPill),
          boxShadow: isActive ? kGlowCyan : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              size: 20,
              color: isActive ? kFgOnCyan : kFg3,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: kLabel.copyWith(
                color: isActive ? kFgOnCyan : kFg3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Crystal Core — breathing animated orb
// ═══════════════════════════════════════════════════════════════

class HakuCrystalCore extends StatefulWidget {
  final double size;
  const HakuCrystalCore({super.key, this.size = 96});

  @override
  State<HakuCrystalCore> createState() => _HakuCrystalCoreState();
}

class _HakuCrystalCoreState extends State<HakuCrystalCore>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 1600),
      vsync: this,
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.94, end: 1.08).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    _opacity = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Opacity(
        opacity: _opacity.value,
        child: Transform.scale(
          scale: _scale.value,
          child: _CoreSphere(size: widget.size),
        ),
      ),
    );
  }
}

class _CoreSphere extends StatelessWidget {
  final double size;
  const _CoreSphere({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: Alignment(-0.3, -0.4),
          colors: [
            Colors.white,
            kCrystal200,
            kCrystal400,
            kCrystal700,
            kCrystal900,
          ],
          stops: [0.0, 0.18, 0.45, 0.80, 1.0],
        ),
        boxShadow: kGlowCyan,
      ),
      child: ClipOval(
        child: Stack(
          children: [
            // Inner highlight (lens flare)
            Positioned(
              top: size * 0.06,
              left: size * 0.10,
              child: Container(
                width: size * 0.55,
                height: size * 0.45,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.white.withAlpha(178),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
