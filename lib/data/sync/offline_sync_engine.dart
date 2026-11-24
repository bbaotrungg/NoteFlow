import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../../domain/entities/document_entity.dart';
import '../../domain/entities/flashcard_entity.dart';
import '../../domain/entities/quiz_question_entity.dart';
import '../../domain/entities/study_session_entity.dart';
import '../../domain/entities/study_set_entity.dart';
import '../../domain/entities/subject_entity.dart';
import '../../domain/entities/sync_queue_item_entity.dart';
import '../local/database/app_database.dart';

/// Phân hệ 1: Động cơ đồng bộ hai chiều Offline-First (Drift SQLite <-> Supabase PostgreSQL)
///
/// Đặc tả kỹ thuật:
/// 1. Outbox Queue (`sync_queue`): Đẩy tuần tự các bản ghi PENDING/FAILED lên Supabase khi có mạng.
/// 2. Tombstone Soft-Delete (`is_deleted = true`): Không xóa vật lý ngay mà đồng bộ cờ `is_deleted`
///    để mọi thiết bị của sinh viên đều nhận biết bản ghi đã bị xóa.
/// 3. Giải quyết xung đột Last-Write-Wins (LWW):
///    So sánh trực tiếp trường `updated_at` giữa bản ghi Local và bản ghi trên Cloud Supabase:
///    - Nếu `local.updated_at >= remote.updated_at`: Ghi đè bản ghi từ Local lên Cloud (Local Wins).
///    - Nếu `remote.updated_at > local.updated_at`: Cập nhật bản ghi từ Cloud về SQLite cục bộ (Remote Wins).
class OfflineSyncEngine {
  final AppDatabase _db;
  final Connectivity _connectivity;
  final SupabaseClient? _supabaseClient;

  OfflineSyncEngine({
    required AppDatabase db,
    Connectivity? connectivity,
    SupabaseClient? supabaseClient,
  })  : _db = db,
        _connectivity = connectivity ?? Connectivity(),
        _supabaseClient = supabaseClient;

