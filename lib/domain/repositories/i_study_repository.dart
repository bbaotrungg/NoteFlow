import '../entities/ai_generated_study_content.dart';
import '../entities/document_entity.dart';
import '../entities/flashcard_entity.dart';
import '../entities/quiz_question_entity.dart';
import '../entities/study_session_entity.dart';
import '../entities/study_set_entity.dart';
import '../entities/subject_entity.dart';
import '../services/sm2_spaced_repetition_service.dart';

/// Hợp đồng giao tiếp (Repository Interface) giữa Domain Layer và Data Layer
abstract class IStudyRepository {
  // Reactive Streams cho UI tự động cập nhật
  Stream<List<SubjectEntity>> watchAllSubjects();
  Stream<List<DocumentEntity>> watchDocumentsBySubject(String subjectId);
  Stream<List<StudySetEntity>> watchAllStudySets();
  Stream<StudySetEntity?> watchStudySetDetail(String studySetId);
  Stream<List<FlashcardEntity>> watchDueFlashcards();
  Stream<List<StudySessionEntity>> watchRecentSessions({int days = 7});
  Stream<int> watchPendingSyncCount();

  // CRUD Môn học
  Future<SubjectEntity> createSubject({
    required String title,
    required String code,
    required String colorHex,
  });
  Future<void> updateSubject(SubjectEntity subject);
  Future<void> softDeleteSubject(String subjectId);

  // Pipeline Tài liệu + AI Study Set
  Future<StudySetEntity> saveDocumentAndStudySet({
    required String subjectId,
    required String documentTitle,
    required DocumentFileType fileType,
    required String localFilePath,
    required String rawExtractedText,
    required AiGeneratedStudyContent generatedContent,
  });

  Future<void> updateStudySetContent({
    required StudySetEntity studySet,
    required List<FlashcardEntity> flashcards,
    required List<QuizQuestionEntity> quizQuestions,
  });

  // Ôn tập Flashcard (SuperMemo SM-2) & Quiz
  Future<FlashcardEntity> reviewFlashcard({
    required FlashcardEntity flashcard,
    required ReviewRating rating,
  });

  Future<void> recordQuizAnswer({
    required String questionId,
    required bool isCorrect,
  });

  Future<StudySessionEntity> recordStudySession({
    required String studySetId,
    required StudySessionType sessionType,
    double? score,
    required int totalItems,
    required int durationSeconds,
  });

  // Đồng bộ Offline-First
  Future<int> synchronizeWithCloud();
}
