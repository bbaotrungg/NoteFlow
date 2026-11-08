import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/date_time_utils.dart';
import '../../domain/entities/flashcard_entity.dart';
import '../../domain/entities/study_session_entity.dart';
import '../../domain/services/sm2_spaced_repetition_service.dart';
import '../providers/app_providers.dart';
import '../widgets/flashcard/interactive_3d_flashcard.dart';

/// Màn hình Ôn tập Flashcard tương tác 3D kết hợp thuật toán lặp lại ngắt quãng SuperMemo SM-2
class FlashcardStudyScreen extends ConsumerStatefulWidget {
  final String? studySetId;
  final String title;
  final List<FlashcardEntity> initialCards;

  const FlashcardStudyScreen({
    super.key,
    this.studySetId,
    required this.title,
    required this.initialCards,
  });

  @override
  ConsumerState<FlashcardStudyScreen> createState() => _FlashcardStudyScreenState();
}

class _FlashcardStudyScreenState extends ConsumerState<FlashcardStudyScreen> {
  late List<FlashcardEntity> _deck;
  int _currentIndex = 0;
  int _elapsedSeconds = 0;
  Timer? _timer;
  final Map<ReviewRating, int> _ratingStats = {
    ReviewRating.again: 0,
    ReviewRating.hard: 0,
    ReviewRating.good: 0,
    ReviewRating.easy: 0,
  };
  bool _sessionRecorded = false;

  @override
  void initState() {
    super.initState();
    _deck = List<FlashcardEntity>.from(widget.initialCards);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _currentIndex < _deck.length) {
        setState(() => _elapsedSeconds++);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _submitRating(ReviewRating rating) async {
    if (_currentIndex >= _deck.length) return;
    final currentCard = _deck[_currentIndex];

    final updatedCard = await ref.read(reviewFlashcardUseCaseProvider).execute(
          flashcard: currentCard,
          rating: rating,
        );

    if (!mounted) return;
    setState(() {
      _deck[_currentIndex] = updatedCard;
      _ratingStats[rating] = (_ratingStats[rating] ?? 0) + 1;
      _currentIndex++;
    });

    if (_currentIndex >= _deck.length && !_sessionRecorded) {
      _sessionRecorded = true;
      _timer?.cancel();
      final targetSetId = widget.studySetId ?? currentCard.studySetId;
      final goodOrEasy =
          (_ratingStats[ReviewRating.good] ?? 0) + (_ratingStats[ReviewRating.easy] ?? 0);
      final scorePct = _deck.isEmpty ? 100.0 : (goodOrEasy / _deck.length) * 100.0;

      await ref.read(studyRepositoryProvider).recordStudySession(
            studySetId: targetSetId,
            sessionType: StudySessionType.flashcard,
            score: scorePct,
            totalItems: _deck.length,
            durationSeconds: _elapsedSeconds,
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCompleted = _currentIndex >= _deck.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.primarySkyBlue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.timer_outlined, size: 16, color: AppTheme.primarySkyBlue),
                    const SizedBox(width: 4),
                    Text(
                      DateTimeUtils.formatDurationClock(_elapsedSeconds),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primarySkyBlue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: _deck.isEmpty
            ? const Center(child: Text('Chưa có thẻ Flashcard nào trong bộ học tập này.'))
            : isCompleted
                ? _buildCompletionSummary(context)
                : _buildActiveDeckView(context),
      ),
    );
  }

  Widget _buildActiveDeckView(BuildContext context) {
    final currentCard = _deck[_currentIndex];
    final sm2 = ref.read(sm2ServiceProvider);
    final progress = (_currentIndex + 1) / _deck.length;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Thanh tiến trình ôn tập
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Thẻ ${_currentIndex + 1} / ${_deck.length}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              Text(
                'SM-2 Ease Factor: ${currentCard.easeFactor.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 13, color: AppTheme.primarySkyBlue),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: AppTheme.primarySkyBlue.withValues(alpha: 0.15),
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primarySkyBlue),
            ),
          ),
          const SizedBox(height: 20),
          // Thẻ Flashcard 3D
          Expanded(
            child: Center(
              child: Interactive3DFlashcard(
                flashcard: currentCard,
                onRated: _submitRating,
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Bộ 4 nút chấm điểm SuperMemo SM-2 kèm dự báo khoảng cách ngày ôn tập tiếp theo
          Row(
            children: ReviewRating.values.map((rating) {
              final preview = sm2.calculate(
                quality: rating.quality,
                currentEaseFactor: currentCard.easeFactor,
                currentIntervalDays: currentCard.intervalDays,
                currentRepetitionCount: currentCard.repetitionCount,
              );

              Color btnColor;
              switch (rating) {
                case ReviewRating.again:
                  btnColor = AppTheme.roseDanger;
                  break;
                case ReviewRating.hard:
                  btnColor = AppTheme.amberWarning;
                  break;
                case ReviewRating.good:
                  btnColor = AppTheme.primarySkyBlue;
                  break;
                case ReviewRating.easy:
                  btnColor = AppTheme.emeraldAccent;
                  break;
              }

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _submitRating(rating),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                      decoration: BoxDecoration(
                        color: btnColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: btnColor.withValues(alpha: 0.55), width: 1.4),
                      ),
                      child: Column(
                        children: [
                          Text(
                            rating.label,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              color: btnColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${preview.nextIntervalDays} ngày',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletionSummary(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.verified_rounded,
                  size: 64,
                  color: AppTheme.emeraldAccent,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Hoàn thành phiên ôn tập SM-2!',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Đã cập nhật lịch ôn tập tiếp theo (next_review_at) cho ${_deck.length} thẻ và đẩy vào hàng đợi đồng bộ Offline-First.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, height: 1.4),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: [
                    _buildStatPill('Rất dễ (q=5)', _ratingStats[ReviewRating.easy] ?? 0,
                        AppTheme.emeraldAccent),
                    _buildStatPill('Nhớ tốt (q=4)', _ratingStats[ReviewRating.good] ?? 0,
                        AppTheme.primarySkyBlue),
                    _buildStatPill('Tạm nhớ (q=3)', _ratingStats[ReviewRating.hard] ?? 0,
                        AppTheme.amberWarning),
                    _buildStatPill('Cần ôn lại (q=1)', _ratingStats[ReviewRating.again] ?? 0,
                        AppTheme.roseDanger),
                  ],
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Quay về Bảng điều khiển'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatPill(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        '$label: $count thẻ',
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13),
      ),
    );
  }
}
