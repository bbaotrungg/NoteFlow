import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 1. RetentionCurvePainter: Vẽ đường cong ghi nhớ kiến thức Ebbinghaus R(t) = e^(-t/S)
/// theo thời gian thực dựa trên hệ số dễ trung bình (Ease Factor) và số lần lặp SM-2.
/// Cam kết 100% vẽ trực tiếp trên Canvas bằng CustomPainter ở tốc độ 60 FPS.
class RetentionCurveChart extends StatefulWidget {
  final double averageEaseFactor;
  final double averageIntervalDays;
  final int averageRepetitionCount;

  const RetentionCurveChart({
    super.key,
    required this.averageEaseFactor,
    required this.averageIntervalDays,
    required this.averageRepetitionCount,
  });

  @override
  State<RetentionCurveChart> createState() => _RetentionCurveChartState();
}

class _RetentionCurveChartState extends State<RetentionCurveChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progressAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _progressAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant RetentionCurveChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.averageEaseFactor != widget.averageEaseFactor ||
        oldWidget.averageIntervalDays != widget.averageIntervalDays) {
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedBuilder(
      animation: _progressAnimation,
      builder: (context, _) {
        return CustomPaint(
          size: const Size(double.infinity, 210),
          painter: RetentionCurvePainter(
            progress: _progressAnimation.value,
            averageEaseFactor: widget.averageEaseFactor,
            averageIntervalDays: widget.averageIntervalDays,
            averageRepetitionCount: widget.averageRepetitionCount,
            isDark: isDark,
          ),
        );
      },
    );
  }
}

class RetentionCurvePainter extends CustomPainter {
  final double progress;
  final double averageEaseFactor;
  final double averageIntervalDays;
  final int averageRepetitionCount;
  final bool isDark;

  RetentionCurvePainter({
    required this.progress,
    required this.averageEaseFactor,
    required this.averageIntervalDays,
    required this.averageRepetitionCount,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const double leftPad = 42.0;
    const double rightPad = 18.0;
    const double topPad = 20.0;
    const double bottomPad = 32.0;

    final double chartWidth = size.width - leftPad - rightPad;
    final double chartHeight = size.height - topPad - bottomPad;
    if (chartWidth <= 0 || chartHeight <= 0) return;

    final Color gridColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final Color labelColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    const Color primaryLineColor = Color(0xFF0284C7);
    const Color baselineDecayColor = Color(0xFFF43F5E);

    final Paint gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1.0;

    // 1. Vẽ lưới ngang (100%, 75%, 50%, 25%) và nhãn trục tung
    final yLevels = [1.0, 0.75, 0.50, 0.25];
    for (final level in yLevels) {
      final y = topPad + chartHeight * (1.0 - level);
      canvas.drawLine(Offset(leftPad, y), Offset(leftPad + chartWidth, y), gridPaint);

      final tp = TextPainter(
        text: TextSpan(
          text: '${(level * 100).toInt()}%',
          style: TextStyle(color: labelColor, fontSize: 11, fontWeight: FontWeight.w500),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(leftPad - tp.width - 8, y - tp.height / 2));
    }

    // 2. Vẽ nhãn trục hoành (Ngày 0 -> Ngày 14)
    final dayMarks = [0, 2, 4, 7, 10, 14];
    for (final day in dayMarks) {
      final x = leftPad + (day / 14.0) * chartWidth;
      final tp = TextPainter(
        text: TextSpan(
          text: 'N$day',
          style: TextStyle(color: labelColor, fontSize: 11, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, topPad + chartHeight + 8));
    }

    // 3. Tính toán độ bền trí nhớ S (Memory Stability)
    final double effectiveInterval = math.max(1.5, averageIntervalDays);
    final double sm2Stability =
        (effectiveInterval * (averageEaseFactor / 2.2) * (1.0 + averageRepetitionCount * 0.35)) /
            0.12;
    const double unreviewedStability = 3.2; // Quên nhanh nếu không áp dụng SM-2

    // 4. Vẽ đường cong suy giảm tự nhiên nếu KHÔNG ôn tập SM-2 (Nét đứt màu hồng đỏ)
    final Path unreviewedPath = Path();
    const int steps = 60;
    final int activeSteps = (steps * progress).round().clamp(1, steps);

    for (int i = 0; i <= activeSteps; i++) {
      final double tDays = (i / steps) * 14.0;
      final double retention = math.exp(-tDays / unreviewedStability).clamp(0.1, 1.0);
      final double x = leftPad + (tDays / 14.0) * chartWidth;
      final double y = topPad + chartHeight * (1.0 - retention);
      if (i == 0) {
        unreviewedPath.moveTo(x, y);
      } else {
        unreviewedPath.lineTo(x, y);
      }
    }

    final Paint baselinePaint = Paint()
      ..color = baselineDecayColor.withOpacity(0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawPath(unreviewedPath, baselinePaint);

    // 5. Vẽ đường cong ghi nhớ khi có thuật toán SuperMemo SM-2 kèm vùng Gradient dưới đường cong
    final Path sm2Path = Path();
    final Path fillPath = Path();

    for (int i = 0; i <= activeSteps; i++) {
      final double tDays = (i / steps) * 14.0;
      final double retention = math.exp(-tDays / sm2Stability).clamp(0.15, 1.0);
      final double x = leftPad + (tDays / 14.0) * chartWidth;
      final double y = topPad + chartHeight * (1.0 - retention);

      if (i == 0) {
        sm2Path.moveTo(x, y);
        fillPath.moveTo(x, topPad + chartHeight);
        fillPath.lineTo(x, y);
      } else {
        sm2Path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }

      if (i == activeSteps) {
        fillPath.lineTo(x, topPad + chartHeight);
        fillPath.close();
      }
    }

    final Paint fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          primaryLineColor.withOpacity(0.36),
          primaryLineColor.withOpacity(0.02),
        ],
      ).createShader(Rect.fromLTWH(leftPad, topPad, chartWidth, chartHeight));
    canvas.drawPath(fillPath, fillPaint);

    final Paint sm2LinePaint = Paint()
      ..color = primaryLineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(sm2Path, sm2LinePaint);

    // 6. Vẽ các điểm nút (Nodes) trên đường cong SM-2
    for (final day in dayMarks) {
      if (day / 14.0 > progress) continue;
      final double retention = math.exp(-day / sm2Stability).clamp(0.15, 1.0);
      final double x = leftPad + (day / 14.0) * chartWidth;
      final double y = topPad + chartHeight * (1.0 - retention);

      canvas.drawCircle(
        Offset(x, y),
        5.0,
        Paint()..color = isDark ? const Color(0xFF0F172A) : Colors.white,
      );
      canvas.drawCircle(
        Offset(x, y),
        3.5,
        Paint()..color = primaryLineColor,
      );
    }
  }

  @override
  bool shouldRepaint(covariant RetentionCurvePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.averageEaseFactor != averageEaseFactor ||
        oldDelegate.averageIntervalDays != averageIntervalDays ||
        oldDelegate.isDark != isDark;
  }
}
