import 'dart:convert';
import 'package:uuid/uuid.dart';

import '../../domain/entities/ai_generated_study_content.dart';
import '../../domain/entities/document_entity.dart';
import '../../domain/entities/flashcard_entity.dart';
import '../../domain/entities/quiz_question_entity.dart';
import '../../domain/entities/study_session_entity.dart';
import '../../domain/entities/study_set_entity.dart';
import '../../domain/entities/subject_entity.dart';
import '../../domain/entities/sync_queue_item_entity.dart';
import '../../domain/repositories/i_study_repository.dart';
import '../../domain/services/sm2_spaced_repetition_service.dart';
import '../local/database/app_database.dart';
import '../sync/offline_sync_engine.dart';

/// Hiện thực hóa IStudyRepository kết nối Drift SQLite DAOs, SuperMemo SM-2 và OfflineSyncEngine
class StudyRepositoryImpl implements IStudyRepository {
  final AppDatabase _db;
  final Sm2SpacedRepetitionService _sm2Service;
  final OfflineSyncEngine _syncEngine;
  static const _uuid = Uuid();

  StudyRepositoryImpl({
    required AppDatabase db,
    required Sm2SpacedRepetitionService sm2Service,
    required OfflineSyncEngine syncEngine,
  })  : _db = db,
        _sm2Service = sm2Service,
        _syncEngine = syncEngine;

  @override
  Stream<List<SubjectEntity>> watchAllSubjects() => _db.subjectDao.watchAllActiveSubjects();

  @override
  Stream<List<DocumentEntity>> watchDocumentsBySubject(String subjectId) =>
      _db.studyDao.watchDocumentsBySubject(subjectId);

  @override
  Stream<List<StudySetEntity>> watchAllStudySets() => _db.studyDao.watchAllStudySets();

  @override
  Stream<StudySetEntity?> watchStudySetDetail(String studySetId) =>
      _db.studyDao.watchStudySetDetail(studySetId);

  @override
  Stream<List<FlashcardEntity>> watchDueFlashcards() => _db.studyDao.watchDueFlashcards();

  @override
  Stream<List<StudySessionEntity>> watchRecentSessions({int days = 7}) =>
      _db.studyDao.watchRecentSessions(days: days);

  @override
  Stream<int> watchPendingSyncCount() => _db.syncDao.watchPendingSyncCount();

  @override
  Future<SubjectEntity> createSubject({
    required String title,
    required String code,
    required String colorHex,
  }) async {
    final now = DateTime.now();
    final subject = SubjectEntity(
      id: _uuid.v4(),
      title: title.trim(),
      code: code.trim().toUpperCase(),
      colorHex: colorHex,
      updatedAt: now,
    );

    await _db.transaction(() async {
      await _db.subjectDao.upsertSubjectRaw(
        id: subject.id,
        title: subject.title,
        code: subject.code,
        colorHex: subject.colorHex,
        updatedAt: subject.updatedAt,
      );
      await _db.syncDao.enqueueMutation(
        tableName: 'subjects',
        recordId: subject.id,
        operation: SyncOperation.insert,
        payloadJson: jsonEncode(subject.toSyncJson()),
      );
    });

    return subject;
  }

  @override
  Future<void> updateSubject(SubjectEntity subject) async {
    final updated = subject.copyWith(updatedAt: DateTime.now());
    await _db.transaction(() async {
      await _db.subjectDao.upsertSubjectRaw(
        id: updated.id,
        title: updated.title,
        code: updated.code,
        colorHex: updated.colorHex,
        updatedAt: updated.updatedAt,
        isDeleted: updated.isDeleted,
      );
      await _db.syncDao.enqueueMutation(
        tableName: 'subjects',
        recordId: updated.id,
        operation: SyncOperation.update,
        payloadJson: jsonEncode(updated.toSyncJson()),
      );
    });
  }

  @override
  Future<void> softDeleteSubject(String subjectId) async {
    final existing = await _db.subjectDao.getSubjectById(subjectId);
    if (existing == null) return;
    final now = DateTime.now();
    final deleted = existing.copyWith(isDeleted: true, updatedAt: now);

    await _db.transaction(() async {
      await _db.subjectDao.tombstoneDeleteSubject(subjectId, now);
      await _db.syncDao.enqueueMutation(
        tableName: 'subjects',
        recordId: subjectId,
        operation: SyncOperation.delete,
        payloadJson: jsonEncode(deleted.toSyncJson()),
      );
    });
  }

