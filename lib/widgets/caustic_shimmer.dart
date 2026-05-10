import 'package:flutter/material.dart';

/// ✨ Caustic Shimmer — แสงหักเหเลื่อนบนกระจก
///
/// จำลอง CSS `haku-shimmer` animation จาก Haku Crystal Design System:
/// - 4s loop, ease-in-out
/// - gradient strip เอียง ~15° เลื่อนจากขวาไปซ้าย
/// - opacity ต่ำมาก (~6–10%) เพื่อให้ดู subtle บน glass
class CausticShimmer extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final BorderRadius? borderRadius;

  const CausticShimmer({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 4000),
    this.borderRadius,
  });

  @override
  State<CausticShimmer> createState() => _CausticShimmerState();
}

class _CausticShimmerState extends State<CausticShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    )..repeat();
    // CSS: 0% → 60% เคลื่อนไหว, 60% → 100% ค้างไว้
    _animation = Tween<double>(begin: -1.2, end: 1.2).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeInOut),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: widget.borderRadius ?? BorderRadius.zero,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _animation,
                builder: (context, child) {
                  return CustomPaint(
                    painter: _CausticShimmerPainter(_animation.value),
                    size: Size.infinite,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CausticShimmerPainter extends CustomPainter {
  final double progress;

  _CausticShimmerPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    // ความกว้างของแถบ shimmer = 70% ของความกว้าง card
    final stripW = size.width * 0.7;
    final travel = size.width + stripW;
    final startX = -stripW + (progress + 1) * 0.5 * travel;

    // Rect ที่เอียงเล็กน้อย (จำลอง 105deg ของ CSS)
    final rect = Rect.fromLTWH(
      startX,
      -size.height * 0.5,
      stripW,
      size.height * 2,
    );

    final shader = const LinearGradient(
      begin: Alignment(-1.0, -0.25),
      end: Alignment(1.0, 0.25),
      colors: [
        Colors.transparent,
        Color(0x0DFFFFFF), // ~5% white
        Color(0x1AFFFFFF), // ~10% white
        Color(0x0DFFFFFF),
        Colors.transparent,
      ],
      stops: [0.0, 0.42, 0.50, 0.58, 1.0],
    ).createShader(rect);

    final paint = Paint()
      ..shader = shader
      ..blendMode = BlendMode.plus; // ให้แสงสะท้อนบน glass

    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _CausticShimmerPainter old) =>
      old.progress != progress;
}
