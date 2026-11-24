import 'dart:math' as math;

import '../entities/study_session_entity.dart';
import '../entities/study_set_entity.dart';
import '../entities/subject_entity.dart';
import '../entities/weakness_analysis_result.dart';

/// Dịch vụ Phát hiện Điểm yếu Học tập Thông minh (Smart Weakness Detection Service)
/// - Phân tích toán học xác định (Deterministic Mathematical Analysis) dựa trên dữ liệu học tập thực tế:
///   1. Độ khó SuperMemo SM-2 (Ease Factor < 2.0 phản ánh thẻ nhiều lần quên hoặc xếp loại Hard/Again).
///   2. Tỷ lệ chính xác câu hỏi trắc nghiệm Quiz (Accuracy Rate < 60% với số lần trả lời >= 1).
///   3. Lịch sử điểm số các phiên học tập Study Sessions gần đây.
/// - Cơ chế bảo vệ dữ liệu tối thiểu (Insufficient Data Guard): Nếu bộ học liệu có ít hơn 3 lượt tương tác,
///   hệ thống gắn cờ "Chưa đủ dữ liệu" thay vì kết luận võ đoán.
/// - Minh bạch & Có thể giải thích được (Explainable Metrics): Mọi điểm yếu đều đi kèm lý do và số liệu cụ thể.
class WeaknessDetectionService {
  const WeaknessDetectionService();

  /// Ngưỡng Ease Factor cảnh báo thẻ khó / điểm yếu
  static const double weakEaseFactorThreshold = 2.0;

  /// Ngưỡng Ease Factor mức độ trung bình
  static const double moderateEaseFactorThreshold = 2.3;

  /// Ngưỡng độ chính xác câu hỏi trắc nghiệm dưới mức an toàn
  static const double lowQuizAccuracyThreshold = 0.60;

  /// Số tương tác tối thiểu để đưa ra kết luận phân tích điểm yếu
  static const int minInteractionsForAnalysis = 3;

  /// Phân tích toàn diện điểm yếu trên toàn bộ hệ thống
  WeaknessAnalysisResult analyze({
    required List<StudySetEntity> studySets,
    required List<SubjectEntity> subjects,
    required List<StudySessionEntity> recentSessions,
  }) {
    final activeSets = studySets.where((s) => !s.isDeleted).toList();
    if (activeSets.isEmpty) {
      return WeaknessAnalysisResult.empty();
    }

    // Bản đồ tra cứu tên môn học theo document_id / subject
    final subjectMap = {for (final s in subjects) s.id: s.title};

    final topicEntities = <TopicWeaknessEntity>[];
    final allWeakItems = <WeakItemEntity>[];

    for (final studySet in activeSets) {
      final topicAnalysis = analyzeStudySet(
        studySet: studySet,
        subjectTitle: subjectMap[studySet.documentId] ?? 'Môn học',
        sessions: recentSessions
            .where((sess) => sess.studySetId == studySet.id)
            .toList(),
      );
      topicEntities.add(topicAnalysis);
      allWeakItems.addAll(topicAnalysis.weakItems);
    }

    // Sắp xếp các điểm yếu nhất lên đầu (Ease Factor thấp nhất hoặc Accuracy thấp nhất)
    allWeakItems.sort((a, b) {
      if (a.type == WeakItemType.flashcard &&
          b.type == WeakItemType.flashcard) {
        return a.easeFactor.compareTo(b.easeFactor);
      }
      if (a.type == WeakItemType.quiz && b.type == WeakItemType.quiz) {
        return a.accuracyRate.compareTo(b.accuracyRate);
      }
      return a.failureCount > b.failureCount ? -1 : 1;
    });

    int weakCount = 0;
    int moderateCount = 0;
    int strongCount = 0;
    double totalMasteryScore = 0.0;
    int validAnalyzedCount = 0;

    for (final t in topicEntities) {
      switch (t.masteryLevel) {
        case MasteryLevel.weak:
          weakCount++;
          totalMasteryScore += t.masteryScore;
          validAnalyzedCount++;
          break;
        case MasteryLevel.moderate:
          moderateCount++;
          totalMasteryScore += t.masteryScore;
          validAnalyzedCount++;
          break;
        case MasteryLevel.strong:
          strongCount++;
          totalMasteryScore += t.masteryScore;
          validAnalyzedCount++;
          break;
        case MasteryLevel.insufficientData:
          // Không kéo tụt điểm trung bình toàn hệ thống
          break;
      }
    }

    final overallMastery = validAnalyzedCount > 0
        ? (totalMasteryScore / validAnalyzedCount).clamp(0.0, 100.0)
        : 100.0;

    final generalAdvice = _generateSystemAdvice(
      weakCount: weakCount,
      moderateCount: moderateCount,
      strongCount: strongCount,
      topWeakCount: allWeakItems.length,
      overallMastery: overallMastery,
    );

    return WeaknessAnalysisResult(
      totalTopicsAnalyzed: topicEntities.length,
      weakTopicsCount: weakCount,
      moderateTopicsCount: moderateCount,
      strongTopicsCount: strongCount,
      overallMasteryScore: (overallMastery * 10).roundToDouble() / 10,
      topics: topicEntities,
      topWeakItems: allWeakItems.take(5).toList(),
      generalAdvice: generalAdvice,
    );
  }