  @override
  Future<StudySetEntity> saveDocumentAndStudySet({
    required String subjectId,
    required String documentTitle,
    required DocumentFileType fileType,
    required String localFilePath,
    required String rawExtractedText,
    required AiGeneratedStudyContent generatedContent,
  }) async {
    final now = DateTime.now();
    final docId = _uuid.v4();
    final studySetId = _uuid.v4();

    final document = DocumentEntity(
      id: docId,
      subjectId: subjectId,
      title: documentTitle.trim(),
      fileType: fileType,
      localFilePath: localFilePath,
      rawExtractedText: rawExtractedText,
      updatedAt: now,
    );

    final flashcards = generatedContent.flashcards.map((draft) {
      return FlashcardEntity(
        id: _uuid.v4(),
        studySetId: studySetId,
        frontText: draft.front,
        backText: draft.back,
        hint: draft.hint,
        easeFactor: 2.5,
        intervalDays: 0,
        repetitionCount: 0,
        nextReviewAt: now,
        updatedAt: now,
      );
    }).toList();

    final quizQuestions = generatedContent.quiz.map((draft) {
      return QuizQuestionEntity(
        id: _uuid.v4(),
        studySetId: studySetId,
        questionText: draft.question,
        options: draft.options,
        correctIndex: draft.correctIndex,
        explanation: draft.explanation,
        updatedAt: now,
      );
    }).toList();

    final studySet = StudySetEntity(
      id: studySetId,
      documentId: docId,
      title: documentTitle.trim(),
      summaryMarkdown: generatedContent.summaryMarkdown,
      updatedAt: now,
      flashcards: flashcards,
      quizQuestions: quizQuestions,
    );

    await _db.transaction(() async {
      await _db.studyDao.upsertDocumentRaw(
        id: document.id,
        subjectId: document.subjectId,
        title: document.title,
        fileType: document.fileType.dbValue,
        localFilePath: document.localFilePath,
        rawExtractedText: document.rawExtractedText,
        updatedAt: document.updatedAt,
      );
      await _db.syncDao.enqueueMutation(
        tableName: 'documents',
        recordId: document.id,
        operation: SyncOperation.insert,
        payloadJson: jsonEncode(document.toSyncJson()),
      );

      await _db.studyDao.upsertStudySetRaw(
        id: studySet.id,
        documentId: studySet.documentId,
        title: studySet.title,
        summaryMarkdown: studySet.summaryMarkdown,
        updatedAt: studySet.updatedAt,
      );
      await _db.syncDao.enqueueMutation(
        tableName: 'study_sets',
        recordId: studySet.id,
        operation: SyncOperation.insert,
        payloadJson: jsonEncode(studySet.toSyncJson()),
      );

      for (final card in flashcards) {
        await _db.studyDao.upsertFlashcardRaw(
          id: card.id,
          studySetId: card.studySetId,
          frontText: card.frontText,
          backText: card.backText,
          hint: card.hint,
          easeFactor: card.easeFactor,
          intervalDays: card.intervalDays,
          repetitionCount: card.repetitionCount,
          nextReviewAt: card.nextReviewAt,
          updatedAt: card.updatedAt,
        );
        await _db.syncDao.enqueueMutation(
          tableName: 'flashcards',
          recordId: card.id,
          operation: SyncOperation.insert,
          payloadJson: jsonEncode(card.toSyncJson()),
        );
      }

      for (final q in quizQuestions) {
        await _db.studyDao.upsertQuizQuestionRaw(
          id: q.id,
          studySetId: q.studySetId,
          questionText: q.questionText,
          optionsJson: q.optionsJson,
          correctIndex: q.correctIndex,
          explanation: q.explanation,
          timesAnswered: q.timesAnswered,
          timesCorrect: q.timesCorrect,
          updatedAt: q.updatedAt,
        );
        await _db.syncDao.enqueueMutation(
          tableName: 'quiz_questions',
          recordId: q.id,
          operation: SyncOperation.insert,
          payloadJson: jsonEncode(q.toSyncJson()),
        );
      }
    });

    return studySet;
  }

