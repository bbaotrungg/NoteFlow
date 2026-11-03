import 'dart:convert';
import 'package:drift/drift.dart';

import '../../../domain/entities/document_entity.dart';
import '../../../domain/entities/flashcard_entity.dart';
import '../../../domain/entities/quiz_question_entity.dart';
import '../../../domain/entities/study_session_entity.dart';
import '../../../domain/entities/study_set_entity.dart';
import '../database/app_database.dart';

/// DAO quản lý Documents, StudySets, Flashcards (SM-2), QuizQuestions và StudySessions
class StudyDao {
  final AppDatabase _db;

  StudyDao(this._db);

  Stream<List<DocumentEntity>> watchDocumentsBySubject(String subjectId) {
    return _db.customSelect(
      '''
      SELECT * FROM documents
      WHERE subject_id = ?1 AND is_deleted = 0
      ORDER BY updated_at DESC
      ''',
      variables: [Variable<String>(subjectId)],
      readsFrom: {_db.documentsTable},
    ).watch().map((rows) => rows.map(_mapDocumentRow).toList());
  }

  Stream<List<StudySetEntity>> watchAllStudySets() {
    return _db.customSelect(
      'SELECT * FROM study_sets WHERE is_deleted = 0 ORDER BY updated_at DESC',
      readsFrom: {
        _db.studySetsTable,
        _db.flashcardsTable,
        _db.quizQuestionsTable,
      },
    ).watch().asyncMap((rows) async {
      final result = <StudySetEntity>[];
      for (final row in rows) {
        final id = row.read<String>('id');
        final cards = await getFlashcardsByStudySet(id);
        final quizzes = await getQuizQuestionsByStudySet(id);
        result.add(
          StudySetEntity(
            id: id,
            documentId: row.read<String>('document_id'),
            title: row.read<String>('title'),
            summaryMarkdown: row.read<String>('summary_markdown'),
            updatedAt: DateTime.fromMillisecondsSinceEpoch(row.read<int>('updated_at')),
            isDeleted: row.read<int>('is_deleted') == 1,
            flashcards: cards,
            quizQuestions: quizzes,
          ),
        );
      }
      return result;
    });
  }

  Stream<StudySetEntity?> watchStudySetDetail(String studySetId) {
    return _db.customSelect(
      'SELECT * FROM study_sets WHERE id = ?1 AND is_deleted = 0 LIMIT 1',
      variables: [Variable<String>(studySetId)],
      readsFrom: {
        _db.studySetsTable,
        _db.flashcardsTable,
        _db.quizQuestionsTable,
      },
    ).watch().asyncMap((rows) async {
      if (rows.isEmpty) return null;
      final row = rows.first;
      final cards = await getFlashcardsByStudySet(studySetId);
      final quizzes = await getQuizQuestionsByStudySet(studySetId);
      return StudySetEntity(
        id: studySetId,
        documentId: row.read<String>('document_id'),
        title: row.read<String>('title'),
        summaryMarkdown: row.read<String>('summary_markdown'),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(row.read<int>('updated_at')),
        isDeleted: row.read<int>('is_deleted') == 1,
        flashcards: cards,
        quizQuestions: quizzes,
      );
    });
  }

  /// Danh sách các thẻ Flashcard cần ôn tập (next_review_at <= now), ưu tiên thẻ khó (ease_factor thấp)
  Stream<List<FlashcardEntity>> watchDueFlashcards() {
    return _db.customSelect(
      '''
      SELECT * FROM flashcards
      WHERE is_deleted = 0
      ORDER BY next_review_at ASC, ease_factor ASC
      ''',
      readsFrom: {_db.flashcardsTable},
    ).watch().map((rows) {
      final now = DateTime.now();
      final allCards = rows.map(_mapFlashcardRow).toList();
      final due = allCards.where((c) => !c.nextReviewAt.isAfter(now)).toList();
      return due.isNotEmpty ? due : allCards;
    });
  }