  /// Phân tích điểm yếu cho một Bộ học liệu cụ thể
  TopicWeaknessEntity analyzeStudySet({
    required StudySetEntity studySet,
    String subjectTitle = 'Môn học',
    List<StudySessionEntity> sessions = const [],
  }) {
    final activeCards = studySet.flashcards.where((f) => !f.isDeleted).toList();
    final activeQuizzes =
        studySet.quizQuestions.where((q) => !q.isDeleted).toList();

    final weakItems = <WeakItemEntity>[];
    int totalInteractions = 0;

    // 1. Phân tích Flashcards
    double sumEaseFactor = 0.0;
    int reviewedCardsCount = 0;
    int weakCardsCount = 0;

    for (final card in activeCards) {
      if (card.repetitionCount > 0 || card.easeFactor < 2.5) {
        reviewedCardsCount++;
        totalInteractions += math.max(1, card.repetitionCount);
        sumEaseFactor += card.easeFactor;

        // Thẻ bị xếp vào diện Yếu nếu Ease Factor < 2.0 hoặc đã ôn nhiều lần nhưng vẫn bị reset interval về 1 ngày
        if (card.easeFactor < weakEaseFactorThreshold) {
          weakCardsCount++;
          weakItems.add(
            WeakItemEntity(
              id: card.id,
              title: card.frontText,
              type: WeakItemType.flashcard,
              easeFactor: card.easeFactor,
              accuracyRate: 0.0,
              failureCount: math.max(1, 3 - (card.easeFactor * 1.2).toInt()),
              reason:
                  'Hệ số ghi nhớ SM-2 thấp (EF: ${card.easeFactor.toStringAsFixed(2)} < 2.0). Đã quên hoặc gặp khó khăn nhiều lần.',
              studySetId: studySet.id,
              studySetTitle: studySet.title,
            ),
          );
        } else if (card.repetitionCount >= 3 && card.intervalDays <= 2) {
          weakCardsCount++;
          weakItems.add(
            WeakItemEntity(
              id: card.id,
              title: card.frontText,
              type: WeakItemType.flashcard,
              easeFactor: card.easeFactor,
              accuracyRate: 0.0,
              failureCount: 2,
              reason:
                  'Khoảng cách ôn tập ngắn (${card.intervalDays} ngày sau ${card.repetitionCount} lần ôn). Kiến thức chưa bền vững.',
              studySetId: studySet.id,
              studySetTitle: studySet.title,
            ),
          );
        }
      } else {
        sumEaseFactor += 2.5; // Giá trị khởi tạo
      }
    }

    final avgEaseFactor =
        activeCards.isNotEmpty ? sumEaseFactor / activeCards.length : 2.5;

    // 2. Phân tích Quiz Questions
    int totalQuizAnswered = 0;
    int totalQuizCorrect = 0;

    for (final quiz in activeQuizzes) {
      if (quiz.timesAnswered > 0) {
        totalInteractions += quiz.timesAnswered;
        totalQuizAnswered += quiz.timesAnswered;
        totalQuizCorrect += quiz.timesCorrect;

        if (quiz.accuracyRate < lowQuizAccuracyThreshold) {
          final isSingleTrial = quiz.timesAnswered == 1;
          weakItems.add(
            WeakItemEntity(
              id: quiz.id,
              title: quiz.questionText,
              type: WeakItemType.quiz,
              easeFactor: 0.0,
              accuracyRate: quiz.accuracyRate,
              failureCount: quiz.timesAnswered - quiz.timesCorrect,
              reason: isSingleTrial
                  ? 'Đã trả lời sai trong 1 lần làm thử đầu tiên (cần thêm lượt làm để đánh giá chính xác).'
                  : 'Độ chính xác trắc nghiệm thấp: ${(quiz.accuracyRate * 100).toInt()}% (${quiz.timesCorrect}/${quiz.timesAnswered} câu đúng).',
              studySetId: studySet.id,
              studySetTitle: studySet.title,
            ),
          );
        }
      }
    }

    final quizAccuracy =
        totalQuizAnswered > 0 ? totalQuizCorrect / totalQuizAnswered : 0.0;

    // 3. Kiểm tra Insufficient Data Guard (Bảo vệ dữ liệu mẫu nhỏ)
    if (totalInteractions < minInteractionsForAnalysis ||
        (reviewedCardsCount == 0 && totalQuizAnswered == 0)) {
      return TopicWeaknessEntity(
        studySetId: studySet.id,
        studySetTitle: studySet.title,
        subjectTitle: subjectTitle,
        masteryLevel: MasteryLevel.insufficientData,
        masteryScore: 50.0,
        totalCards: activeCards.length,
        weakCardsCount: weakCardsCount,
        averageEaseFactor: (avgEaseFactor * 100).round() / 100,
        quizAccuracy: (quizAccuracy * 100).round() / 100,
        hasQuizData: totalQuizAnswered > 0,
        weakItems: weakItems,
        recommendations: const [
          'Chưa đủ dữ liệu ôn tập. Hãy hoàn thành ít nhất 1 phiên học flashcard hoặc thử thách trắc nghiệm!',
        ],
      );
    }

    // 4. Tính toán Chỉ số Thông thạo Thích ứng (Adaptive Mastery Score: 0.0 - 100.0)
    // - Flashcard Health: Dựa trên Ease Factor chuẩn hóa (1.3 -> 0%, 2.5+ -> 100%) và tỷ lệ thẻ yếu
    final efNormalized = ((avgEaseFactor - 1.3) / (2.5 - 1.3)).clamp(0.0, 1.0);
    final weakCardPenalty = activeCards.isNotEmpty
        ? (weakCardsCount / activeCards.length) * 0.35
        : 0.0;
    final flashcardScore =
        ((efNormalized - weakCardPenalty).clamp(0.0, 1.0)) * 100;

    // - Quiz Health: Dựa trên độ chính xác trắc nghiệm
    final quizScore = totalQuizAnswered > 0 ? (quizAccuracy * 100) : 0.0;

    // Cân bằng trọng số thích ứng:
    // - Nếu cả 2 đều có dữ liệu: 60% Flashcard + 40% Quiz
    // - Nếu chỉ có Flashcard (Case A & C): 100% Flashcard Score
    // - Nếu chỉ có Quiz (Case D): 100% Quiz Score
    double compositeScore;
    if (reviewedCardsCount > 0 && totalQuizAnswered > 0) {
      compositeScore = flashcardScore * 0.6 + quizScore * 0.4;
    } else if (reviewedCardsCount > 0) {
      compositeScore = flashcardScore;
    } else if (totalQuizAnswered > 0) {
      compositeScore = quizScore;
    } else {
      compositeScore = 50.0;
    }

    final roundedScore = (compositeScore * 10).roundToDouble() / 10;

    // 5. Phân loại Mức độ Thông thạo (Mastery Classification)
    MasteryLevel level;
    if (roundedScore >= 78.0 && weakCardsCount == 0) {
      level = MasteryLevel.strong;
    } else if (roundedScore < 60.0 ||
        weakCardsCount >= 2 ||
        (weakItems.length >= 3 && totalInteractions >= 5)) {
      level = MasteryLevel.weak;
    } else {
      level = MasteryLevel.moderate;
    }

    // 6. Sinh Khuyến nghị Hành động
    final recommendations = _generateTopicRecommendations(
      studySetTitle: studySet.title,
      level: level,
      weakCardsCount: weakCardsCount,
      weakItemsCount: weakItems.length,
      quizAccuracy: quizAccuracy,
      hasQuizData: totalQuizAnswered > 0,
    );

    return TopicWeaknessEntity(
      studySetId: studySet.id,
      studySetTitle: studySet.title,
      subjectTitle: subjectTitle,
      masteryLevel: level,
      masteryScore: roundedScore,
      totalCards: activeCards.length,
      weakCardsCount: weakCardsCount,
      averageEaseFactor: (avgEaseFactor * 100).round() / 100,
      quizAccuracy: (quizAccuracy * 100).round() / 100,
      hasQuizData: totalQuizAnswered > 0,
      weakItems: weakItems,
      recommendations: recommendations,
    );
  }