  @override
  Future<void> updateStudySetContent({
    required StudySetEntity studySet,
    required List<FlashcardEntity> flashcards,
    required List<QuizQuestionEntity> quizQuestions,
  }) async {
    final now = DateTime.now();
    final updatedSet = studySet.copyWith(updatedAt: now);

    await _db.transaction(() async {
      await _db.studyDao.upsertStudySetRaw(
        id: updatedSet.id,
        documentId: updatedSet.documentId,
        title: updatedSet.title,
        summaryMarkdown: updatedSet.summaryMarkdown,
        updatedAt: now,
      );
      await _db.syncDao.enqueueMutation(
        tableName: 'study_sets',
        recordId: updatedSet.id,
        operation: SyncOperation.update,
        payloadJson: jsonEncode(updatedSet.toSyncJson()),
      );

      for (final card in flashcards) {
        final updatedCard = card.copyWith(updatedAt: now);
        await _db.studyDao.upsertFlashcardRaw(
          id: updatedCard.id,
          studySetId: updatedCard.studySetId,
          frontText: updatedCard.frontText,
          backText: updatedCard.backText,
          hint: updatedCard.hint,
          easeFactor: updatedCard.easeFactor,
          intervalDays: updatedCard.intervalDays,
          repetitionCount: updatedCard.repetitionCount,
          nextReviewAt: updatedCard.nextReviewAt,
          updatedAt: now,
          isDeleted: updatedCard.isDeleted,
        );
        await _db.syncDao.enqueueMutation(
          tableName: 'flashcards',
          recordId: updatedCard.id,
          operation: SyncOperation.update,
          payloadJson: jsonEncode(updatedCard.toSyncJson()),
        );
      }

      for (final q in quizQuestions) {
        final updatedQuiz = q.copyWith(updatedAt: now);
        await _db.studyDao.upsertQuizQuestionRaw(
          id: updatedQuiz.id,
          studySetId: updatedQuiz.studySetId,
          questionText: updatedQuiz.questionText,
          optionsJson: updatedQuiz.optionsJson,
          correctIndex: updatedQuiz.correctIndex,
          explanation: updatedQuiz.explanation,
          timesAnswered: updatedQuiz.timesAnswered,
          timesCorrect: updatedQuiz.timesCorrect,
          updatedAt: now,
          isDeleted: updatedQuiz.isDeleted,
        );
        await _db.syncDao.enqueueMutation(
          tableName: 'quiz_questions',
          recordId: updatedQuiz.id,
          operation: SyncOperation.update,
          payloadJson: jsonEncode(updatedQuiz.toSyncJson()),
        );
      }
    });
  }

  @override
  Future<FlashcardEntity> reviewFlashcard({
    required FlashcardEntity flashcard,
    required ReviewRating rating,
  }) async {
    final updatedCard = _sm2Service.applyReview(
      flashcard: flashcard,
      rating: rating,
    );

    await _db.transaction(() async {
      await _db.studyDao.upsertFlashcardRaw(
        id: updatedCard.id,
        studySetId: updatedCard.studySetId,
        frontText: updatedCard.frontText,
        backText: updatedCard.backText,
        hint: updatedCard.hint,
        easeFactor: updatedCard.easeFactor,
        intervalDays: updatedCard.intervalDays,
        repetitionCount: updatedCard.repetitionCount,
        nextReviewAt: updatedCard.nextReviewAt,
        updatedAt: updatedCard.updatedAt,
      );
      await _db.syncDao.enqueueMutation(
        tableName: 'flashcards',
        recordId: updatedCard.id,
        operation: SyncOperation.update,
        payloadJson: jsonEncode(updatedCard.toSyncJson()),
      );
    });

    return updatedCard;
  }

  @override
  Future<void> recordQuizAnswer({
    required String questionId,
    required bool isCorrect,
  }) async {
    final existing = await _db.studyDao.getQuizQuestionById(questionId);
    if (existing == null) return;
    final now = DateTime.now();

    final updated = existing.copyWith(
      timesAnswered: existing.timesAnswered + 1,
      timesCorrect: existing.timesCorrect + (isCorrect ? 1 : 0),
      updatedAt: now,
    );

    await _db.transaction(() async {
      await _db.studyDao.upsertQuizQuestionRaw(
        id: updated.id,
        studySetId: updated.studySetId,
        questionText: updated.questionText,
        optionsJson: updated.optionsJson,
        correctIndex: updated.correctIndex,
        explanation: updated.explanation,
        timesAnswered: updated.timesAnswered,
        timesCorrect: updated.timesCorrect,
        updatedAt: updated.updatedAt,
      );
      await _db.syncDao.enqueueMutation(
        tableName: 'quiz_questions',
        recordId: updated.id,
        operation: SyncOperation.update,
        payloadJson: jsonEncode(updated.toSyncJson()),
      );
    });
  }

  @override
  Future<StudySessionEntity> recordStudySession({
    required String studySetId,
    required StudySessionType sessionType,
    double? score,
    required int totalItems,
    required int durationSeconds,
  }) async {
    final session = StudySessionEntity(
      id: _uuid.v4(),
      studySetId: studySetId,
      sessionType: sessionType,
      score: score,
      totalItems: totalItems,
      durationSeconds: durationSeconds,
      completedAt: DateTime.now(),
    );

    await _db.transaction(() async {
      await _db.studyDao.insertStudySessionRaw(
        id: session.id,
        studySetId: session.studySetId,
        sessionType: session.sessionType.dbValue,
        score: session.score,
        totalItems: session.totalItems,
        durationSeconds: session.durationSeconds,
        completedAt: session.completedAt,
      );
      await _db.syncDao.enqueueMutation(
        tableName: 'study_sessions',
        recordId: session.id,
        operation: SyncOperation.insert,
        payloadJson: jsonEncode(session.toSyncJson()),
      );
    });

    return session;
  }

  @override
  Future<int> synchronizeWithCloud() => _syncEngine.runBidirectionalSync();
}