  /// Kiểm tra kết nối mạng thực tế
  Future<bool> isOnline() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return results.any((r) =>
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.ethernet);
    } catch (_) {
      return false;
    }
  }

  /// Thuật toán phân xử xung đột Last-Write-Wins (LWW) thuần khiết (Unit Testable)
  /// Trả về `true` nếu phiên bản Local thắng (mới hơn hoặc bằng phiên bản Remote).
  bool shouldLocalWinConflict({
    required DateTime localUpdatedAt,
    required DateTime remoteUpdatedAt,
  }) {
    return !localUpdatedAt.toUtc().isBefore(remoteUpdatedAt.toUtc());
  }

  bool _isSyncRunning = false;

  /// Cho biết một tiến trình đồng bộ hai chiều đang thực thi
  bool get isSyncRunning => _isSyncRunning;

  /// Thực thi chu trình đồng bộ hai chiều (Push Outbox Queue -> Pull Remote Changes với LWW)
  /// Trả về tổng số bản ghi đã đồng bộ thành công.
  Future<int> runBidirectionalSync() async {
    // Ngăn chặn xung đột xử lý trùng lặp khi có 2 luồng gọi đồng bộ cùng lúc
    if (_isSyncRunning) {
      return 0;
    }
    _isSyncRunning = true;

    try {
      final online = await isOnline();
      if (!online) {
        return 0;
      }

      // Khôi phục mọi bản ghi bị kẹt ở trạng thái SYNCING do ngắt kết nối đột ngột
      await _db.syncDao.recoverOrphanedSyncingItems();

      final pendingItems = await _db.syncDao.getPendingSyncItems(limit: 100);
      int syncedCount = 0;

      for (final item in pendingItems) {
        await _db.syncDao.markAsSyncing(item.id);
        try {
          await _pushSingleQueueItemWithLww(item);
          await _db.syncDao.removeCompletedSyncItem(item.id);
          syncedCount++;
        } catch (_) {
          await _db.syncDao.markAsFailed(item.id);
        }
      }

      // Bước 2: Pull các bản ghi mới hơn từ Supabase về Local SQLite theo nguyên tắc LWW
      if (_supabaseClient != null && _isSupabaseConfigured) {
        await _pullRemoteUpdatesWithLww();
      }

      return syncedCount;
    } finally {
      _isSyncRunning = false;
    }
  }

  bool get _isSupabaseConfigured =>
      AppConstants.supabaseUrl.isNotEmpty &&
      !AppConstants.supabaseUrl.contains('demo-noteflow-vku');

  Future<void> _pushSingleQueueItemWithLww(SyncQueueItemEntity item) async {
    // Nếu đang chạy ở chế độ Local/Demo chưa cấu hình Supabase project thật,
    // mô phỏng độ trễ xác thực đồng bộ để dọn sạch hàng đợi sau khi kiểm tra tính toàn vẹn JSON.
    if (_supabaseClient == null || !_isSupabaseConfigured) {
      final payload = jsonDecode(item.payloadJson) as Map<String, dynamic>;
      if (!payload.containsKey('id')) {
        throw StateError('Payload thiếu khóa định danh id');
      }
      await Future<void>.delayed(const Duration(milliseconds: 60));
      return;
    }

    final client = _supabaseClient;
    final payload = jsonDecode(item.payloadJson) as Map<String, dynamic>;
    if (client.auth.currentUser != null) {
      final activeUserId = client.auth.currentUser!.id;
      // SEC-02: Prevent cross-user attribution: verify payload owner matches current user if present
      if (payload.containsKey('user_id') &&
          payload['user_id'] != null &&
          payload['user_id'] != activeUserId) {
        throw StateError(
          'Security Violation: Attempted to synchronize item owned by user ${payload['user_id']} under session of user $activeUserId',
        );
      }
      payload['user_id'] = activeUserId;
    }
    final recordId = item.recordId;

    // Kiểm tra phiên bản hiện có trên Supabase để phân xử xung đột LWW
    final existingRemote = await client
        .from(item.tableName)
        .select()
        .eq('id', recordId)
        .maybeSingle();

    final localTimeStr =
        (payload['updated_at'] ?? payload['completed_at']) as String?;
    final remoteTimeStr = existingRemote != null
        ? ((existingRemote['updated_at'] ?? existingRemote['completed_at'])
            as String?)
        : null;

    if (existingRemote != null &&
        remoteTimeStr != null &&
        localTimeStr != null) {
      final localUpdatedAt = DateTime.parse(localTimeStr).toUtc();
      final remoteUpdatedAt = DateTime.parse(remoteTimeStr).toUtc();

      final localWins = shouldLocalWinConflict(
        localUpdatedAt: localUpdatedAt,
        remoteUpdatedAt: remoteUpdatedAt,
      );

      if (!localWins) {
        // Remote mới hơn -> Áp dụng bản ghi Remote xuống SQLite cục bộ và kết thúc mục hàng đợi này
        await _applyRemoteRecordToLocal(item.tableName, existingRemote);
        return;
      }
    }

    // Local thắng hoặc chưa tồn tại trên Remote -> Upsert lên Supabase (kể cả Tombstone is_deleted = true)
    await client.from(item.tableName).upsert(payload);
  }

  Future<void> _pullRemoteUpdatesWithLww() async {
    final client = _supabaseClient;
    if (client == null || !_isSupabaseConfigured) return;

    const syncedTables = [
      'subjects',
      'documents',
      'study_sets',
      'flashcards',
      'quiz_questions',
      'study_sessions',
    ];

    for (final table in syncedTables) {
      final remoteRows = await client.from(table).select();
      for (final rawRow in remoteRows) {
        await _reconcileRemoteRow(table, rawRow);
      }
    }
  }

  Future<void> _reconcileRemoteRow(
      String tableName, Map<String, dynamic> remoteJson) async {
    final id = remoteJson['id'] as String;
    final timeStr =
        (remoteJson['updated_at'] ?? remoteJson['completed_at']) as String?;
    final remoteUpdatedAt =
        timeStr != null ? DateTime.parse(timeStr).toLocal() : DateTime.now();

    DateTime? localUpdatedAt;
    if (tableName == 'subjects') {
      final local = await _db.subjectDao.getSubjectById(id);
      localUpdatedAt = local?.updatedAt;
    } else if (tableName == 'documents') {
      final local = await _db.studyDao.getDocumentById(id);
      localUpdatedAt = local?.updatedAt;
    } else if (tableName == 'study_sets') {
      final local = await _db.studyDao.getStudySetById(id);
      localUpdatedAt = local?.updatedAt;
    } else if (tableName == 'flashcards') {
      final local = await _db.studyDao.getFlashcardById(id);
      localUpdatedAt = local?.updatedAt;
    } else if (tableName == 'quiz_questions') {
      final local = await _db.studyDao.getQuizQuestionById(id);
      localUpdatedAt = local?.updatedAt;
    } else if (tableName == 'study_sessions') {
      final local = await _db.studyDao.getStudySessionById(id);
      localUpdatedAt = local?.completedAt;
    }

    if (localUpdatedAt == null ||
        !shouldLocalWinConflict(
            localUpdatedAt: localUpdatedAt, remoteUpdatedAt: remoteUpdatedAt)) {
      await _applyRemoteRecordToLocal(tableName, remoteJson);
    }
  }

  Future<void> _applyRemoteRecordToLocal(
      String tableName, Map<String, dynamic> remoteJson) async {
    switch (tableName) {
      case 'subjects':
        final entity = SubjectEntity.fromSyncJson(remoteJson);
        await _db.subjectDao.upsertSubjectRaw(
          id: entity.id,
          title: entity.title,
          code: entity.code,
          colorHex: entity.colorHex,
          updatedAt: entity.updatedAt,
          isDeleted: entity.isDeleted,
        );
        break;
      case 'documents':
        final entity = DocumentEntity.fromSyncJson(remoteJson);
        await _db.studyDao.upsertDocumentRaw(
          id: entity.id,
          subjectId: entity.subjectId,
          title: entity.title,
          fileType: entity.fileType.dbValue,
          localFilePath: entity.localFilePath,
          rawExtractedText: entity.rawExtractedText,
          updatedAt: entity.updatedAt,
          isDeleted: entity.isDeleted,
        );
        break;
      case 'study_sets':
        final entity = StudySetEntity.fromSyncJson(remoteJson);
        await _db.studyDao.upsertStudySetRaw(
          id: entity.id,
          documentId: entity.documentId,
          title: entity.title,
          summaryMarkdown: entity.summaryMarkdown,
          updatedAt: entity.updatedAt,
          isDeleted: entity.isDeleted,
        );
        break;
      case 'flashcards':
        final entity = FlashcardEntity.fromSyncJson(remoteJson);
        await _db.studyDao.upsertFlashcardRaw(
          id: entity.id,
          studySetId: entity.studySetId,
          frontText: entity.frontText,
          backText: entity.backText,
          hint: entity.hint,
          easeFactor: entity.easeFactor,
          intervalDays: entity.intervalDays,
          repetitionCount: entity.repetitionCount,
          nextReviewAt: entity.nextReviewAt,
          updatedAt: entity.updatedAt,
          isDeleted: entity.isDeleted,
        );
        break;
      case 'quiz_questions':
        final entity = QuizQuestionEntity.fromSyncJson(remoteJson);
        await _db.studyDao.upsertQuizQuestionRaw(
          id: entity.id,
          studySetId: entity.studySetId,
          questionText: entity.questionText,
          optionsJson: entity.optionsJson,
          correctIndex: entity.correctIndex,
          explanation: entity.explanation,
          timesAnswered: entity.timesAnswered,
          timesCorrect: entity.timesCorrect,
          updatedAt: entity.updatedAt,
          isDeleted: entity.isDeleted,
        );
        break;
      case 'study_sessions':
        final entity = StudySessionEntity.fromSyncJson(remoteJson);
        await _db.studyDao.insertStudySessionRaw(
          id: entity.id,
          studySetId: entity.studySetId,
          sessionType: entity.sessionType.dbValue,
          score: entity.score,
          totalItems: entity.totalItems,
          durationSeconds: entity.durationSeconds,
          completedAt: entity.completedAt,
        );
        break;
    }
  }
}
