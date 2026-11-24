import 'package:flutter_test/flutter_test.dart';
import 'package:noteflow_ai/domain/entities/flashcard_entity.dart';
import 'package:noteflow_ai/domain/entities/review_plan_entity.dart';
import 'package:noteflow_ai/domain/entities/study_session_entity.dart';
import 'package:noteflow_ai/domain/entities/study_set_entity.dart';
import 'package:noteflow_ai/domain/entities/subject_entity.dart';
import 'package:noteflow_ai/domain/entities/weakness_analysis_result.dart';
import 'package:noteflow_ai/domain/services/review_planner_service.dart';

void main() {
  group('ReviewPlannerService - Personalized Review Planner Tests', () {
    const planner = ReviewPlannerService();
    final now = DateTime(2026, 11, 24, 10, 0);

    test('Assigns ReviewTaskPriority.urgent to overdue flashcards', () {
      final studySet = StudySetEntity(
        id: 'set_overdue',
        documentId: 'doc_1',
        title: 'Cơ sở Dữ liệu Quan hệ',
        summaryMarkdown: 'SQL & Chuẩn hóa',
        updatedAt: now,
        flashcards: [
          FlashcardEntity(
            id: 'card_overdue',
            studySetId: 'set_overdue',
            frontText: 'Khóa ngoại (Foreign Key) là gì?',
            backText: 'Thuộc tính tham chiếu tới khóa chính của bảng khác',
            easeFactor: 2.3,
            intervalDays: 4,
            repetitionCount: 2,
            nextReviewAt:
                now.subtract(const Duration(days: 2)), // Đã quá hạn 2 ngày
            updatedAt: now.subtract(const Duration(days: 6)),
          ),
        ],
        quizQuestions: [],
      );

      final plan = planner.generateDailyPlan(
        studySets: [studySet],
        subjects: [
          SubjectEntity(
            id: 'sub_1',
            title: 'Cơ sở Dữ liệu',
            code: 'CS102',
            colorHex: '#0284C7',
            updatedAt: now,
          ),
        ],
        recentSessions: [],
        weaknessAnalysis: WeaknessAnalysisResult.empty(),
        referenceDate: now,
      );

      expect(plan.tasks.isNotEmpty, isTrue);
      final urgentTask = plan.tasks.first;
      expect(urgentTask.priority, ReviewTaskPriority.urgent);
      expect(urgentTask.taskType, ReviewTaskType.flashcardReview);
      expect(urgentTask.itemCount, 1);
      expect(urgentTask.reason, contains('quá hạn'));
      expect(urgentTask.isCompleted, isFalse);
    });

    test('Assigns ReviewTaskPriority.high to cards due today', () {
      final studySet = StudySetEntity(
        id: 'set_due_today',
        documentId: 'doc_2',
        title: 'Kỹ thuật Lập trình C++',
        summaryMarkdown: 'Con trỏ & Quản lý bộ nhớ',
        updatedAt: now,
        flashcards: [
          FlashcardEntity(
            id: 'card_today',
            studySetId: 'set_due_today',
            frontText: 'Toán tử new và delete làm gì?',
            backText: 'Cấp phát và giải phóng bộ nhớ heap trong C++',
            easeFactor: 2.5,
            intervalDays: 3,
            repetitionCount: 1,
            nextReviewAt: DateTime(2026, 11, 24, 18, 0), // Đến hạn chiều nay
            updatedAt: now.subtract(const Duration(days: 3)),
          ),
        ],
        quizQuestions: [],
      );

      final plan = planner.generateDailyPlan(
        studySets: [studySet],
        subjects: [],
        recentSessions: [],
        weaknessAnalysis: WeaknessAnalysisResult.empty(),
        referenceDate: now,
      );

      expect(plan.tasks.isNotEmpty, isTrue);
      final dueTask = plan.tasks.first;
      expect(dueTask.priority, ReviewTaskPriority.high);
      expect(dueTask.taskType, ReviewTaskType.flashcardReview);
      expect(dueTask.reason, contains('hôm nay'));
    });

    test(
        'Dynamic Adaptation: Logged session today automatically marks task as completed',
        () {
      final studySet = StudySetEntity(
        id: 'set_completed',
        documentId: 'doc_3',
        title: 'Kiến trúc Máy tính',
        summaryMarkdown: 'ALU, Register, Bus',
        updatedAt: now,
        flashcards: [
          FlashcardEntity(
            id: 'card_done',
            studySetId: 'set_completed',
            frontText: 'Thanh ghi PC (Program Counter) lưu gì?',
            backText: 'Địa chỉ của lệnh tiếp theo cần thực thi',
            easeFactor: 2.5,
            intervalDays: 1,
            repetitionCount: 1,
            nextReviewAt: now.subtract(const Duration(hours: 1)),
            updatedAt: now,
          ),
        ],
        quizQuestions: [],
      );

      // Giả lập phiên học flashcard vừa hoàn thành hôm nay
      final todaySession = StudySessionEntity(
        id: 'sess_today_1',
        studySetId: 'set_completed',
        sessionType: StudySessionType.flashcard,
        totalItems: 1,
        durationSeconds: 45,
        completedAt: now.subtract(const Duration(minutes: 10)),
      );

      final plan = planner.generateDailyPlan(
        studySets: [studySet],
        subjects: [],
        recentSessions: [todaySession],
        weaknessAnalysis: WeaknessAnalysisResult.empty(),
        referenceDate: now,
      );

      expect(plan.tasks.isNotEmpty, isTrue);
      final task = plan.tasks.first;
      expect(task.isCompleted, isTrue);
      expect(plan.completedTaskCount, 1);
      expect(plan.completionRate, 1.0);
      expect(plan.isAllCompleted, isTrue);
    });

    test('Includes weakness drill task from weakness analysis result', () {
      final studySet = StudySetEntity(
        id: 'set_weak_math',
        documentId: 'doc_4',
        title: 'Đại số Tuyến tính',
        summaryMarkdown: 'Ma trận & Không gian vector',
        updatedAt: now,
        flashcards: [
          FlashcardEntity(
            id: 'card_weak_1',
            studySetId: 'set_weak_math',
            frontText: 'Định thức ma trận 2x2',
            backText: 'ad - bc',
            easeFactor: 1.6,
            intervalDays: 5,
            repetitionCount: 2,
            nextReviewAt:
                now.add(const Duration(days: 3)), // Chưa đến hạn flashcard
            updatedAt: now,
          ),
        ],
        quizQuestions: [],
      );

      const weaknessResult = WeaknessAnalysisResult(
        totalTopicsAnalyzed: 1,
        weakTopicsCount: 1,
        moderateTopicsCount: 0,
        strongTopicsCount: 0,
        overallMasteryScore: 45.0,
        topics: [
          TopicWeaknessEntity(
            studySetId: 'set_weak_math',
            studySetTitle: 'Đại số Tuyến tính',
            subjectTitle: 'Toán học',
            masteryLevel: MasteryLevel.weak,
            masteryScore: 45.0,
            totalCards: 1,
            weakCardsCount: 1,
            averageEaseFactor: 1.6,
            quizAccuracy: 0.0,
          ),
        ],
        topWeakItems: [],
        generalAdvice: [],
      );

      final plan = planner.generateDailyPlan(
        studySets: [studySet],
        subjects: [],
        recentSessions: [],
        weaknessAnalysis: weaknessResult,
        referenceDate: now,
      );

      expect(plan.tasks.isNotEmpty, isTrue);
      final drillTask = plan.tasks.firstWhere(
        (t) => t.taskType == ReviewTaskType.weaknessDrill,
      );
      expect(drillTask.priority, ReviewTaskPriority.high);
      expect(drillTask.reason, contains('Điểm thông thạo thấp'));
    });

    test(
        'Partial Session Safety: Reviewing 5 of 20 overdue cards leaves task uncompleted',
        () {
      // 20 thẻ quá hạn
      final cards = List.generate(
        20,
        (i) => FlashcardEntity(
          id: 'card_overdue_$i',
          studySetId: 'set_partial',
          frontText: 'Khái niệm $i',
          backText: 'Định nghĩa $i',
          easeFactor: 2.5,
          intervalDays: 1,
          repetitionCount: 1,
          nextReviewAt: now.subtract(const Duration(days: 2)), // Quá hạn
          updatedAt: now.subtract(const Duration(days: 3)),
        ),
      );

      final studySet = StudySetEntity(
        id: 'set_partial',
        documentId: 'doc_part',
        title: 'Hệ Quản trị Cơ sở Dữ liệu',
        summaryMarkdown: 'Indexing & Transaction',
        updatedAt: now,
        flashcards: cards,
        quizQuestions: [],
      );

      // Người dùng chỉ mới hoàn thành phiên học 5 thẻ (bỏ dở hoặc chỉ ôn 5 thẻ)
      final partialSession = StudySessionEntity(
        id: 'sess_partial',
        studySetId: 'set_partial',
        sessionType: StudySessionType.flashcard,
        totalItems: 5,
        durationSeconds: 120,
        completedAt: now.subtract(const Duration(minutes: 15)),
      );

      final plan = planner.generateDailyPlan(
        studySets: [studySet],
        subjects: [],
        recentSessions: [partialSession],
        weaknessAnalysis: WeaknessAnalysisResult.empty(),
        referenceDate: now,
      );

      expect(plan.tasks.isNotEmpty, isTrue);
      final overdueTask = plan.tasks.firstWhere(
        (t) =>
            t.studySetId == 'set_partial' &&
            t.taskType == ReviewTaskType.flashcardReview,
      );

      // Phải là false vì 5 < 20 thẻ! Không được vội vàng đánh dấu hoàn thành toàn bộ
      expect(overdueTask.isCompleted, isFalse);
      expect(overdueTask.itemCount, 20);
      expect(overdueTask.reason, contains('Đã ôn 5/20 thẻ hôm nay'));
      expect(plan.completedTaskCount, 0);
      expect(plan.completionRate, 0.0);
    });
  });
}
