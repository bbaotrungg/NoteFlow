import 'package:flutter_test/flutter_test.dart';
import 'package:noteflow_ai/domain/entities/flashcard_entity.dart';
import 'package:noteflow_ai/domain/entities/quiz_question_entity.dart';
import 'package:noteflow_ai/domain/entities/study_set_entity.dart';
import 'package:noteflow_ai/domain/entities/subject_entity.dart';
import 'package:noteflow_ai/domain/services/sm2_spaced_repetition_service.dart';

void main() {
  final now = DateTime.utc(2026, 11, 8, 12, 0, 0);

  group('FlashcardEntity Unit Tests', () {
    test('isDue correctly calculates due state relative to reference time', () {
      final pastCard = FlashcardEntity(
        id: 'fc-past',
        studySetId: 'set-1',
        frontText: 'Front',
        backText: 'Back',
        nextReviewAt: now.subtract(const Duration(minutes: 5)),
        updatedAt: now,
      );

      final exactCard = FlashcardEntity(
        id: 'fc-exact',
        studySetId: 'set-1',
        frontText: 'Front',
        backText: 'Back',
        nextReviewAt: now,
        updatedAt: now,
      );

      final futureCard = FlashcardEntity(
        id: 'fc-future',
        studySetId: 'set-1',
        frontText: 'Front',
        backText: 'Back',
        nextReviewAt: now.add(const Duration(hours: 2)),
        updatedAt: now,
      );

      expect(pastCard.isDue(now), isTrue);
      expect(exactCard.isDue(now), isTrue);
      expect(futureCard.isDue(now), isFalse);
    });

    test('toSyncJson produces valid map with ISO timestamps and correct fields', () {
      final card = FlashcardEntity(
        id: 'fc-sync',
        studySetId: 'set-sync',
        frontText: 'Cây đỏ đen là gì?',
        backText: 'Cây tìm kiếm nhị phân tự cân bằng',
        hint: 'Màu sắc các nút',
        easeFactor: 2.6,
        intervalDays: 6,
        repetitionCount: 2,
        nextReviewAt: now,
        updatedAt: now,
        isDeleted: false,
      );

      final json = card.toSyncJson();
      expect(json['id'], 'fc-sync');
      expect(json['study_set_id'], 'set-sync');
      expect(json['front_text'], 'Cây đỏ đen là gì?');
      expect(json['back_text'], 'Cây tìm kiếm nhị phân tự cân bằng');
      expect(json['hint'], 'Màu sắc các nút');
      expect(json['ease_factor'], 2.6);
      expect(json['interval_days'], 6);
      expect(json['repetition_count'], 2);
      expect(json['next_review_at'], now.toUtc().toIso8601String());
      expect(json['updated_at'], now.toUtc().toIso8601String());
      expect(json['is_deleted'], false);
    });
  });

  group('StudySetEntity Unit Tests', () {
    test('dueFlashcardsCount counts only active (non-deleted) cards that are due', () {
      final dueCard1 = FlashcardEntity(
        id: 'card-1',
        studySetId: 'set-1',
        frontText: 'Q1',
        backText: 'A1',
        nextReviewAt: DateTime.now().subtract(const Duration(hours: 1)),
        updatedAt: DateTime.now(),
        isDeleted: false,
      );

      final dueCard2 = FlashcardEntity(
        id: 'card-2',
        studySetId: 'set-1',
        frontText: 'Q2',
        backText: 'A2',
        nextReviewAt: DateTime.now().subtract(const Duration(minutes: 10)),
        updatedAt: DateTime.now(),
        isDeleted: false,
      );

      final futureCard = FlashcardEntity(
        id: 'card-3',
        studySetId: 'set-1',
        frontText: 'Q3',
        backText: 'A3',
        nextReviewAt: DateTime.now().add(const Duration(days: 3)),
        updatedAt: DateTime.now(),
        isDeleted: false,
      );

      final deletedDueCard = FlashcardEntity(
        id: 'card-4',
        studySetId: 'set-1',
        frontText: 'Q4',
        backText: 'A4',
        nextReviewAt: DateTime.now().subtract(const Duration(days: 1)),
        updatedAt: DateTime.now(),
        isDeleted: true, // Soft-deleted
      );

      final studySet = StudySetEntity(
        id: 'set-1',
        documentId: 'doc-1',
        title: 'Cấu trúc dữ liệu',
        summaryMarkdown: '# Tóm tắt',
        updatedAt: DateTime.now(),
        flashcards: [dueCard1, dueCard2, futureCard, deletedDueCard],
      );

      expect(studySet.dueFlashcardsCount, 2);
    });
  });

  group('SubjectEntity & QuizQuestionEntity Serialization Tests', () {
    test('SubjectEntity toSyncJson formats ISO dates and properties accurately', () {
      final subject = SubjectEntity(
        id: 'sub-vku-01',
        title: 'Hệ thống nhúng VKU',
        code: 'EMB202',
        colorHex: '#3B82F6',
        updatedAt: now,
        isDeleted: false,
        documentCount: 4,
        dueFlashcardCount: 12,
        totalStudyMinutes: 90,
      );

      final json = subject.toSyncJson();
      expect(json['id'], 'sub-vku-01');
      expect(json['title'], 'Hệ thống nhúng VKU');
      expect(json['code'], 'EMB202');
      expect(json['color_hex'], '#3B82F6');
      expect(json['updated_at'], now.toUtc().toIso8601String());
      expect(json['is_deleted'], false);
    });

    test('QuizQuestionEntity computes accuracyRate and formats optionsJson', () {
      final quiz = QuizQuestionEntity(
        id: 'quiz-01',
        studySetId: 'set-01',
        questionText: 'Thứ tự duyệt hậu thứ tự (Post-order) là gì?',
        options: ['Gốc - Trái - Phải', 'Trái - Phải - Gốc', 'Trái - Gốc - Phải', 'Phải - Trái - Gốc'],
        correctIndex: 1,
        explanation: 'Post-order duyệt cây con trái, rồi cây con phải, cuối cùng là nút gốc.',
        timesAnswered: 5,
        timesCorrect: 4,
        updatedAt: now,
      );

      expect(quiz.accuracyRate, 0.8);
      expect(quiz.optionsJson, contains('"Trái - Phải - Gốc"'));
      expect(quiz.toSyncJson()['correct_index'], 1);
    });
  });

  group('SM-2 Cognitive Matrix Extended Tests', () {
    const service = Sm2SpacedRepetitionService();

    test('ReviewRating.again (q=1) forces repetition reset and 1 day interval', () {
      final card = FlashcardEntity(
        id: 'card-again',
        studySetId: 'set-1',
        frontText: 'Front',
        backText: 'Back',
        easeFactor: 2.5,
        intervalDays: 16,
        repetitionCount: 3,
        nextReviewAt: now,
        updatedAt: now,
      );

      final result = service.applyReview(
        flashcard: card,
        rating: ReviewRating.again,
        reviewTimestamp: now,
      );

      expect(result.repetitionCount, 0);
      expect(result.intervalDays, 1);
      expect(result.easeFactor, lessThan(2.5));
      expect(result.nextReviewAt, now.add(const Duration(days: 1)));
    });

    test('ReviewRating.hard maintains repetition progression with penalised ease factor', () {
      final card = FlashcardEntity(
        id: 'card-hard',
        studySetId: 'set-1',
        frontText: 'Front',
        backText: 'Back',
        easeFactor: 2.5,
        intervalDays: 1,
        repetitionCount: 1,
        nextReviewAt: now,
        updatedAt: now,
      );

      final result = service.applyReview(
        flashcard: card,
        rating: ReviewRating.hard,
        reviewTimestamp: now,
      );

      expect(result.repetitionCount, 2);
      expect(result.intervalDays, 6);
      // q=3: EF decreases by 0.14
      expect(result.easeFactor, closeTo(2.36, 0.01));
    });

    test('ReviewRating.easy gives maximum ease factor boost', () {
      final card = FlashcardEntity(
        id: 'card-easy',
        studySetId: 'set-1',
        frontText: 'Front',
        backText: 'Back',
        easeFactor: 2.5,
        intervalDays: 1,
        repetitionCount: 1,
        nextReviewAt: now,
        updatedAt: now,
      );

      final result = service.applyReview(
        flashcard: card,
        rating: ReviewRating.easy,
        reviewTimestamp: now,
      );

      expect(result.repetitionCount, 2);
      expect(result.intervalDays, 6);
      // q=5: EF increases by 0.1
      expect(result.easeFactor, closeTo(2.6, 0.01));
    });
  });
}
