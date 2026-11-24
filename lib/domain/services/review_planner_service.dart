import 'dart:math' as math;

import '../entities/flashcard_entity.dart';
import '../entities/review_plan_entity.dart';
import '../entities/study_session_entity.dart';
import '../entities/study_set_entity.dart';
import '../entities/subject_entity.dart';
import '../entities/weakness_analysis_result.dart';

/// Dịch vụ Lập Kế hoạch Ôn tập Cá nhân hóa Hàng ngày (Personalized Review Planner Service)
/// - Tuân thủ nguyên tắc SuperMemo SM-2 là Nguồn Chân lý (Source of Truth).
/// - Phân cấp thứ tự ưu tiên ôn tập theo thuật toán thích ứng (Adaptive Spaced Repetition Prioritization):
///   1. KHẨN CẤP (Urgent): Thẻ Flashcard đã quá hạn ôn tập (Overdue cards).
///   2. QUAN TRỌNG (High): Thẻ Flashcard đến hạn hôm nay + Các chủ đề điểm yếu (Weakness Drills).
///   3. TIÊU CHUẨN (Normal): Luyện trắc nghiệm củng cố các bộ học liệu có tỷ lệ sai cao hoặc lâu chưa làm quiz.
///   4. DUY TRÌ (Maintenance): Ôn nhanh để duy trì trí nhớ đối với các chủ đề vững chắc.
/// - Tự động thích ứng động (Dynamic Adaptation): Khi người dùng hoàn thành một phiên học flashcard hoặc quiz,
///   kế hoạch lập tức cập nhật trạng thái `isCompleted = true` và tính toán lại tỷ lệ hoàn thành trong ngày.
class ReviewPlannerService {
  const ReviewPlannerService();

  DailyReviewPlan generateDailyPlan({
    required List<StudySetEntity> studySets,
    required List<SubjectEntity> subjects,
    required List<StudySessionEntity> recentSessions,
    required WeaknessAnalysisResult weaknessAnalysis,
    DateTime? referenceDate,
  }) {
    final now = referenceDate ?? DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);

    final activeSets = studySets.where((s) => !s.isDeleted).toList();
    if (activeSets.isEmpty) {
      return DailyReviewPlan.empty();
    }

    final subjectMap = {for (final s in subjects) s.id: s.title};

    // Lọc các phiên học đã hoàn thành trong ngày hôm nay
    final todaySessions = recentSessions.where((sess) {
      return sess.completedAt.isAfter(startOfToday) &&
          sess.completedAt.isBefore(endOfToday.add(const Duration(seconds: 1)));
    }).toList();

    final tasks = <ReviewPlanTaskEntity>[];