  Stream<List<StudySessionEntity>> watchRecentSessions({int days = 7}) {
    final cutoffMs = DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;
    return _db.customSelect(
      '''
      SELECT * FROM study_sessions
      WHERE completed_at >= ?1
      ORDER BY completed_at ASC
      ''',
      variables: [Variable<int>(cutoffMs)],
      readsFrom: {_db.studySessionsTable},
    ).watch().map((rows) => rows.map(_mapSessionRow).toList());
  }

  Future<List<FlashcardEntity>> getFlashcardsByStudySet(String studySetId) async {
    final rows = await _db.customSelect(
      '''
      SELECT * FROM flashcards
      WHERE study_set_id = ?1 AND is_deleted = 0
      ORDER BY next_review_at ASC
      ''',
      variables: [Variable<String>(studySetId)],
      readsFrom: {_db.flashcardsTable},
    ).get();
    return rows.map(_mapFlashcardRow).toList();
  }

  Future<List<QuizQuestionEntity>> getQuizQuestionsByStudySet(String studySetId) async {
    final rows = await _db.customSelect(
      '''
      SELECT * FROM quiz_questions
      WHERE study_set_id = ?1 AND is_deleted = 0
      ORDER BY id ASC
      ''',
      variables: [Variable<String>(studySetId)],
      readsFrom: {_db.quizQuestionsTable},
    ).get();
    return rows.map(_mapQuizRow).toList();
  }

  Future<DocumentEntity?> getDocumentById(String id) async {
    final rows = await _db.customSelect(
      'SELECT * FROM documents WHERE id = ?1 LIMIT 1',
      variables: [Variable<String>(id)],
      readsFrom: {_db.documentsTable},
    ).get();
    if (rows.isEmpty) return null;
    return _mapDocumentRow(rows.first);
  }

