import 'dart:convert';

/// Thực thể Câu hỏi trắc nghiệm (QUIZ_QUESTIONS)
class QuizQuestionEntity {
  final String id;
  final String studySetId;
  final String questionText;
  final List<String> options;
  final int correctIndex;
  final String explanation;
  final int timesAnswered;
  final int timesCorrect;
  final DateTime updatedAt;
  final bool isDeleted;

  const QuizQuestionEntity({
    required this.id,
    required this.studySetId,
    required this.questionText,
    required this.options,
    required this.correctIndex,
    required this.explanation,
    this.timesAnswered = 0,
    this.timesCorrect = 0,
    required this.updatedAt,
    this.isDeleted = false,
  });

  double get accuracyRate => timesAnswered == 0 ? 0.0 : timesCorrect / timesAnswered;

  String get optionsJson => jsonEncode(options);

  QuizQuestionEntity copyWith({
    String? id,
    String? studySetId,
    String? questionText,
    List<String>? options,
    int? correctIndex,
    String? explanation,
    int? timesAnswered,
    int? timesCorrect,
    DateTime? updatedAt,
    bool? isDeleted,
  }) {
    return QuizQuestionEntity(
      id: id ?? this.id,
      studySetId: studySetId ?? this.studySetId,
      questionText: questionText ?? this.questionText,
      options: options ?? this.options,
      correctIndex: correctIndex ?? this.correctIndex,
      explanation: explanation ?? this.explanation,
      timesAnswered: timesAnswered ?? this.timesAnswered,
      timesCorrect: timesCorrect ?? this.timesCorrect,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  Map<String, dynamic> toSyncJson() => {
        'id': id,
        'study_set_id': studySetId,
        'question_text': questionText,
        'options_json': optionsJson,
        'correct_index': correctIndex,
        'explanation': explanation,
        'times_answered': timesAnswered,
        'times_correct': timesCorrect,
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'is_deleted': isDeleted,
      };

  factory QuizQuestionEntity.fromSyncJson(Map<String, dynamic> json) {
    final rawOptions = json['options_json'] as String? ?? '[]';
    final decoded = (jsonDecode(rawOptions) as List<dynamic>).map((e) => e.toString()).toList();
    return QuizQuestionEntity(
      id: json['id'] as String,
      studySetId: json['study_set_id'] as String,
      questionText: json['question_text'] as String,
      options: decoded,
      correctIndex: (json['correct_index'] as num?)?.toInt() ?? 0,
      explanation: (json['explanation'] as String?) ?? '',
      timesAnswered: (json['times_answered'] as num?)?.toInt() ?? 0,
      timesCorrect: (json['times_correct'] as num?)?.toInt() ?? 0,
      updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
      isDeleted: (json['is_deleted'] as bool?) ?? false,
    );
  }
}
