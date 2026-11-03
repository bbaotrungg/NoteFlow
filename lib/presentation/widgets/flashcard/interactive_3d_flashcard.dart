import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/flashcard_entity.dart';
import '../../../domain/services/sm2_spaced_repetition_service.dart';

/// Thẻ Flashcard tương tác 3 chiều (3D Flip Animation) sử dụng ma trận biến đổi [Matrix4]
/// Kết hợp cử chỉ vuốt thẻ (Swipe Gestures) theo 3 hướng để chấm điểm trực tiếp vào thuật toán SuperMemo SM-2:
/// - Vuốt Trái (Swipe Left): Khó / Quên (ReviewRating.again -> q = 1)
/// - Vuốt Lên (Swipe Up): Vừa / Nhớ tốt (ReviewRating.good -> q = 4)
/// - Vuốt Phải (Swipe Right): Dễ / Phản xạ nhanh (ReviewRating.easy -> q = 5)
class Interactive3DFlashcard extends StatefulWidget {
  final FlashcardEntity flashcard;
  final ValueChanged<ReviewRating> onRated;

  const Interactive3DFlashcard({
    super.key,
    required this.flashcard,
    required this.onRated,
  });

  @override
  State<Interactive3DFlashcard> createState() => _Interactive3DFlashcardState();
}

class _Interactive3DFlashcardState extends State<Interactive3DFlashcard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flipController;
  late final Animation<double> _flipAnimation;

  bool _isFrontVisible = true;
  bool _showHint = false;
  Offset _dragOffset = Offset.zero;

  @override
  void initState() {
    super.initState();
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _flipAnimation = CurvedAnimation(
      parent: _flipController,
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  void didUpdateWidget(covariant Interactive3DFlashcard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.flashcard.id != widget.flashcard.id) {
      _flipController.reset();
      _isFrontVisible = true;
      _showHint = false;
      _dragOffset = Offset.zero;
    }
  }

  @override
  void dispose() {
    _flipController.dispose();
    super.dispose();
  }

  void _toggleFlip() {
    if (_flipController.isAnimating) return;
    if (_isFrontVisible) {
      _flipController.forward();
    } else {
      _flipController.reverse();
    }
    setState(() {
      _isFrontVisible = !_isFrontVisible;
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.delta;
    });
  }

  void _onPanEnd(DragEndDetails details) {
    const double horizontalThreshold = 110.0;
    const double verticalThreshold = -105.0;

    if (_dragOffset.dx <= -horizontalThreshold) {
      widget.onRated(ReviewRating.again);
    } else if (_dragOffset.dx >= horizontalThreshold) {
      widget.onRated(ReviewRating.easy);
    } else if (_dragOffset.dy <= verticalThreshold) {
      widget.onRated(ReviewRating.good);
    }

    setState(() {
      _dragOffset = Offset.zero;
    });
  }

  ReviewRating? _previewSwipeRating() {
    if (_dragOffset.dx < -55) return ReviewRating.again;
    if (_dragOffset.dx > 55) return ReviewRating.easy;
    if (_dragOffset.dy < -55) return ReviewRating.good;
    return null;
  }

  Color _badgeColorForRating(ReviewRating rating) {
    switch (rating) {
      case ReviewRating.again:
        return AppTheme.roseDanger;
      case ReviewRating.hard:
        return AppTheme.amberWarning;
      case ReviewRating.good:
        return AppTheme.primarySkyBlue;
      case ReviewRating.easy:
        return AppTheme.emeraldAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final previewRating = _previewSwipeRating();
    final double tiltZ = (_dragOffset.dx / 320).clamp(-0.22, 0.22);

    return GestureDetector(
      onTap: _toggleFlip,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: AnimatedContainer(
        duration: _dragOffset == Offset.zero
            ? const Duration(milliseconds: 220)
            : Duration.zero,
        curve: Curves.easeOutBack,
        transform: Matrix4.identity()
          ..translate(_dragOffset.dx, _dragOffset.dy)
          ..rotateZ(tiltZ),
        child: AnimatedBuilder(
          animation: _flipAnimation,
          builder: (context, _) {
            final double angle = _flipAnimation.value * math.pi;
            final bool showingFront = angle <= (math.pi / 2);

            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0012) // Phối cảnh chiều sâu 3D (3D Perspective Depth)
                ..rotateY(angle),
              child: showingFront
                  ? _buildCardSurface(
                      context,
                      isFront: true,
                      previewRating: previewRating,
                    )
                  : Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()..rotateY(math.pi),
                      child: _buildCardSurface(
                        context,
                        isFront: false,
                        previewRating: previewRating,
                      ),
                    ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCardSurface(
    BuildContext context, {
    required bool isFront,
    required ReviewRating? previewRating,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = widget.flashcard;

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 340, maxHeight: 430),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isFront
              ? (isDark
                  ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                  : [Colors.white, const Color(0xFFF0F9FF)])
              : (isDark
                  ? [const Color(0xFF0F172A), const Color(0xFF1E1B4B)]
                  : [const Color(0xFFF0FDF4), Colors.white]),
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: previewRating != null
              ? _badgeColorForRating(previewRating)
              : (isFront
                  ? AppTheme.primarySkyBlue.withOpacity(0.45)
                  : AppTheme.emeraldAccent.withOpacity(0.55)),
          width: previewRating != null ? 2.8 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.35 : 0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header thông số SuperMemo SM-2
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: (isFront ? AppTheme.primarySkyBlue : AppTheme.emeraldAccent)
                      .withOpacity(0.16),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isFront ? Icons.help_outline_rounded : Icons.lightbulb_rounded,
                      size: 16,
                      color: isFront ? AppTheme.primarySkyBlue : AppTheme.emeraldAccent,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isFront ? 'MẶT TRƯỚC (CÂU HỎI)' : 'MẶT SAU (ĐÁP ÁN)',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: isFront ? AppTheme.primarySkyBlue : AppTheme.emeraldAccent,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                'EF: ${card.easeFactor.toStringAsFixed(2)} • Lặp: ${card.repetitionCount} • ${card.intervalDays}d',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
            ],
          ),
          if (previewRating != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.center,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: _badgeColorForRating(previewRating),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '${previewRating.swipeDirectionLabel}: ${previewRating.label} (q=${previewRating.quality})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
          const Spacer(),
          // Nội dung chính của thẻ
          SingleChildScrollView(
            child: Text(
              isFront ? card.frontText : card.backText,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: isFront ? 20 : 18,
                height: 1.45,
                fontWeight: isFront ? FontWeight.w700 : FontWeight.w500,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
          ),
          const Spacer(),
          // Gợi ý (Hint) và hướng dẫn lật 3D
          if (isFront && card.hint != null && card.hint!.isNotEmpty) ...[
            if (_showHint)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.amberWarning.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.amberWarning.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.tips_and_updates_rounded,
                        size: 18, color: AppTheme.amberWarning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Gợi ý: ${card.hint}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              )
            else
              Center(
                child: TextButton.icon(
                  onPressed: () => setState(() => _showHint = true),
                  icon: const Icon(Icons.visibility_outlined, size: 16),
                  label: const Text('Xem gợi ý (Hint)'),
                ),
              ),
            const SizedBox(height: 8),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.threesixty_rounded,
                size: 16,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
              const SizedBox(width: 6),
              Text(
                'Chạm để lật 3D • Vuốt Trái (Khó) / Lên (Vừa) / Phải (Dễ)',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
