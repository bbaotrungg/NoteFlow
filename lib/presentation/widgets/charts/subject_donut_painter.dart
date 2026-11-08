import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/subject_entity.dart';

/// 2. SubjectDonutPainter: Biểu đồ tròn phân bổ thời gian học tập giữa các môn học
/// Có animation xoay mượt mà và hỗ trợ chạm (Tap Hit-Testing) để xem chi tiết từng môn.
/// Cam kết 100% vẽ trực tiếp trên Canvas bằng CustomPainter.
class SubjectStudyDonutChart extends StatefulWidget {
  final List<SubjectEntity> subjects;

  const SubjectStudyDonutChart({
    super.key,
    required this.subjects,
  });

  @override
  State<SubjectStudyDonutChart> createState() => _SubjectStudyDonutChartState();
}

class _SubjectStudyDonutChartState extends State<SubjectStudyDonutChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _sweepAnimation;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );
    _sweepAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details, Size size) {
    if (widget.subjects.isEmpty) return;
    final center = Offset(size.width / 2, size.height / 2);
    final touchVec = details.localPosition - center;
    final distance = touchVec.distance;
    final radius = math.min(size.width, size.height) * 0.38;

    if (distance < radius * 0.45 || distance > radius * 1.25) return;

    double touchAngle = math.atan2(touchVec.dy, touchVec.dx);
    if (touchAngle < -math.pi / 2) {
      touchAngle += 2 * math.pi;
    }

    final totalWeight = _computeTotalWeight(widget.subjects);
    double startAngle = -math.pi / 2;

    for (int i = 0; i < widget.subjects.length; i++) {
      final weight = _subjectWeight(widget.subjects[i]);
      final sweep = (weight / totalWeight) * 2 * math.pi;
      if (touchAngle >= startAngle && touchAngle <= startAngle + sweep) {
        setState(() {
          _selectedIndex = i;
        });
        break;
      }
      startAngle += sweep;
    }
  }

  double _subjectWeight(SubjectEntity s) {
    final base = s.totalStudyMinutes + (s.documentCount * 15) + 10;
    return base.toDouble();
  }

  double _computeTotalWeight(List<SubjectEntity> list) {
    return list.fold<double>(0.0, (sum, item) => sum + _subjectWeight(item));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.subjects.isEmpty) {
      return const SizedBox(
        height: 180,
        child: Center(child: Text('Chưa có dữ liệu môn học')),
      );
    }

    final safeIndex = _selectedIndex.clamp(0, widget.subjects.length - 1);
    final selectedSubject = widget.subjects[safeIndex];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final chartSize = Size(constraints.maxWidth, 200);
            return GestureDetector(
              onTapDown: (details) => _handleTapDown(details, chartSize),
              child: AnimatedBuilder(
                animation: _sweepAnimation,
                builder: (context, _) {
                  return CustomPaint(
                    size: chartSize,
                    painter: SubjectDonutPainter(
                      subjects: widget.subjects,
                      selectedIndex: safeIndex,
                      animationValue: _sweepAnimation.value.clamp(0.0, 1.0),
                      isDark: isDark,
                    ),
                  );
                },
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: List.generate(widget.subjects.length, (index) {
            final sub = widget.subjects[index];
            final isSelected = index == safeIndex;
            final color = AppTheme.parseHexColor(sub.colorHex);
            return InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => setState(() => _selectedIndex = index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected ? color.withValues(alpha: 0.18) : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? color : color.withValues(alpha: 0.35),
                    width: isSelected ? 1.6 : 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${sub.code} (${sub.totalStudyMinutes > 0 ? "${sub.totalStudyMinutes}p" : "${sub.documentCount} TL"})',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 6),
        Text(
          'Đang chọn: ${selectedSubject.title} • ${selectedSubject.dueFlashcardCount} thẻ cần ôn',
          style: TextStyle(
            fontSize: 12.5,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class SubjectDonutPainter extends CustomPainter {
  final List<SubjectEntity> subjects;
  final int selectedIndex;
  final double animationValue;
  final bool isDark;

  SubjectDonutPainter({
    required this.subjects,
    required this.selectedIndex,
    required this.animationValue,
    required this.isDark,
  });

  double _subjectWeight(SubjectEntity s) {
    return (s.totalStudyMinutes + (s.documentCount * 15) + 10).toDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (subjects.isEmpty) return;

    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = math.min(size.width, size.height) * 0.36;
    final double totalWeight =
        subjects.fold<double>(0.0, (sum, item) => sum + _subjectWeight(item));

    double startAngle = -math.pi / 2;

    for (int i = 0; i < subjects.length; i++) {
      final sub = subjects[i];
      final weight = _subjectWeight(sub);
      final sweepAngle = (weight / totalWeight) * 2 * math.pi * animationValue;
      final isSelected = i == selectedIndex;
      final color = AppTheme.parseHexColor(sub.colorHex);

      final Paint arcPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 28.0 : 21.0
        ..strokeCap = StrokeCap.butt;

      final double midAngle = startAngle + sweepAngle / 2;
      final Offset arcCenter = isSelected
          ? Offset(
              center.dx + math.cos(midAngle) * 5.0,
              center.dy + math.sin(midAngle) * 5.0,
            )
          : center;

      canvas.drawArc(
        Rect.fromCircle(center: arcCenter, radius: radius),
        startAngle,
        math.max(0.01, sweepAngle - 0.04),
        false,
        arcPaint,
      );

      startAngle += sweepAngle;
    }

    // Vẽ thông tin tổng hợp ở tâm biểu đồ Donut
    final selected = subjects[selectedIndex];
    final pct = ((_subjectWeight(selected) / totalWeight) * 100).round();

    final titlePainter = TextPainter(
      text: TextSpan(
        text: '$pct%',
        style: TextStyle(
          color: isDark ? Colors.white : const Color(0xFF0F172A),
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final subPainter = TextPainter(
      text: TextSpan(
        text: selected.code,
        style: TextStyle(
          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    titlePainter.paint(
      canvas,
      Offset(center.dx - titlePainter.width / 2, center.dy - titlePainter.height + 2),
    );
    subPainter.paint(
      canvas,
      Offset(center.dx - subPainter.width / 2, center.dy + 4),
    );
  }

  @override
  bool shouldRepaint(covariant SubjectDonutPainter oldDelegate) {
    return oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.animationValue != animationValue ||
        oldDelegate.subjects != subjects ||
        oldDelegate.isDark != isDark;
  }
}
