import 'ai_generated_study_content.dart';

enum StudyAssistantRole {
  user,
  assistant,
  system,
}

/// Thực thể Tin nhắn Trợ lý Học tập AI (AI Study Assistant)
class StudyAssistantMessage {
  final String id;
  final String? studySetId;
  final StudyAssistantRole role;
  final String content;
  final DateTime timestamp;
  final List<String> references;
  final List<String> suggestedActions;
  final List<AiGeneratedFlashcardDraft> practiceFlashcards;
  final List<AiGeneratedQuizDraft> practiceQuizzes;
  final bool isError;
  final String? errorMessage;
  final bool isOfflineFallback;

  const StudyAssistantMessage({
    required this.id,
    this.studySetId,
    required this.role,
    required this.content,
    required this.timestamp,
    this.references = const [],
    this.suggestedActions = const [],
    this.practiceFlashcards = const [],
    this.practiceQuizzes = const [],
    this.isError = false,
    this.errorMessage,
    this.isOfflineFallback = false,
  });

  bool get isUser => role == StudyAssistantRole.user;
  bool get isAssistant => role == StudyAssistantRole.assistant;
  bool get isSystem => role == StudyAssistantRole.system;

  bool get hasPracticeItems =>
      practiceFlashcards.isNotEmpty || practiceQuizzes.isNotEmpty;

  StudyAssistantMessage copyWith({
    String? id,
    String? studySetId,
    StudyAssistantRole? role,
    String? content,
    DateTime? timestamp,
    List<String>? references,
    List<String>? suggestedActions,
    List<AiGeneratedFlashcardDraft>? practiceFlashcards,
    List<AiGeneratedQuizDraft>? practiceQuizzes,
    bool? isError,
    String? errorMessage,
    bool? isOfflineFallback,
  }) {
    return StudyAssistantMessage(
      id: id ?? this.id,
      studySetId: studySetId ?? this.studySetId,
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      references: references ?? this.references,
      suggestedActions: suggestedActions ?? this.suggestedActions,
      practiceFlashcards: practiceFlashcards ?? this.practiceFlashcards,
      practiceQuizzes: practiceQuizzes ?? this.practiceQuizzes,
      isError: isError ?? this.isError,
      errorMessage: errorMessage ?? this.errorMessage,
      isOfflineFallback: isOfflineFallback ?? this.isOfflineFallback,
    );
  }
}
