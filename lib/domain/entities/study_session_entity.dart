enum StudySessionType {
  flashcard('FLASHCARD'),
  quiz('QUIZ');

  final String dbValue;
  const StudySessionType(this.dbValue);

  static StudySessionType fromString(String value) {
    return StudySessionType.values.firstWhere(
      (e) => e.dbValue.toUpperCase() == value.toUpperCase(),
      orElse: () => StudySessionType.flashcard,
    );
  }
}

/// Thực thể Phiên học tập (STUDY_SESSIONS) lưu lịch sử ôn tập
class StudySessionEntity {
  final String id;
  final String studySetId;
  final StudySessionType sessionType;
  final double? score;
  final int totalItems;
  final int durationSeconds;
  final DateTime completedAt;

  const StudySessionEntity({
    required this.id,
    required this.studySetId,
    required this.sessionType,
    this.score,
    required this.totalItems,
    required this.durationSeconds,
    required this.completedAt,
  });

  Map<String, dynamic> toSyncJson() => {
        'id': id,
        'study_set_id': studySetId,
        'session_type': sessionType.dbValue,
        'score': score,
        'total_items': totalItems,
        'duration_seconds': durationSeconds,
        'completed_at': completedAt.toUtc().toIso8601String(),
      };

  factory StudySessionEntity.fromSyncJson(Map<String, dynamic> json) => StudySessionEntity(
        id: json['id'] as String,
        studySetId: json['study_set_id'] as String,
        sessionType: StudySessionType.fromString(json['session_type'] as String? ?? 'FLASHCARD'),
        score: (json['score'] as num?)?.toDouble(),
        totalItems: (json['total_items'] as num?)?.toInt() ?? 0,
        durationSeconds: (json['duration_seconds'] as num?)?.toInt() ?? 0,
        completedAt: DateTime.parse(json['completed_at'] as String).toLocal(),
      );
}
