/// Thực thể Thẻ ghi nhớ (FLASHCARDS) hỗ trợ thuật toán lặp lại ngắt quãng SuperMemo SM-2
class FlashcardEntity {
  final String id;
  final String studySetId;
  final String frontText;
  final String backText;
  final String? hint;
  final double easeFactor;
  final int intervalDays;
  final int repetitionCount;
  final DateTime nextReviewAt;
  final DateTime updatedAt;
  final bool isDeleted;

  const FlashcardEntity({
    required this.id,
    required this.studySetId,
    required this.frontText,
    required this.backText,
    this.hint,
    this.easeFactor = 2.5,
    this.intervalDays = 0,
    this.repetitionCount = 0,
    required this.nextReviewAt,
    required this.updatedAt,
    this.isDeleted = false,
  });

  bool isDue([DateTime? referenceTime]) {
    final now = referenceTime ?? DateTime.now();
    return !nextReviewAt.isAfter(now);
  }

  FlashcardEntity copyWith({
    String? id,
    String? studySetId,
    String? frontText,
    String? backText,
    String? hint,
    double? easeFactor,
    int? intervalDays,
    int? repetitionCount,
    DateTime? nextReviewAt,
    DateTime? updatedAt,
    bool? isDeleted,
  }) {
    return FlashcardEntity(
      id: id ?? this.id,
      studySetId: studySetId ?? this.studySetId,
      frontText: frontText ?? this.frontText,
      backText: backText ?? this.backText,
      hint: hint ?? this.hint,
      easeFactor: easeFactor ?? this.easeFactor,
      intervalDays: intervalDays ?? this.intervalDays,
      repetitionCount: repetitionCount ?? this.repetitionCount,
      nextReviewAt: nextReviewAt ?? this.nextReviewAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  Map<String, dynamic> toSyncJson() => {
        'id': id,
        'study_set_id': studySetId,
        'front_text': frontText,
        'back_text': backText,
        'hint': hint,
        'ease_factor': easeFactor,
        'interval_days': intervalDays,
        'repetition_count': repetitionCount,
        'next_review_at': nextReviewAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'is_deleted': isDeleted,
      };

  factory FlashcardEntity.fromSyncJson(Map<String, dynamic> json) => FlashcardEntity(
        id: json['id'] as String,
        studySetId: json['study_set_id'] as String,
        frontText: json['front_text'] as String,
        backText: json['back_text'] as String,
        hint: json['hint'] as String?,
        easeFactor: (json['ease_factor'] as num?)?.toDouble() ?? 2.5,
        intervalDays: (json['interval_days'] as num?)?.toInt() ?? 0,
        repetitionCount: (json['repetition_count'] as num?)?.toInt() ?? 0,
        nextReviewAt: DateTime.parse(json['next_review_at'] as String).toLocal(),
        updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
        isDeleted: (json['is_deleted'] as bool?) ?? false,
      );
}
