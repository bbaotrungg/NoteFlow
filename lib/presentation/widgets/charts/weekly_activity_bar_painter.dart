import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../domain/entities/study_session_entity.dart';

/// 3. WeeklyActivityBarPainter: Biểu đồ cột đôi thể hiện số lượng thẻ Flashcard và câu hỏi Quiz
/// đã hoàn thành trong 7 ngày gần nhất.
/// Cam kết 100% vẽ trực tiếp trên Canvas bằng CustomPainter ở tốc độ 60 FPS.
class WeeklyActivityBarChart extends StatefulWidget {
  final List<StudySessionEntity> sessions;

  const WeeklyActivityBarChart({
    super.key,
    required this.sessions,
  });

  @override
  State<WeeklyActivityBarChart> createState() => _WeeklyActivityBarChartState();
}

class _WeeklyActivityBarChartState extends State<WeeklyActivityBarChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _barAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _barAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutQuart,
    );
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant WeeklyActivityBarChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessions.length != widget.sessions.length) {
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
      animation: _barAnimation,
      builder: (context, _) {
        return CustomPaint(
          size: const Size(double.infinity, 200),
          painter: WeeklyActivityBarPainter(
            sessions: widget.sessions,
            progress: _barAnimation.value,
            isDark: isDark,
          ),
        );
      },
    );
  }
}

class WeeklyActivityBarPainter extends CustomPainter {
  final List<StudySessionEntity> sessions;
  final double progress;
  final bool isDark;

  WeeklyActivityBarPainter({
    required this.sessions,
    required this.progress,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const double leftPad = 34.0;
    const double rightPad = 14.0;
    const double topPad = 22.0;
    const double bottomPad = 32.0;

    final double chartWidth = size.width - leftPad - rightPad;
    final double chartHeight = size.height - topPad - bottomPad;
    if (chartWidth <= 0 || chartHeight <= 0) return;

    final now = DateTime.now();
    final days = List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      return DateTime(d.year, d.month, d.day);
    });

    final flashcardCounts = List<int>.filled(7, 0);
    final quizCounts = List<int>.filled(7, 0);

    for (final s in sessions) {
      final local = s.completedAt.toLocal();
      final dayKey = DateTime(local.year, local.month, local.day);
      for (int i = 0; i < 7; i++) {
        if (days[i] == dayKey) {
          if (s.sessionType == StudySessionType.flashcard) {
            flashcardCounts[i] += s.totalItems;
          } else {
            quizCounts[i] += s.totalItems;
          }
        }
      }
    }

    int maxItems = 20;
    for (int i = 0; i < 7; i++) {
      final total = flashcardCounts[i] + quizCounts[i];
      if (total > maxItems) maxItems = total;
    }
    maxItems = ((maxItems / 10).ceil() * 10);

    final Color gridColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final Color labelColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    const Color flashcardBarColor = Color(0xFF0284C7);
    const Color quizBarColor = Color(0xFF10B981);

    final Paint gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1.0;

    // 1. Vẽ đường lưới ngang
    for (int step = 0; step <= 4; step++) {
      final ratio = step / 4.0;
      final y = topPad + chartHeight * (1.0 - ratio);
      canvas.drawLine(Offset(leftPad, y), Offset(leftPad + chartWidth, y), gridPaint);

      final val = (maxItems * ratio).round();
      final tp = TextPainter(
        text: TextSpan(
          text: '$val',
          style: TextStyle(color: labelColor, fontSize: 10.5, fontWeight: FontWeight.w500),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(leftPad - tp.width - 6, y - tp.height / 2));
    }

    // 2. Vẽ các cột chồng (Stacked Rounded Bars) cho 7 ngày
    final double slotWidth = chartWidth / 7.0;
    final double barWidth = math.min(24.0, slotWidth * 0.48);

    for (int i = 0; i < 7; i++) {
      final double centerX = leftPad + slotWidth * (i + 0.5);
      final int fcCount = flashcardCounts[i];
      final int qzCount = quizCounts[i];
      final int totalCount = fcCount + qzCount;

      final double fcHeight = (fcCount / maxItems) * chartHeight * progress;
      final double qzHeight = (qzCount / maxItems) * chartHeight * progress;
      final double baseLineY = topPad + chartHeight;

      // Vẽ phần Flashcard (màu Sky Blue bên dưới)
      if (fcHeight > 0) {
        final RRect fcRect = RRect.fromRectAndCorners(
          Rect.fromLTWH(centerX - barWidth / 2, baseLineY - fcHeight, barWidth, fcHeight),
          topLeft: qzHeight == 0 ? const Radius.circular(6) : Radius.zero,
          topRight: qzHeight == 0 ? const Radius.circular(6) : Radius.zero,
        );
        canvas.drawRRect(fcRect, Paint()..color = flashcardBarColor);
      }

      // Vẽ phần Quiz (màu Emerald bên trên)
      if (qzHeight > 0) {
        final RRect qzRect = RRect.fromRectAndCorners(
          Rect.fromLTWH(
            centerX - barWidth / 2,
            baseLineY - fcHeight - qzHeight,
            barWidth,
            qzHeight,
          ),
          topLeft: const Radius.circular(6),
          topRight: const Radius.circular(6),
        );
        canvas.drawRRect(qzRect, Paint()..color = quizBarColor);
      }

      // Hiển thị tổng số lượng trên đỉnh cột
      if (totalCount > 0 && progress > 0.8) {
        final topText = TextPainter(
          text: TextSpan(
            text: '$totalCount',
            style: TextStyle(
              color: isDark ? Colors.white70 : const Color(0xFF0F172A),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        topText.paint(
          canvas,
          Offset(
            centerX - topText.width / 2,
            baseLineY - fcHeight - qzHeight - topText.height - 3,
          ),
        );
      }

      // Nhãn ngày (T2..CN hoặc dd/MM)
      final dayLabel = DateFormat('dd/MM').format(days[i]);
      final dayTp = TextPainter(
        text: TextSpan(
          text: dayLabel,
          style: TextStyle(
            color: i == 6 ? flashcardBarColor : labelColor,
            fontSize: 10.5,
            fontWeight: i == 6 ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      dayTp.paint(canvas, Offset(centerX - dayTp.width / 2, baseLineY + 8));
    }
  }

  @override
  bool shouldRepaint(covariant WeeklyActivityBarPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.sessions != sessions ||
        oldDelegate.isDark != isDark;
  }
}
