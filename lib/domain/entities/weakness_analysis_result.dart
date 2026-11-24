/// Mức độ thông thạo kiến thức (Mastery Level)
enum MasteryLevel {
  strong('Vững chắc', 0xFF10B981),
  moderate('Trung bình', 0xFFF59E0B),
  weak('Cần củng cố', 0xFFF43F5E),
  insufficientData('Chưa đủ dữ liệu', 0xFF64748B);

  final String label;
  final int colorHex;
  const MasteryLevel(this.label, this.colorHex);
}

/// Loại mục học tập có điểm yếu
enum WeakItemType {
  flashcard('Thẻ ghi nhớ'),
  quiz('Câu hỏi trắc nghiệm');

  final String label;
  const WeakItemType(this.label);
}

/// Chi tiết một mục học tập (Flashcard hoặc Quiz) đang gặp khó khăn
class WeakItemEntity {
  final String id;
  final String title;
  final WeakItemType type;
  final double easeFactor;
  final double accuracyRate;
  final int failureCount;
  final String reason;
  final String studySetId;
  final String studySetTitle;

  const WeakItemEntity({
    required this.id,
    required this.title,
    required this.type,
    required this.easeFactor,
    required this.accuracyRate,
    required this.failureCount,
    required this.reason,
    required this.studySetId,
    required this.studySetTitle,
  });
}

/// Đánh giá điểm yếu của từng Bộ học liệu (Topic / Study Set)
class TopicWeaknessEntity {
  final String studySetId;
  final String studySetTitle;
  final String subjectTitle;
  final MasteryLevel masteryLevel;
  final double masteryScore; // 0.0 - 100.0
  final int totalCards;
  final int weakCardsCount;
  final double averageEaseFactor;
  final double quizAccuracy;
  final bool hasQuizData;
  final List<WeakItemEntity> weakItems;
  final List<String> recommendations;

  const TopicWeaknessEntity({
    required this.studySetId,
    required this.studySetTitle,
    required this.subjectTitle,
    required this.masteryLevel,
    required this.masteryScore,
    required this.totalCards,
    required this.weakCardsCount,
    required this.averageEaseFactor,
    required this.quizAccuracy,
    this.hasQuizData = false,
    this.weakItems = const [],
    this.recommendations = const [],
  });

  bool get isWeak => masteryLevel == MasteryLevel.weak;
  bool get needsAttention =>
      masteryLevel == MasteryLevel.weak ||
      masteryLevel == MasteryLevel.moderate;
}

/// Kết quả phân tích tổng thể toàn bộ hệ thống học tập
class WeaknessAnalysisResult {
  final int totalTopicsAnalyzed;
  final int weakTopicsCount;
  final int moderateTopicsCount;
  final int strongTopicsCount;
  final double overallMasteryScore; // 0.0 - 100.0
  final List<TopicWeaknessEntity> topics;
  final List<WeakItemEntity> topWeakItems;
  final List<String> generalAdvice;

  const WeaknessAnalysisResult({
    required this.totalTopicsAnalyzed,
    required this.weakTopicsCount,
    required this.moderateTopicsCount,
    required this.strongTopicsCount,
    required this.overallMasteryScore,
    required this.topics,
    required this.topWeakItems,
    required this.generalAdvice,
  });

  factory WeaknessAnalysisResult.empty() => const WeaknessAnalysisResult(
        totalTopicsAnalyzed: 0,
        weakTopicsCount: 0,
        moderateTopicsCount: 0,
        strongTopicsCount: 0,
        overallMasteryScore: 100.0,
        topics: [],
        topWeakItems: [],
        generalAdvice: [
          'Chưa có dữ liệu học tập. Hãy tạo bộ học liệu và ôn tập flashcard để kích hoạt phân tích điểm yếu!'
        ],
      );
}