  Future<StudySetEntity?> getStudySetById(String id) async {
    final rows = await _db.customSelect(
      'SELECT * FROM study_sets WHERE id = ?1 LIMIT 1',
      variables: [Variable<String>(id)],
      readsFrom: {_db.studySetsTable},
    ).get();
    if (rows.isEmpty) return null;
    final row = rows.first;
    return StudySetEntity(
      id: row.read<String>('id'),
      documentId: row.read<String>('document_id'),
      title: row.read<String>('title'),
      summaryMarkdown: row.read<String>('summary_markdown'),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row.read<int>('updated_at')),
      isDeleted: row.read<int>('is_deleted') == 1,
    );
  }

  Future<FlashcardEntity?> getFlashcardById(String id) async {
    final rows = await _db.customSelect(
      'SELECT * FROM flashcards WHERE id = ?1 LIMIT 1',
      variables: [Variable<String>(id)],
      readsFrom: {_db.flashcardsTable},
    ).get();
    if (rows.isEmpty) return null;
    return _mapFlashcardRow(rows.first);
  }

  Future<QuizQuestionEntity?> getQuizQuestionById(String id) async {
    final rows = await _db.customSelect(
      'SELECT * FROM quiz_questions WHERE id = ?1 LIMIT 1',
      variables: [Variable<String>(id)],
      readsFrom: {_db.quizQuestionsTable},
    ).get();
    if (rows.isEmpty) return null;
    return _mapQuizRow(rows.first);
  }

  Future<void> upsertDocumentRaw({
    required String id,
    required String subjectId,
    required String title,
    required String fileType,
    required String localFilePath,
    required String rawExtractedText,
    required DateTime updatedAt,
    bool isDeleted = false,
  }) async {
    await _db.customInsert(
      '''
      INSERT INTO documents (
        id, subject_id, title, file_type, local_file_path, raw_extracted_text, updated_at, is_deleted
      ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
      ON CONFLICT(id) DO UPDATE SET
        subject_id = excluded.subject_id,
        title = excluded.title,
        file_type = excluded.file_type,
        local_file_path = excluded.local_file_path,
        raw_extracted_text = excluded.raw_extracted_text,
        updated_at = excluded.updated_at,
        is_deleted = excluded.is_deleted
      ''',
      variables: [
        Variable<String>(id),
        Variable<String>(subjectId),
        Variable<String>(title),
        Variable<String>(fileType),
        Variable<String>(localFilePath),
        Variable<String>(rawExtractedText),
        Variable<int>(updatedAt.millisecondsSinceEpoch),
        Variable<int>(isDeleted ? 1 : 0),
      ],
      updates: {_db.documentsTable},
    );
  }

  Future<void> upsertStudySetRaw({
    required String id,
    required String documentId,
    required String title,
    required String summaryMarkdown,
    required DateTime updatedAt,
    bool isDeleted = false,
  }) async {
    await _db.customInsert(
      '''
      INSERT INTO study_sets (
        id, document_id, title, summary_markdown, updated_at, is_deleted
      ) VALUES (?1, ?2, ?3, ?4, ?5, ?6)
      ON CONFLICT(id) DO UPDATE SET
        document_id = excluded.document_id,
        title = excluded.title,
        summary_markdown = excluded.summary_markdown,
        updated_at = excluded.updated_at,
        is_deleted = excluded.is_deleted
      ''',
      variables: [
        Variable<String>(id),
        Variable<String>(documentId),
        Variable<String>(title),
        Variable<String>(summaryMarkdown),
        Variable<int>(updatedAt.millisecondsSinceEpoch),
        Variable<int>(isDeleted ? 1 : 0),
      ],
      updates: {_db.studySetsTable},
    );
  }

  Future<void> upsertFlashcardRaw({
    required String id,
    required String studySetId,
    required String frontText,
    required String backText,
    String? hint,
    required double easeFactor,
    required int intervalDays,
    required int repetitionCount,
    required DateTime nextReviewAt,
    required DateTime updatedAt,
    bool isDeleted = false,
  }) async {
    await _db.customInsert(
      '''
      INSERT INTO flashcards (
        id, study_set_id, front_text, back_text, hint, ease_factor,
        interval_days, repetition_count, next_review_at, updated_at, is_deleted
      ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)
      ON CONFLICT(id) DO UPDATE SET
        study_set_id = excluded.study_set_id,
        front_text = excluded.front_text,
        back_text = excluded.back_text,
        hint = excluded.hint,
        ease_factor = excluded.ease_factor,
        interval_days = excluded.interval_days,
        repetition_count = excluded.repetition_count,
        next_review_at = excluded.next_review_at,
        updated_at = excluded.updated_at,
        is_deleted = excluded.is_deleted
      ''',
      variables: [
        Variable<String>(id),
        Variable<String>(studySetId),
        Variable<String>(frontText),
        Variable<String>(backText),
        Variable<String>(hint),
        Variable<double>(easeFactor),
        Variable<int>(intervalDays),
        Variable<int>(repetitionCount),
        Variable<int>(nextReviewAt.millisecondsSinceEpoch),
        Variable<int>(updatedAt.millisecondsSinceEpoch),
        Variable<int>(isDeleted ? 1 : 0),
      ],
      updates: {_db.flashcardsTable},
    );
  }

  Future<void> upsertQuizQuestionRaw({
    required String id,
    required String studySetId,
    required String questionText,
    required String optionsJson,
    required int correctIndex,
    required String explanation,
    required int timesAnswered,
    required int timesCorrect,
    required DateTime updatedAt,
    bool isDeleted = false,
  }) async {
    await _db.customInsert(
      '''
      INSERT INTO quiz_questions (
        id, study_set_id, question_text, options_json, correct_index,
        explanation, times_answered, times_correct, updated_at, is_deleted
      ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)
      ON CONFLICT(id) DO UPDATE SET
        study_set_id = excluded.study_set_id,
        question_text = excluded.question_text,
        options_json = excluded.options_json,
        correct_index = excluded.correct_index,
        explanation = excluded.explanation,
        times_answered = excluded.times_answered,
        times_correct = excluded.times_correct,
        updated_at = excluded.updated_at,
        is_deleted = excluded.is_deleted
      ''',
      variables: [
        Variable<String>(id),
        Variable<String>(studySetId),
        Variable<String>(questionText),
        Variable<String>(optionsJson),
        Variable<int>(correctIndex),
        Variable<String>(explanation),
        Variable<int>(timesAnswered),
        Variable<int>(timesCorrect),
        Variable<int>(updatedAt.millisecondsSinceEpoch),
        Variable<int>(isDeleted ? 1 : 0),
      ],
      updates: {_db.quizQuestionsTable},
    );
  }

  Future<void> insertStudySessionRaw({
    required String id,
    required String studySetId,
    required String sessionType,
    double? score,
    required int totalItems,
    required int durationSeconds,
    required DateTime completedAt,
  }) async {
    await _db.customInsert(
      '''
      INSERT OR REPLACE INTO study_sessions (
        id, study_set_id, session_type, score, total_items, duration_seconds, completed_at
      ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
      ''',
      variables: [
        Variable<String>(id),
        Variable<String>(studySetId),
        Variable<String>(sessionType),
        Variable<double>(score),
        Variable<int>(totalItems),
        Variable<int>(durationSeconds),
        Variable<int>(completedAt.millisecondsSinceEpoch),
      ],
      updates: {_db.studySessionsTable},
    );
  }

  DocumentEntity _mapDocumentRow(QueryRow row) {
    return DocumentEntity(
      id: row.read<String>('id'),
      subjectId: row.read<String>('subject_id'),
      title: row.read<String>('title'),
      fileType: DocumentFileType.fromString(row.read<String>('file_type')),
      localFilePath: row.read<String>('local_file_path'),
      rawExtractedText: row.read<String>('raw_extracted_text'),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row.read<int>('updated_at')),
      isDeleted: row.read<int>('is_deleted') == 1,
    );
  }

  FlashcardEntity _mapFlashcardRow(QueryRow row) {
    return FlashcardEntity(
      id: row.read<String>('id'),
      studySetId: row.read<String>('study_set_id'),
      frontText: row.read<String>('front_text'),
      backText: row.read<String>('back_text'),
      hint: row.readNullable<String>('hint'),
      easeFactor: row.read<double>('ease_factor'),
      intervalDays: row.read<int>('interval_days'),
      repetitionCount: row.read<int>('repetition_count'),
      nextReviewAt: DateTime.fromMillisecondsSinceEpoch(row.read<int>('next_review_at')),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row.read<int>('updated_at')),
      isDeleted: row.read<int>('is_deleted') == 1,
    );
  }

  QuizQuestionEntity _mapQuizRow(QueryRow row) {
    final rawJson = row.read<String>('options_json');
    final options = (jsonDecode(rawJson) as List<dynamic>).map((e) => e.toString()).toList();
    return QuizQuestionEntity(
      id: row.read<String>('id'),
      studySetId: row.read<String>('study_set_id'),
      questionText: row.read<String>('question_text'),
      options: options,
      correctIndex: row.read<int>('correct_index'),
      explanation: row.read<String>('explanation'),
      timesAnswered: row.read<int>('times_answered'),
      timesCorrect: row.read<int>('times_correct'),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row.read<int>('updated_at')),
      isDeleted: row.read<int>('is_deleted') == 1,
    );
  }

  StudySessionEntity _mapSessionRow(QueryRow row) {
    return StudySessionEntity(
      id: row.read<String>('id'),
      studySetId: row.read<String>('study_set_id'),
      sessionType: StudySessionType.fromString(row.read<String>('session_type')),
      score: row.readNullable<double>('score'),
      totalItems: row.read<int>('total_items'),
      durationSeconds: row.read<int>('duration_seconds'),
      completedAt: DateTime.fromMillisecondsSinceEpoch(row.read<int>('completed_at')),
    );
  }
}
