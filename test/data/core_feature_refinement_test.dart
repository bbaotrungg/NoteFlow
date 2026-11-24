import 'dart:convert';
import 'dart:ui';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noteflow_ai/data/local/database/app_database.dart';
import 'package:noteflow_ai/data/services/ocr_spatial_clustering_service.dart';
import 'package:noteflow_ai/domain/entities/ai_generated_study_content.dart';
import 'package:noteflow_ai/domain/entities/ocr_result_entity.dart';
import 'package:noteflow_ai/domain/entities/sync_queue_item_entity.dart';
import 'package:noteflow_ai/domain/services/sm2_spaced_repetition_service.dart';
import 'package:noteflow_ai/data/sync/offline_sync_engine.dart';

class _FakeOnlineConnectivity extends Fake implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      Stream.value([ConnectivityResult.wifi]);
}

void main() {
  group('FEAT-OCR: Spatial Column Segmentation with Spanning Headers', () {
    final ocrService = OcrSpatialClusteringService();

    test(
        'Empty element list returns empty structured text without throwing exception',
        () {
      final result = ocrService.clusterSpatialElements(elements: []);
      expect(result.structuredText, isEmpty);
      expect(result.clusteredRows, isEmpty);
      expect(result.detectedColumnsCount, 1);
    });

    test(
        'Spanning header line at top correctly segments columns: Title -> Left Column -> Right Column',
        () {
      // Elements simulating a paper with a centered full-width title at top and 2-column text below
      final elements = [
        // Spanning title (width = 460 on a 500-wide page)
        const SpatialTextElement(
          text: 'Chương 5: Lập trình Đa luồng trong Dart 3',
          boundingBox: Rect.fromLTWH(20, 20, 460, 30),
        ),
        // Left Column (X ~ 20..200)
        const SpatialTextElement(
          text: '1. Isolates và Event Loop',
          boundingBox: Rect.fromLTWH(20, 70, 180, 24),
        ),
        const SpatialTextElement(
          text: 'Bộ nhớ cô lập giữa các luồng.',
          boundingBox: Rect.fromLTWH(20, 105, 180, 24),
        ),
        // Right Column (X ~ 300..480)
        const SpatialTextElement(
          text: '2. Microtask Queue',
          boundingBox: Rect.fromLTWH(300, 72, 180, 24),
        ),
        const SpatialTextElement(
          text: 'Ưu tiên chạy trước Event Queue.',
          boundingBox: Rect.fromLTWH(300, 107, 180, 24),
        ),
      ];

      final result = ocrService.clusterSpatialElements(elements: elements);

      expect(result.detectedColumnsCount,
          3); // Header section + Left col + Right col
      expect(result.clusteredRows.length, 5);

      // Verify strict reading order: Title -> Left Col 1 -> Left Col 2 -> Right Col 1 -> Right Col 2
      expect(result.clusteredRows[0].reconstructedLine,
          'Chương 5: Lập trình Đa luồng trong Dart 3');
      expect(result.clusteredRows[1].reconstructedLine,
          '1. Isolates và Event Loop');
      expect(result.clusteredRows[2].reconstructedLine,
          'Bộ nhớ cô lập giữa các luồng.');
      expect(result.clusteredRows[3].reconstructedLine, '2. Microtask Queue');
      expect(result.clusteredRows[4].reconstructedLine,
          'Ưu tiên chạy trước Event Queue.');
    });
  });

  group('FEAT-AI: JSON Sanitization, Boundary Checks & Deduplication', () {
    test('Deduplicates flashcards with identical front text', () {
      final json = {
        'summary': 'Tóm tắt bài học',
        'flashcards': [
          {
            'front': 'Isolate là gì?',
            'back': 'Đơn vị thực thi độc lập với bộ nhớ riêng.'
          },
          {
            'front': 'isolate là gì?',
            'back': 'Bản sao lặp lại không mong muốn từ AI.'
          },
          {
            'front': 'Event Loop là gì?',
            'back': 'Vòng lặp sự kiện điều phối luồng.'
          },
        ],
        'quiz': [],
      };

      final content = AiGeneratedStudyContent.fromJson(json);

      expect(content.flashcards.length, 2);
      expect(content.flashcards[0].front, 'Isolate là gì?');
      expect(content.flashcards[1].front, 'Event Loop là gì?');
    });

    test('Deduplicates quiz questions with identical question text', () {
      final json = {
        'summary': 'Tóm tắt',
        'flashcards': [],
        'quiz': [
          {
            'question': 'Isolate có chia sẻ bộ nhớ không?',
            'options': ['Không', 'Có', 'Tùy cấu hình', 'Chỉ trên Web'],
            'correct_index': 0,
            'explanation': 'Isolate không dùng chung heap bộ nhớ.',
          },
          {
            'question': 'isolate có chia sẻ bộ nhớ không?',
            'options': ['Không', 'Có', 'Luôn luôn', 'Không rõ'],
            'correct_index': 0,
            'explanation': 'Trùng lặp từ AI.',
          },
        ],
      };

      final content = AiGeneratedStudyContent.fromJson(json);

      expect(content.quiz.length, 1);
      expect(content.quiz.first.question, 'Isolate có chia sẻ bộ nhớ không?');
    });

    test(
        'AiGeneratedQuizDraft pads options to 4 and clamps correct_index within bounds',
        () {
      final json = {
        'question': 'Dart là ngôn ngữ gì?',
        'options': ['Đơn luồng với Event Loop', 'Đa luồng dùng chung bộ nhớ'],
        'correct_index': 8, // Out of range from malformed AI output
        'explanation': 'Dart xử lý đơn luồng theo mặc định.',
      };

      final draft = AiGeneratedQuizDraft.fromJson(json);

      expect(draft.options.length, 4);
      expect(draft.correctIndex, 3); // Clamped to 3
    });
  });

  group('FEAT-SM2: Cognitive Science Retention Curve Stability', () {
    const sm2Service = Sm2SpacedRepetitionService();

    test(
        'predictRetentionProbability returns 1.0 at day 0 and decays monotonically',
        () {
      final r0 = sm2Service.predictRetentionProbability(
        daysElapsed: 0,
        easeFactor: 2.5,
        intervalDays: 6,
        repetitionCount: 2,
      );
      final r1 = sm2Service.predictRetentionProbability(
        daysElapsed: 1,
        easeFactor: 2.5,
        intervalDays: 6,
        repetitionCount: 2,
      );
      final r7 = sm2Service.predictRetentionProbability(
        daysElapsed: 7,
        easeFactor: 2.5,
        intervalDays: 6,
        repetitionCount: 2,
      );
      final r14 = sm2Service.predictRetentionProbability(
        daysElapsed: 14,
        easeFactor: 2.5,
        intervalDays: 6,
        repetitionCount: 2,
      );

      expect(r0, 1.0);
      expect(r1 < r0, isTrue);
      expect(r7 < r1, isTrue);
      expect(r14 < r7, isTrue);
      expect(r14 >= 0.05, isTrue); // Clamped minimum boundary
    });
  });

  group('FEAT-DASH & DATA: Session Filtering and Metric Consistency', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test(
        'watchRecentSessions excludes study sessions belonging to soft-deleted study sets',
        () async {
      final now = DateTime.now();

      // Setup Subject & Document
      await db.subjectDao.upsertSubjectRaw(
        id: 'sub-dash-01',
        title: 'Hệ Điều Hành',
        code: 'OS201',
        colorHex: '#0284C7',
        updatedAt: now,
      );

      await db.studyDao.upsertDocumentRaw(
        id: 'doc-dash-01',
        subjectId: 'sub-dash-01',
        title: 'Chương 2: Tiến trình & Luồng',
        fileType: 'TEXT',
        localFilePath: '',
        rawExtractedText: 'Processes and Threads',
        updatedAt: now,
      );

      // Setup 2 Study Sets: Set A (active) and Set B (to be deleted)
      await db.studyDao.upsertStudySetRaw(
        id: 'set-active',
        documentId: 'doc-dash-01',
        title: 'Bộ học liệu Đang hoạt động',
        summaryMarkdown: 'Summary A',
        updatedAt: now,
      );

      await db.studyDao.upsertStudySetRaw(
        id: 'set-deleted',
        documentId: 'doc-dash-01',
        title: 'Bộ học liệu Chuẩn bị Xóa',
        summaryMarkdown: 'Summary B',
        updatedAt: now,
      );

      // Insert study sessions for both sets
      await db.studyDao.insertStudySessionRaw(
        id: 'sess-active-01',
        studySetId: 'set-active',
        sessionType: 'FLASHCARD',
        score: 100.0,
        totalItems: 5,
        durationSeconds: 120,
        completedAt: now,
      );

      await db.studyDao.insertStudySessionRaw(
        id: 'sess-deleted-01',
        studySetId: 'set-deleted',
        sessionType: 'QUIZ',
        score: 80.0,
        totalItems: 4,
        durationSeconds: 90,
        completedAt: now,
      );

      // Initial check: both sessions exist in the recent sessions stream
      final initialSessions =
          await db.studyDao.watchRecentSessions(days: 7).first;
      expect(initialSessions.any((s) => s.id == 'sess-active-01'), isTrue);
      expect(initialSessions.any((s) => s.id == 'sess-deleted-01'), isTrue);

      // Soft delete set-deleted
      await db.studyDao.tombstoneDeleteStudySet('set-deleted', DateTime.now());

      // Recent sessions stream should automatically omit sessions from set-deleted
      final activeSessions =
          await db.studyDao.watchRecentSessions(days: 7).first;
      expect(activeSessions.any((s) => s.id == 'sess-active-01'), isTrue);
      expect(activeSessions.any((s) => s.id == 'sess-deleted-01'), isFalse);
    });

    test(
        'SubjectDao.watchAllActiveSubjects totalStudyMinutes excludes time from soft-deleted study sets',
        () async {
      final now = DateTime.now();

      await db.subjectDao.upsertSubjectRaw(
        id: 'sub-time-01',
        title: 'Cơ Sở Dữ Liệu',
        code: 'DB301',
        colorHex: '#059669',
        updatedAt: now,
      );

      await db.studyDao.upsertDocumentRaw(
        id: 'doc-time-01',
        subjectId: 'sub-time-01',
        title: 'Chương 1: SQL Relational Model',
        fileType: 'TEXT',
        localFilePath: '',
        rawExtractedText: 'SQL Relational',
        updatedAt: now,
      );

      await db.studyDao.upsertStudySetRaw(
        id: 'set-time-active',
        documentId: 'doc-time-01',
        title: 'Bộ học liệu SQL Chuẩn',
        summaryMarkdown: 'Summary SQL',
        updatedAt: now,
      );

      await db.studyDao.upsertStudySetRaw(
        id: 'set-time-deleted',
        documentId: 'doc-time-01',
        title: 'Bộ học liệu Xóa',
        summaryMarkdown: 'Summary Delete',
        updatedAt: now,
      );

      // 120s for active set (2 mins), 180s for set to be deleted (3 mins)
      await db.studyDao.insertStudySessionRaw(
        id: 'sess-time-01',
        studySetId: 'set-time-active',
        sessionType: 'FLASHCARD',
        score: 100.0,
        totalItems: 10,
        durationSeconds: 120,
        completedAt: now,
      );

      await db.studyDao.insertStudySessionRaw(
        id: 'sess-time-02',
        studySetId: 'set-time-deleted',
        sessionType: 'FLASHCARD',
        score: 100.0,
        totalItems: 15,
        durationSeconds: 180,
        completedAt: now,
      );

      // Before deletion: total 300s -> ceil(300 / 60) = 5 mins
      var subjects = await db.subjectDao.watchAllActiveSubjects().first;
      expect(subjects.first.totalStudyMinutes, 5);

      // Soft delete set-time-deleted
      await db.studyDao
          .tombstoneDeleteStudySet('set-time-deleted', DateTime.now());

      // After deletion: only active set 120s -> ceil(120 / 60) = 2 mins
      subjects = await db.subjectDao.watchAllActiveSubjects().first;
      expect(subjects.first.totalStudyMinutes, 2);
    });
  });

  group('FEAT-SYNC: Orphaned Syncing Items Recovery', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test(
        'recoverOrphanedSyncingItems resets status from SYNCING back to PENDING',
        () async {
      // Enqueue an item
      await db.syncDao.enqueueMutation(
        tableName: 'subjects',
        recordId: 'sub-crash-01',
        operation: SyncOperation.insert,
        payloadJson: jsonEncode({'id': 'sub-crash-01', 'title': 'Crash Test'}),
      );

      final items = await db.syncDao.getPendingSyncItems();
      expect(items.length, 1);
      final itemId = items.first.id;

      // Simulate mid-flight crash: mark as SYNCING
      await db.syncDao.markAsSyncing(itemId);

      // Verify that getPendingSyncItems now returns 0 (item is stranded in SYNCING state)
      var pending = await db.syncDao.getPendingSyncItems();
      expect(pending, isEmpty);

      // Run recovery
      final recoveredCount = await db.syncDao.recoverOrphanedSyncingItems();
      expect(recoveredCount, 1);

      // Item should now be accessible again in pending queue
      pending = await db.syncDao.getPendingSyncItems();
      expect(pending.length, 1);
      expect(pending.first.status, SyncStatus.pending);
    });

    test(
        'runBidirectionalSync prevents concurrent execution and duplicate processing',
        () async {
      final syncEngine = OfflineSyncEngine(
        db: db,
        connectivity: _FakeOnlineConnectivity(),
      );

      await db.syncDao.enqueueMutation(
        tableName: 'subjects',
        recordId: 'sub-concur-01',
        operation: SyncOperation.insert,
        payloadJson:
            jsonEncode({'id': 'sub-concur-01', 'title': 'Concur Test'}),
      );

      // Launch sync runs concurrently
      final futureA = syncEngine.runBidirectionalSync();
      final futureB = syncEngine.runBidirectionalSync();

      final results = await Future.wait([futureA, futureB]);

      // Exactly one should succeed with the item, and the other should return 0 (skipped due to lock)
      expect(results.contains(1), isTrue);
      expect(results.contains(0), isTrue);
      expect(syncEngine.isSyncRunning, isFalse);
    });
  });
}