    // 1. Phân tích Thẻ Flashcard đến hạn & quá hạn theo từng Bộ học liệu
    for (final studySet in activeSets) {
      final activeCards =
          studySet.flashcards.where((f) => !f.isDeleted).toList();
      if (activeCards.isEmpty) continue;

      final overdueCards = <FlashcardEntity>[];
      final dueTodayCards = <FlashcardEntity>[];

      for (final card in activeCards) {
        if (card.nextReviewAt.isBefore(startOfToday)) {
          overdueCards.add(card);
        } else if (!card.nextReviewAt.isAfter(endOfToday)) {
          dueTodayCards.add(card);
        }
      }

      final subjectTitle = subjectMap[studySet.documentId] ?? 'Học phần';

      // Tính tổng số thẻ Flashcard đã thực sự ôn tập trong ngày hôm nay cho bộ học liệu này
      final totalReviewedCardsToday = todaySessions
          .where((s) =>
              s.studySetId == studySet.id &&
              s.sessionType == StudySessionType.flashcard)
          .fold<int>(0, (sum, s) => sum + s.totalItems);

      // Thẻ quá hạn -> Nhiệm vụ Khẩn cấp
      if (overdueCards.isNotEmpty) {
        final estMin = math.max(3, (overdueCards.length * 0.6).ceil());
        // Bảo vệ an toàn: Chỉ đánh dấu hoàn thành nếu số thẻ đã ôn hôm nay >= số thẻ quá hạn
        // Ngăn chặn trường hợp có 20 thẻ nhưng mới chỉ ôn 5 thẻ đã vội đánh dấu hoàn thành nhiệm vụ!
        final isCompleted = overdueCards.isEmpty ||
            (totalReviewedCardsToday >= overdueCards.length &&
                overdueCards.length <= totalReviewedCardsToday);
        final partialInfo = totalReviewedCardsToday > 0 && !isCompleted
            ? ' (Đã ôn $totalReviewedCardsToday/${overdueCards.length} thẻ hôm nay)'
            : '';

        tasks.add(
          ReviewPlanTaskEntity(
            id: 'task_overdue_${studySet.id}',
            studySetId: studySet.id,
            studySetTitle: studySet.title,
            subjectTitle: subjectTitle,
            taskType: ReviewTaskType.flashcardReview,
            priority: ReviewTaskPriority.urgent,
            estimatedMinutes: estMin,
            itemCount: overdueCards.length,
            reason:
                'Có ${overdueCards.length} thẻ quá hạn ôn tập SM-2$partialInfo. Cần ôn ngay để tránh quên lãng!',
            isCompleted: isCompleted,
          ),
        );
      } else if (dueTodayCards.isNotEmpty) {
        // Thẻ đến hạn hôm nay -> Nhiệm vụ Quan trọng
        final estMin = math.max(2, (dueTodayCards.length * 0.5).ceil());
        final isCompleted = dueTodayCards.isEmpty ||
            (totalReviewedCardsToday >= dueTodayCards.length &&
                dueTodayCards.length <= totalReviewedCardsToday);
        final partialInfo = totalReviewedCardsToday > 0 && !isCompleted
            ? ' (Đã ôn $totalReviewedCardsToday/${dueTodayCards.length} thẻ hôm nay)'
            : '';

        tasks.add(
          ReviewPlanTaskEntity(
            id: 'task_due_${studySet.id}',
            studySetId: studySet.id,
            studySetTitle: studySet.title,
            subjectTitle: subjectTitle,
            taskType: ReviewTaskType.flashcardReview,
            priority: ReviewTaskPriority.high,
            estimatedMinutes: estMin,
            itemCount: dueTodayCards.length,
            reason:
                'Có ${dueTodayCards.length} thẻ đến hạn ôn tập định kỳ hôm nay theo thuật toán SM-2$partialInfo.',
            isCompleted: isCompleted,
          ),
        );
      }
    }

    // 2. Thêm Nhiệm vụ Củng cố Điểm yếu từ kết quả Stage B (Weakness Detection)
    for (final topic in weaknessAnalysis.topics) {
      if (topic.isWeak && topic.weakCardsCount > 0) {
        // Tránh trùng lặp nếu đã có nhiệm vụ flashcard overdue của bộ này
        final alreadyHasFlashcardTask =
            tasks.any((t) => t.studySetId == topic.studySetId);

        if (!alreadyHasFlashcardTask) {
          final reviewedCardsInSetToday = todaySessions
              .where((s) =>
                  s.studySetId == topic.studySetId &&
                  s.sessionType == StudySessionType.flashcard)
              .fold<int>(0, (sum, s) => sum + s.totalItems);

          // Chỉ coi là hoàn thành luyện tập điểm yếu nếu đã ôn tập ít nhất bằng số thẻ yếu
          final isDrillCompleted =
              reviewedCardsInSetToday >= topic.weakCardsCount;

          tasks.add(
            ReviewPlanTaskEntity(
              id: 'task_weakness_${topic.studySetId}',
              studySetId: topic.studySetId,
              studySetTitle: topic.studySetTitle,
              subjectTitle: topic.subjectTitle,
              taskType: ReviewTaskType.weaknessDrill,
              priority: ReviewTaskPriority.high,
              estimatedMinutes: math.max(4, topic.weakCardsCount * 1),
              itemCount: topic.weakCardsCount,
              reason:
                  'Điểm thông thạo thấp (${topic.masteryScore}%). Cần luyện tập củng cố ${topic.weakCardsCount} thẻ khó.',
              isCompleted: isDrillCompleted,
            ),
          );
        }
      }
    }

