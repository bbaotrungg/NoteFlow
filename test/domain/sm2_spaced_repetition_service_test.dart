import 'package:flutter_test/flutter_test.dart';
import 'package:noteflow_ai/domain/entities/flashcard_entity.dart';
import 'package:noteflow_ai/domain/services/sm2_spaced_repetition_service.dart';

void main() {
  const service = Sm2SpacedRepetitionService();
  final baseDate = DateTime(2026, 10, 26, 10, 0);

  group('SuperMemo SM-2 Cognitive Algorithm Tests', () {
    test('First successful review (q=4, n=0 -> n=1) sets interval to 1 day and keeps EF=2.5', () {
      final result = service.calculate(
        quality: 4,
        currentEaseFactor: 2.5,
        currentIntervalDays: 0,
        currentRepetitionCount: 0,
        evaluatedAt: baseDate,
      );

      expect(result.nextRepetitionCount, 1);
      expect(result.nextIntervalDays, 1);
      expect(result.nextEaseFactor, closeTo(2.5, 0.001));
      expect(result.nextReviewAt, baseDate.add(const Duration(days: 1)));
    });

    test('Second successful review (q=5, n=1 -> n=2) sets interval to 6 days and increases EF by 0.1', () {
      final result = service.calculate(
        quality: 5,
        currentEaseFactor: 2.5,
        currentIntervalDays: 1,
        currentRepetitionCount: 1,
        evaluatedAt: baseDate,
      );

      expect(result.nextRepetitionCount, 2);
      expect(result.nextIntervalDays, 6);
      expect(result.nextEaseFactor, closeTo(2.6, 0.001));
      expect(result.nextReviewAt, baseDate.add(const Duration(days: 6)));
    });

    test('Third successful review (q=5, n=2 -> n=3) multiplies previous interval by new EF', () {
      final result = service.calculate(
        quality: 5,
        currentEaseFactor: 2.6,
        currentIntervalDays: 6,
        currentRepetitionCount: 2,
        evaluatedAt: baseDate,
      );

      // newEF = 2.6 + 0.1 = 2.7; interval = round(6 * 2.7) = 16
      expect(result.nextRepetitionCount, 3);
      expect(result.nextEaseFactor, closeTo(2.7, 0.001));
      expect(result.nextIntervalDays, 16);
    });

    test('Forgotten card (q < 3) resets repetitionCount to 0 and intervalDays to 1', () {
      final result = service.calculate(
        quality: 1,
        currentEaseFactor: 2.5,
        currentIntervalDays: 15,
        currentRepetitionCount: 4,
        evaluatedAt: baseDate,
      );

      expect(result.nextRepetitionCount, 0);
      expect(result.nextIntervalDays, 1);
      expect(result.nextEaseFactor, lessThan(2.5));
    });

    test('Ease Factor never drops below minimum threshold 1.3 (Anti-Ease-Hell constraint)', () {
      final result = service.calculate(
        quality: 0,
        currentEaseFactor: 1.32,
        currentIntervalDays: 6,
        currentRepetitionCount: 2,
        evaluatedAt: baseDate,
      );

      expect(result.nextEaseFactor, equals(1.3));
    });

    test('applyReview immutably updates FlashcardEntity with new SM-2 schedule', () {
      final card = FlashcardEntity(
        id: 'fc-01',
        studySetId: 'set-01',
        frontText: 'Question',
        backText: 'Answer',
        easeFactor: 2.5,
        intervalDays: 1,
        repetitionCount: 1,
        nextReviewAt: baseDate,
        updatedAt: baseDate,
      );

      final updated = service.applyReview(
        flashcard: card,
        rating: ReviewRating.good,
        reviewTimestamp: baseDate,
      );

      expect(updated.repetitionCount, 2);
      expect(updated.intervalDays, 6);
      expect(updated.nextReviewAt, baseDate.add(const Duration(days: 6)));
    });
  });
}
