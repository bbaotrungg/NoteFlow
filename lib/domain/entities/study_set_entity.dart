import 'flashcard_entity.dart';
import 'quiz_question_entity.dart';

/// Thực thể Bộ học liệu (STUDY_SETS) được sinh bởi AI hoặc chỉnh sửa bởi sinh viên
class StudySetEntity {
  final String id;
  final String documentId;
  final String title;
  final String summaryMarkdown;
  final DateTime updatedAt;
  final bool isDeleted;
  final List<FlashcardEntity> flashcards;
  final List<QuizQuestionEntity> quizQuestions;

  const StudySetEntity({
    required this.id,
    required this.documentId,
    required this.title,
    required this.summaryMarkdown,
    required this.updatedAt,
    this.isDeleted = false,
    this.flashcards = const [],
    this.quizQuestions = const [],
  });

  int get dueFlashcardsCount {
    final now = DateTime.now();
    return flashcards.where((f) => !f.isDeleted && !f.nextReviewAt.isAfter(now)).length;
  }

  StudySetEntity copyWith({
    String? id,
    String? documentId,
    String? title,
    String? summaryMarkdown,
    DateTime? updatedAt,
    bool? isDeleted,
    List<FlashcardEntity>? flashcards,
    List<QuizQuestionEntity>? quizQuestions,
  }) {
    return StudySetEntity(
      id: id ?? this.id,
      documentId: documentId ?? this.documentId,
      title: title ?? this.title,
      summaryMarkdown: summaryMarkdown ?? this.summaryMarkdown,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      flashcards: flashcards ?? this.flashcards,
      quizQuestions: quizQuestions ?? this.quizQuestions,
    );
  }

  Map<String, dynamic> toSyncJson() => {
        'id': id,
        'document_id': documentId,
        'title': title,
        'summary_markdown': summaryMarkdown,
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'is_deleted': isDeleted,
      };

  factory StudySetEntity.fromSyncJson(Map<String, dynamic> json) => StudySetEntity(
        id: json['id'] as String,
        documentId: json['document_id'] as String,
        title: json['title'] as String,
        summaryMarkdown: (json['summary_markdown'] as String?) ?? '',
        updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
        isDeleted: (json['is_deleted'] as bool?) ?? false,
      );
}
