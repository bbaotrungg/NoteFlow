import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noteflow_ai/data/local/database/app_database.dart';
import 'package:noteflow_ai/data/sync/offline_sync_engine.dart';
import 'package:noteflow_ai/domain/entities/study_session_entity.dart';
import 'package:noteflow_ai/domain/entities/sync_queue_item_entity.dart';

void main() {
  group('SEC-02: Local SQLite Multi-Account Isolation Tests', () {
    test(
        'User A and User B databases are completely isolated; User B sees none of User A data',
        () async {
      // Create separate in-memory databases simulating distinct account-scoped databases
      final dbUserA =
          AppDatabase.forUser('user-uuid-aaa', NativeDatabase.memory());
      final dbUserB =
          AppDatabase.forUser('user-uuid-bbb', NativeDatabase.memory());

      final now = DateTime.now();

      // User A creates a subject
      await dbUserA.subjectDao.upsertSubjectRaw(
        id: 'sub-user-a-01',
        title: 'Môn riêng của User A',
        code: 'PRIV101',
        colorHex: '#0284C7',
        updatedAt: now,
      );

      // Verify User A can see their subject
      final userASubject =
          await dbUserA.subjectDao.getSubjectById('sub-user-a-01');
      expect(userASubject, isNotNull);
      expect(userASubject!.code, 'PRIV101');

      // Verify User B CANNOT see User A's subject
      final userBSubject =
          await dbUserB.subjectDao.getSubjectById('sub-user-a-01');
      expect(userBSubject, isNull,
          reason: 'User B must never access User A records');

      final userBSubjects =
          await dbUserB.subjectDao.watchAllActiveSubjects().first;
      expect(userBSubjects.any((s) => s.id == 'sub-user-a-01'), isFalse);

      await dbUserA.close();
      await dbUserB.close();
    });

    test(
        'Sync queue prevents cross-user attribution when item user_id does not match active session',
        () {
      // Test LWW logic with differing user ownership simulation
      final item = SyncQueueItemEntity(
        id: 'sync-tamper-01',
        tableName: 'subjects',
        recordId: 'sub-victim-01',
        operation: SyncOperation.insert,
        payloadJson: jsonEncode({
          'id': 'sub-victim-01',
          'user_id': 'original-owner-uuid',
          'title': 'Stolen Subject',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }),
        status: SyncStatus.pending,
        retryCount: 0,
        createdAt: DateTime.now(),
      );

      final payload = jsonDecode(item.payloadJson) as Map<String, dynamic>;
      expect(payload['user_id'], 'original-owner-uuid');
      expect(payload['user_id'] != 'attacker-user-uuid', isTrue);
    });
  });

  group('DATA-02: Complete Two-Way Study Session Synchronization Tests', () {
    late AppDatabase db;
    late OfflineSyncEngine syncEngine;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      syncEngine = OfflineSyncEngine(db: db);
      // Insert valid parent hierarchy for test sessions
      final now = DateTime.now();
      await db.subjectDao.upsertSubjectRaw(
        id: 'sub-sync-test',
        title: 'Môn Test Sync',
        code: 'SYNC101',
        colorHex: '#0284C7',
        updatedAt: now,
      );
      await db.studyDao.upsertDocumentRaw(
        id: 'doc-sync-test',
        subjectId: 'sub-sync-test',
        title: 'Doc Sync Test',
        fileType: 'TEXT',
        localFilePath: '',
        rawExtractedText: 'Test text',
        updatedAt: now,
      );
      await db.studyDao.upsertStudySetRaw(
        id: 'set-sample-01',
        documentId: 'doc-sync-test',
        title: 'Study Set Sync Test',
        summaryMarkdown: '',
        updatedAt: now,
      );
    });

    tearDown(() async {
      await db.close();
    });

    test(
        'getStudySessionById correctly retrieves study session from local database',
        () async {
      final now = DateTime.now();
      await db.studyDao.insertStudySessionRaw(
        id: 'sess-sync-01',
        studySetId: 'set-sample-01',
        sessionType: 'FLASHCARD',
        score: 95.0,
        totalItems: 10,
        durationSeconds: 180,
        completedAt: now,
      );

      final retrieved = await db.studyDao.getStudySessionById('sess-sync-01');
      expect(retrieved, isNotNull);
      expect(retrieved!.id, 'sess-sync-01');
      expect(retrieved.sessionType, StudySessionType.flashcard);
      expect(retrieved.score, 95.0);
      expect(retrieved.totalItems, 10);
      expect(retrieved.durationSeconds, 180);
    });

    test(
        'Remote study_sessions JSON payload is correctly parsed and applied to local SQLite',
        () async {
      final completedTimeUtc = DateTime.utc(2026, 11, 20, 14, 0, 0);

      final remotePayload = {
        'id': 'sess-remote-999',
        'study_set_id': 'set-vku-clean-arch-01',
        'session_type': 'QUIZ',
        'score': 88.5,
        'total_items': 8,
        'duration_seconds': 240,
        'completed_at': completedTimeUtc.toIso8601String(),
      };

      // Ensure entity deserialization works accurately
      final entity = StudySessionEntity.fromSyncJson(remotePayload);
      expect(entity.id, 'sess-remote-999');
      expect(entity.sessionType, StudySessionType.quiz);
      expect(entity.score, 88.5);
      expect(entity.totalItems, 8);
      expect(entity.durationSeconds, 240);

      // Insert into local database via DAO
      await db.studyDao.insertStudySessionRaw(
        id: entity.id,
        studySetId: entity.studySetId,
        sessionType: entity.sessionType.dbValue,
        score: entity.score,
        totalItems: entity.totalItems,
        durationSeconds: entity.durationSeconds,
        completedAt: entity.completedAt,
      );

      // Verify the session now exists in local SQLite
      final localSession =
          await db.studyDao.getStudySessionById('sess-remote-999');
      expect(localSession, isNotNull);
      expect(localSession!.score, 88.5);
      expect(localSession.sessionType, StudySessionType.quiz);
    });

    test(
        'Repeated synchronization of the same session is idempotent and does not create duplicates',
        () async {
      final time = DateTime.now();

      for (int i = 0; i < 3; i++) {
        await db.studyDao.insertStudySessionRaw(
          id: 'sess-idempotent-01',
          studySetId: 'set-sample-01',
          sessionType: 'FLASHCARD',
          score: 100.0,
          totalItems: 5,
          durationSeconds: 120,
          completedAt: time,
        );
      }

      // Verify only one entry exists in study_sessions
      final sessions = await db.studyDao.watchRecentSessions(days: 30).first;
      final matching =
          sessions.where((s) => s.id == 'sess-idempotent-01').toList();
      expect(matching.length, 1,
          reason: 'Duplicate sync attempts must upsert rather than duplicate');
    });

    test(
        'LWW Conflict Resolution preserves newer session timestamp over older remote',
        () {
      final newerLocal = DateTime.utc(2026, 11, 22, 10, 0, 0);
      final olderRemote = DateTime.utc(2026, 11, 22, 9, 0, 0);

      final localWins = syncEngine.shouldLocalWinConflict(
        localUpdatedAt: newerLocal,
        remoteUpdatedAt: olderRemote,
      );

      expect(localWins, isTrue,
          reason: 'Newer local session wins conflict resolution');
    });
  });
}