  /// Sinh danh sách khuyến nghị học tập cho một bộ học liệu
  List<String> _generateTopicRecommendations({
    required String studySetTitle,
    required MasteryLevel level,
    required int weakCardsCount,
    required int weakItemsCount,
    required double quizAccuracy,
    required bool hasQuizData,
  }) {
    final list = <String>[];
    switch (level) {
      case MasteryLevel.weak:
        if (weakCardsCount > 0) {
          list.add(
              'Ưu tiên ôn lại $weakCardsCount thẻ ghi nhớ có độ khó cao trước khi học nội dung mới.');
        }
        if (hasQuizData && quizAccuracy < 0.6) {
          list.add(
              'Thử làm lại bài trắc nghiệm để củng cố các câu hỏi bị trả lời sai.');
        }
        list.add(
            'Mở Trợ lý AI để nghe giải thích chuyên sâu các khái niệm dễ nhầm lẫn.');
        break;
      case MasteryLevel.moderate:
        list.add(
            'Duy trì nhịp độ ôn tập ngắt quãng SM-2 để đưa kiến thức vào trí nhớ dài hạn.');
        if (weakItemsCount > 0) {
          list.add('Tập trung giải quyết $weakItemsCount mục còn phân vân.');
        }
        break;
      case MasteryLevel.strong:
        list.add(
            'Kiến thức rất vững chắc! Tiếp tục ôn tập định kỳ khi thẻ đến hạn.');
        list.add(
            'Bạn có thể thử tạo thêm câu hỏi nâng cao với Trợ lý AI để thử thách bản thân.');
        break;
      case MasteryLevel.insufficientData:
        list.add(
            'Hãy bắt đầu phiên ôn tập đầu tiên để kích hoạt phân tích năng lực.');
        break;
    }
    return list;
  }

  /// Lời khuyên tổng thể cho toàn hệ thống
  List<String> _generateSystemAdvice({
    required int weakCount,
    required int moderateCount,
    required int strongCount,
    required int topWeakCount,
    required double overallMastery,
  }) {
    final advice = <String>[];
    if (weakCount > 0) {
      advice.add(
        'Bạn có $weakCount chủ đề cần củng cố ngay. Hãy tập trung xử lý $topWeakCount mục khó nhất trong Kế hoạch ôn tập hôm nay.',
      );
    } else if (moderateCount > 0) {
      advice.add(
        'Tiến độ rất khả quan! Hãy giải quyết các chủ đề ở mức Trung bình để nâng điểm thông thạo tổng thể lên trên 85%.',
      );
    } else if (strongCount > 0) {
      advice.add(
        'Xuất sắc! Tất cả các chủ đề đều ở trạng thái Vững chắc (${overallMastery.toStringAsFixed(1)}%). Hãy duy trì chuỗi học tập hàng ngày!',
      );
    } else {
      advice.add(
        'Hãy thực hiện các phiên ôn tập flashcard để NoteFlow phân tích điểm mạnh và điểm yếu của bạn.',
      );
    }
    return advice;
  }
}