    // 3. Thêm Nhiệm vụ Trắc nghiệm Đánh giá (Quiz Reinforcement)
    for (final studySet in activeSets) {
      final activeQuizzes =
          studySet.quizQuestions.where((q) => !q.isDeleted).toList();
      if (activeQuizzes.length < 2) continue;

      // Tìm phiên trắc nghiệm gần nhất
      final setQuizSessions = recentSessions
          .where((s) =>
              s.studySetId == studySet.id &&
              s.sessionType == StudySessionType.quiz)
          .toList();
      setQuizSessions.sort((a, b) => b.completedAt.compareTo(a.completedAt));

      final lastQuiz =
          setQuizSessions.isNotEmpty ? setQuizSessions.first : null;
      final daysSinceLastQuiz =
          lastQuiz != null ? now.difference(lastQuiz.completedAt).inDays : 999;

      // Đánh dấu hoàn thành Quiz chỉ khi phiên trắc nghiệm hôm nay có số câu hoàn thành hợp lệ (>= 2 câu)
      final completedQuizToday = todaySessions.any(
        (s) =>
            s.studySetId == studySet.id &&
            s.sessionType == StudySessionType.quiz &&
            s.totalItems >= math.min(2, activeQuizzes.length),
      );

      // Nếu chưa làm quiz quá 3 ngày hoặc điểm thi gần nhất < 70%
      if (daysSinceLastQuiz >= 3 ||
          (lastQuiz?.score != null && lastQuiz!.score! < 0.70)) {
        // Giới hạn số nhiệm vụ quiz không quá 2 nhiệm vụ / ngày để tránh quá tải
        final currentQuizTasks = tasks
            .where((t) => t.taskType == ReviewTaskType.quizReinforcement)
            .length;
        if (currentQuizTasks < 2) {
          final scoreText = lastQuiz?.score != null
              ? ' (Điểm gần nhất: ${(lastQuiz!.score! * 100).toInt()}%)'
              : '';
          tasks.add(
            ReviewPlanTaskEntity(
              id: 'task_quiz_${studySet.id}',
              studySetId: studySet.id,
              studySetTitle: studySet.title,
              subjectTitle: 'Trắc nghiệm',
              taskType: ReviewTaskType.quizReinforcement,
              priority: ReviewTaskPriority.normal,
              estimatedMinutes: math.max(3, activeQuizzes.length * 1),
              itemCount: activeQuizzes.length,
              reason:
                  'Đã $daysSinceLastQuiz ngày chưa kiểm tra trắc nghiệm$scoreText. Làm bài để củng cố phản xạ!',
              isCompleted: completedQuizToday,
            ),
          );
        }
      }
    }

    // Sắp xếp thứ tự ưu tiên: urgent -> high -> normal -> maintenance
    tasks.sort((a, b) {
      if (a.isCompleted != b.isCompleted) {
        return a.isCompleted ? 1 : -1; // Đẩy nhiệm vụ đã xong xuống dưới
      }
      return a.priority.index.compareTo(b.priority.index);
    });

    int totalMinutes = 0;
    int completedCount = 0;
    for (final t in tasks) {
      totalMinutes += t.estimatedMinutes;
      if (t.isCompleted) completedCount++;
    }

    return DailyReviewPlan(
      date: now,
      tasks: tasks,
      totalEstimatedMinutes: totalMinutes,
      completedTaskCount: completedCount,
    );
  }
}
