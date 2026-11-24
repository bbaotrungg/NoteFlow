import 'package:flutter_test/flutter_test.dart';
import 'package:noteflow_ai/data/services/ai_study_assistant_service.dart';
import 'package:noteflow_ai/domain/entities/flashcard_entity.dart';
import 'package:noteflow_ai/domain/entities/quiz_question_entity.dart';
import 'package:noteflow_ai/domain/entities/review_plan_entity.dart';
import 'package:noteflow_ai/domain/entities/study_session_entity.dart';
import 'package:noteflow_ai/domain/entities/study_set_entity.dart';
import 'package:noteflow_ai/domain/entities/subject_entity.dart';
import 'package:noteflow_ai/domain/services/review_planner_service.dart';
import 'package:noteflow_ai/domain/services/sm2_spaced_repetition_service.dart';
import 'package:noteflow_ai/domain/services/weakness_detection_service.dart';

void main() {
  group('Phase 4: Full Intelligent AI Features Integration Pipeline', () {
    const sm2Service = Sm2SpacedRepetitionService();
    const weaknessService = WeaknessDetectionService();
    const reviewPlanner = ReviewPlannerService();
    final assistantService = AiStudyAssistantService(apiKey: '');

    final testDate = DateTime(2026, 11, 24, 10, 0);

    test(
        'End-to-End Cycle: SM-2 Review -> Weakness Detection -> Daily Review Plan -> AI Assistant Grounding',
        () async {
      // 1. Khởi tạo Môn học & Bộ học liệu ban đầu
      final subject = SubjectEntity(
        id: 'sub_int_1',
        title: 'Trí Tuệ Nhân Tạo',
        code: 'AI101',
        colorHex: '#0284C7',
        updatedAt: testDate,
      );

      var card1 = FlashcardEntity(
        id: 'card_int_1',
        studySetId: 'set_int_1',
        frontText: 'Thuật toán A* sử dụng hàm đánh giá nào?',
        backText:
            'f(n) = g(n) + h(n), với g(n) là chi phí thực và h(n) là hàm heuristic',
        hint: 'Hàm đánh giá chi phí tổng thể',
        easeFactor: 2.5,
        intervalDays: 0,
        repetitionCount: 0,
        nextReviewAt: testDate,
        updatedAt: testDate,
      );

      var card2 = FlashcardEntity(
        id: 'card_int_2',
        studySetId: 'set_int_1',
        frontText: 'Điều kiện để thuật toán A* đảm bảo tối ưu?',
        backText:
            'Hàm heuristic h(n) phải chấp nhận được (admissible), không đánh giá vượt quá chi phí thực',
        hint: 'Tính chất của hàm h(n)',
        easeFactor: 2.5,
        intervalDays: 0,
        repetitionCount: 0,
        nextReviewAt: testDate,
        updatedAt: testDate,
      );

      final quizQuestion = QuizQuestionEntity(
        id: 'quiz_int_1',
        studySetId: 'set_int_1',
        questionText:
            'Trong thuật toán A*, nếu h(n) = 0 thì thuật toán trở thành thuật toán nào?',
        options: [
          'Dijkstra',
          'Breadth-First Search',
          'Depth-First Search',
          'Greedy Best-First'
        ],
        correctIndex: 0,
        explanation:
            'Khi h(n) = 0, f(n) = g(n) chính là thuật toán tìm đường ngắn nhất Dijkstra.',
        timesAnswered: 4,
        timesCorrect: 1, // 25% accuracy (< 60%)
        updatedAt: testDate,
      );

      var studySet = StudySetEntity(
        id: 'set_int_1',
        documentId: 'doc_int_1',
        title: 'Giải thuật Tìm kiếm Đồ thị trong AI',
        summaryMarkdown:
            '### Tìm kiếm có thông tin:\n* Thuật toán A*\n* Tính admissible và consistent của Heuristic',
        updatedAt: testDate,
        flashcards: [card1, card2],
        quizQuestions: [quizQuestion],
      );

      // 2. Sinh viên học và liên tục xếp loại "Hard" / "Again" trên card1 qua SM-2
      // Lần 1: Again (q=1)
      card1 = sm2Service.applyReview(
          flashcard: card1,
          rating: ReviewRating.again,
          reviewTimestamp: testDate);
      expect(card1.easeFactor, 1.96); // Giảm xuống < 2.0!

      // Lần 2: Hard (q=2)
      card1 = sm2Service.applyReview(
          flashcard: card1,
          rating: ReviewRating.hard,
          reviewTimestamp: testDate);
      expect(card1.easeFactor, lessThan(1.9));

      // card2 học tốt (Good)
      card2 = sm2Service.applyReview(
          flashcard: card2,
          rating: ReviewRating.good,
          reviewTimestamp: testDate);

      studySet = studySet.copyWith(flashcards: [card1, card2]);

      // 3. Phân tích Điểm yếu Thông minh (Weakness Detection)
      final weakness = weaknessService.analyze(
        studySets: [studySet],
        subjects: [subject],
        recentSessions: [],
      );

      expect(weakness.totalTopicsAnalyzed, 1);
      expect(weakness.weakTopicsCount, 1);
      final analyzedTopic = weakness.topics.first;
      expect(analyzedTopic.isWeak, isTrue);
      expect(analyzedTopic.weakCardsCount, 1);
      expect(weakness.topWeakItems.isNotEmpty, isTrue);
      expect(weakness.topWeakItems.first.title.toLowerCase(),
          contains('thuật toán a*'));

      // 4. Lập Kế hoạch Ôn tập Hàng ngày (Personalized Review Planner)
      var dailyPlan = reviewPlanner.generateDailyPlan(
        studySets: [studySet],
        subjects: [subject],
        recentSessions: [],
        weaknessAnalysis: weakness,
        referenceDate: testDate,
      );

      expect(dailyPlan.tasks.isNotEmpty, isTrue);
      final urgentOrDrillTask = dailyPlan.tasks.first;
      expect(
        urgentOrDrillTask.taskType == ReviewTaskType.flashcardReview ||
            urgentOrDrillTask.taskType == ReviewTaskType.weaknessDrill,
        isTrue,
      );
      expect(urgentOrDrillTask.isCompleted, isFalse);

      // 5. Sinh viên hoàn thành phiên ôn tập điểm yếu trong ngày hôm nay
      final completedSession = StudySessionEntity(
        id: 'session_completed_1',
        studySetId: studySet.id,
        sessionType: StudySessionType.flashcard,
        totalItems: 2,
        durationSeconds: 150,
        completedAt: testDate.add(const Duration(minutes: 30)),
      );

      // Kế hoạch cập nhật tức thì (Dynamic Adaptation)
      dailyPlan = reviewPlanner.generateDailyPlan(
        studySets: [studySet],
        subjects: [subject],
        recentSessions: [completedSession],
        weaknessAnalysis: weakness,
        referenceDate: testDate,
      );

      final completedTask =
          dailyPlan.tasks.firstWhere((t) => t.studySetId == studySet.id);
      expect(completedTask.isCompleted, isTrue);
      expect(dailyPlan.completedTaskCount, greaterThanOrEqualTo(1));

      // 6. Tương tác với Trợ lý Học tập AI (AI Study Assistant)
      final assistantReply = await assistantService.askAssistant(
        userPrompt: 'Giải thích chi tiết về thuật toán A* và hàm heuristic',
        studySet: studySet,
      );

      expect(assistantReply.isAssistant, isTrue);
      expect(assistantReply.content, contains('A*'));
      expect(assistantReply.references.isNotEmpty, isTrue);
      expect(assistantReply.suggestedActions.isNotEmpty, isTrue);
    });
  });
}
