import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noteflow_ai/data/local/database/app_database.dart';
import 'package:noteflow_ai/data/repositories/study_repository_impl.dart';
import 'package:noteflow_ai/data/sync/offline_sync_engine.dart';
import 'package:noteflow_ai/domain/services/sm2_spaced_repetition_service.dart';

void main() {
  late AppDatabase db;
  late StudyRepositoryImpl repository;
  late OfflineSyncEngine syncEngine;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    syncEngine = OfflineSyncEngine(db: db);
    repository = StudyRepositoryImpl(
      db: db,
      sm2Service: const Sm2SpacedRepetitionService(),
      syncEngine: syncEngine,
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('DATA-01: Cascade Soft-Delete & Zombie Flashcard Prevention Tests', () {
    test(
        'Soft-deleting a StudySet cascades is_deleted = 1 to all its Flashcards and Quizzes',
        () async {
      final now = DateTime.now();

      // Create a test subject and document
      await db.subjectDao.upsertSubjectRaw(
        id: 'sub-test-01',
        title: 'Mạng Máy Tính',
        code: 'NET101',
        colorHex: '#0284C7',
        updatedAt: now,
      );

      await db.studyDao.upsertDocumentRaw(
        id: 'doc-test-01',
        subjectId: 'sub-test-01',
        title: 'Chương 1: Mô hình OSI & TCP/IP',
        fileType: 'TEXT',
        localFilePath: '',
        rawExtractedText: 'OSI 7 layers',
        updatedAt: now,
      );

      // Create a study set
      await db.studyDao.upsertStudySetRaw(
        id: 'set-test-01',
        documentId: 'doc-test-01',
        title: 'Bộ thẻ Mô hình OSI',
        summaryMarkdown: '# Tóm tắt OSI',
        updatedAt: now,
      );

      // Add two flashcards for this study set
      await db.studyDao.upsertFlashcardRaw(
        id: 'fc-001',
        studySetId: 'set-test-01',
        frontText: 'Tầng 1 là gì?',
        backText: 'Physical',
        easeFactor: 2.5,
        intervalDays: 0,
        repetitionCount: 0,
        nextReviewAt: now.subtract(const Duration(hours: 1)), // Due now
        updatedAt: now,
      );

      await db.studyDao.upsertFlashcardRaw(
        id: 'fc-002',
        studySetId: 'set-test-01',
        frontText: 'Tầng 7 là gì?',
        backText: 'Application',
        easeFactor: 2.5,
        intervalDays: 0,
        repetitionCount: 0,
        nextReviewAt: now.subtract(const Duration(minutes: 30)), // Due now
        updatedAt: now,
      );

      // Add a quiz question for this study set
      await db.studyDao.upsertQuizQuestionRaw(
        id: 'qz-001',
        studySetId: 'set-test-01',
        questionText: 'Mô hình OSI có mấy tầng?',
        optionsJson: '["5", "6", "7", "4"]',
        correctIndex: 2,
        explanation: 'Mô hình OSI có 7 tầng chuẩn hóa.',
        timesAnswered: 0,
        timesCorrect: 0,
        updatedAt: now,
      );

      // Verify that prior to deletion, due flashcards include both cards
      final dueBeforeDelete = await db.studyDao.watchDueFlashcards().first;
      expect(dueBeforeDelete.any((c) => c.id == 'fc-001'), isTrue);
      expect(dueBeforeDelete.any((c) => c.id == 'fc-002'), isTrue);

      // Soft delete the study set via repository
      await repository.softDeleteStudySet('set-test-01');

      // 1. Verify StudySet itself is marked is_deleted = 1
      final deletedSet = await db.studyDao.getStudySetById('set-test-01');
      expect(deletedSet, isNotNull);
      expect(deletedSet!.isDeleted, isTrue);

      // 2. Verify child flashcards are cascade soft-deleted
      final fc1 = await db.studyDao.getFlashcardById('fc-001');
      final fc2 = await db.studyDao.getFlashcardById('fc-002');
      expect(fc1!.isDeleted, isTrue,
          reason: 'Flashcard fc-001 must be soft-deleted with parent');
      expect(fc2!.isDeleted, isTrue,
          reason: 'Flashcard fc-002 must be soft-deleted with parent');

      // 3. Verify child quiz questions are cascade soft-deleted
      final qz1 = await db.studyDao.getQuizQuestionById('qz-001');
      expect(qz1!.isDeleted, isTrue,
          reason: 'Quiz qz-001 must be soft-deleted with parent');

      // 4. Verify Zombie Flashcard Prevention: deleted cards NO LONGER appear in watchDueFlashcards
      final dueAfterDelete = await db.studyDao.watchDueFlashcards().first;
      expect(dueAfterDelete.any((c) => c.id == 'fc-001'), isFalse);
      expect(dueAfterDelete.any((c) => c.id == 'fc-002'), isFalse);

      // 5. Verify active flashcards stream excludes them as well
      final activeCards = await db.studyDao.watchAllActiveFlashcards().first;
      expect(activeCards.any((c) => c.id == 'fc-001'), isFalse);
      expect(activeCards.any((c) => c.id == 'fc-002'), isFalse);
    });

    test(
        'watchDueFlashcards excludes cards even if card is_deleted is 0 but study_set is_deleted is 1',
        () async {
      final now = DateTime.now();

      await db.subjectDao.upsertSubjectRaw(
        id: 'sub-test-02',
        title: 'Hệ Điều Hành',
        code: 'OS202',
        colorHex: '#059669',
        updatedAt: now,
      );

      await db.studyDao.upsertDocumentRaw(
        id: 'doc-test-02',
        subjectId: 'sub-test-02',
        title: 'Chương 2: Tiến trình & Luồng',
        fileType: 'TEXT',
        localFilePath: '',
        rawExtractedText: 'Processes and Threads',
        updatedAt: now,
      );

      // Create study set and mark it is_deleted = 1 directly
      await db.studyDao.upsertStudySetRaw(
        id: 'set-test-orphan',
        documentId: 'doc-test-02',
        title: 'Bộ thẻ Tiến trình (Đã xóa)',
        summaryMarkdown: '',
        updatedAt: now,
        isDeleted: true,
      );

      // Insert an orphaned card whose is_deleted flag is 0
      await db.studyDao.upsertFlashcardRaw(
        id: 'fc-orphan-01',
        studySetId: 'set-test-orphan',
        frontText: 'Deadlock là gì?',
        backText: 'Bế tắc',
        easeFactor: 2.5,
        intervalDays: 0,
        repetitionCount: 0,
        nextReviewAt: now.subtract(const Duration(hours: 2)), // Due now
        updatedAt: now,
        isDeleted: false, // Flag is not yet updated
      );

      // Query due flashcards: relational join MUST filter it out because study_set is deleted
      final dueCards = await db.studyDao.watchDueFlashcards().first;
      expect(
        dueCards.any((c) => c.id == 'fc-orphan-01'),
        isFalse,
        reason:
            'watchDueFlashcards must exclude orphaned cards belonging to deleted study sets',
      );
    });

    test(
        'Soft-deleting a Subject cascades through documents, study sets, and flashcards',
        () async {
      final now = DateTime.now();

      await db.subjectDao.upsertSubjectRaw(
        id: 'sub-cascade-01',
        title: 'Cơ sở Dữ liệu',
        code: 'DB101',
        colorHex: '#D97706',
        updatedAt: now,
      );

      await db.studyDao.upsertDocumentRaw(
        id: 'doc-cascade-01',
        subjectId: 'sub-cascade-01',
        title: 'SQL Cơ bản',
        fileType: 'TEXT',
        localFilePath: '',
        rawExtractedText: 'SELECT * FROM table',
        updatedAt: now,
      );

      await db.studyDao.upsertStudySetRaw(
        id: 'set-cascade-01',
        documentId: 'doc-cascade-01',
        title: 'Bộ thẻ SQL',
        summaryMarkdown: '',
        updatedAt: now,
      );

      await db.studyDao.upsertFlashcardRaw(
        id: 'fc-cascade-01',
        studySetId: 'set-cascade-01',
        frontText: 'Khóa chính là gì?',
        backText: 'Định danh duy nhất một bản ghi',
        easeFactor: 2.5,
        intervalDays: 0,
        repetitionCount: 0,
        nextReviewAt: now.subtract(const Duration(days: 1)),
        updatedAt: now,
      );

      // Soft delete subject via repository
      await repository.softDeleteSubject('sub-cascade-01');

      // Verify subject is soft deleted
      final subject = await db.subjectDao.getSubjectById('sub-cascade-01');
      expect(subject!.isDeleted, isTrue);

      // Verify document is soft deleted
      final doc = await db.studyDao.getDocumentById('doc-cascade-01');
      expect(doc!.isDeleted, isTrue);

      // Verify study set is soft deleted
      final set = await db.studyDao.getStudySetById('set-cascade-01');
      expect(set!.isDeleted, isTrue);

      // Verify flashcard is soft deleted
      final card = await db.studyDao.getFlashcardById('fc-cascade-01');
      expect(card!.isDeleted, isTrue);

      // Verify flashcard does not appear in due review queue
      final dueCards = await db.studyDao.watchDueFlashcards().first;
      expect(dueCards.any((c) => c.id == 'fc-cascade-01'), isFalse);
    });

    test('Repeated soft-delete is idempotent', () async {
      final now = DateTime.now();
      await db.studyDao.upsertStudySetRaw(
        id: 'set-idempotent',
        documentId: 'doc-vku-clean-arch-01',
        title: 'Idempotent Set',
        summaryMarkdown: '',
        updatedAt: now,
      );

      // Call soft delete twice
      await repository.softDeleteStudySet('set-idempotent');
      await repository.softDeleteStudySet('set-idempotent');

      final s = await db.studyDao.getStudySetById('set-idempotent');
      expect(s!.isDeleted, isTrue);
    });
  });
}
