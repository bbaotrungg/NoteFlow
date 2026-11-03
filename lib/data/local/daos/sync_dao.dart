import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/entities/sync_queue_item_entity.dart';
import '../database/app_database.dart';

/// DAO quản lý bảng SYNC_QUEUE cho kiến trúc đồng bộ Offline-First 2 chiều
class SyncDao {
  final AppDatabase _db;
  static const _uuid = Uuid();

  SyncDao(this._db);

  Stream<int> watchPendingSyncCount() {
    return _db.customSelect(
      "SELECT COUNT(*) AS cnt FROM sync_queue WHERE status IN ('PENDING', 'FAILED')",
      readsFrom: {_db.syncQueueTable},
    ).watch().map((rows) => rows.isEmpty ? 0 : (rows.first.readNullable<int>('cnt') ?? 0));
  }

  /// Đưa một thao tác thay đổi dữ liệu (INSERT / UPDATE / DELETE) vào hàng đợi đồng bộ.
  /// Nếu đã có bản ghi PENDING cho cùng (table_name, record_id), hợp nhất (Coalesce) payload mới nhất.
  Future<void> enqueueMutation({
    required String tableName,
    required String recordId,
    required SyncOperation operation,
    required String payloadJson,
  }) async {
    final existing = await _db.customSelect(
      '''
      SELECT id, operation FROM sync_queue
      WHERE table_name = ?1 AND record_id = ?2 AND status IN ('PENDING', 'FAILED')
      LIMIT 1
      ''',
      variables: [
        Variable<String>(tableName),
        Variable<String>(recordId),
      ],
      readsFrom: {_db.syncQueueTable},
    ).get();

    final nowMs = DateTime.now().millisecondsSinceEpoch;

    if (existing.isNotEmpty) {
      final existingId = existing.first.read<String>('id');
      final prevOp = existing.first.read<String>('operation');
      // Nếu bản ghi vừa được INSERT offline rồi UPDATE offline, giữ nguyên operation là INSERT với payload mới nhất
      final mergedOp = (prevOp == 'INSERT' && operation == SyncOperation.update)
          ? 'INSERT'
          : operation.dbValue;

      await _db.customUpdate(
        '''
        UPDATE sync_queue
        SET operation = ?1, payload_json = ?2, status = 'PENDING', created_at = ?3
        WHERE id = ?4
        ''',
        variables: [
          Variable<String>(mergedOp),
          Variable<String>(payloadJson),
          Variable<int>(nowMs),
          Variable<String>(existingId),
        ],
        updates: {_db.syncQueueTable},
        updateKind: UpdateKind.update,
      );
    } else {
      await _db.customInsert(
        '''
        INSERT INTO sync_queue (
          id, table_name, record_id, operation, payload_json, status, retry_count, created_at
        ) VALUES (?1, ?2, ?3, ?4, ?5, 'PENDING', 0, ?6)
        ''',
        variables: [
          Variable<String>(_uuid.v4()),
          Variable<String>(tableName),
          Variable<String>(recordId),
          Variable<String>(operation.dbValue),
          Variable<String>(payloadJson),
          Variable<int>(nowMs),
        ],
        updates: {_db.syncQueueTable},
      );
    }
  }

  Future<List<SyncQueueItemEntity>> getPendingSyncItems({int limit = 50}) async {
    final rows = await _db.customSelect(
      '''
      SELECT * FROM sync_queue
      WHERE status IN ('PENDING', 'FAILED') AND retry_count < 5
      ORDER BY created_at ASC
      LIMIT ?1
      ''',
      variables: [Variable<int>(limit)],
      readsFrom: {_db.syncQueueTable},
    ).get();

    return rows.map((row) {
      return SyncQueueItemEntity(
        id: row.read<String>('id'),
        tableName: row.read<String>('table_name'),
        recordId: row.read<String>('record_id'),
        operation: SyncOperation.fromString(row.read<String>('operation')),
        payloadJson: row.read<String>('payload_json'),
        status: SyncStatus.fromString(row.read<String>('status')),
        retryCount: row.read<int>('retry_count'),
        createdAt: DateTime.fromMillisecondsSinceEpoch(row.read<int>('created_at')),
      );
    }).toList();
  }

  Future<void> markAsSyncing(String id) async {
    await _db.customUpdate(
      "UPDATE sync_queue SET status = 'SYNCING' WHERE id = ?1",
      variables: [Variable<String>(id)],
      updates: {_db.syncQueueTable},
      updateKind: UpdateKind.update,
    );
  }

  Future<void> removeCompletedSyncItem(String id) async {
    await _db.customUpdate(
      'DELETE FROM sync_queue WHERE id = ?1',
      variables: [Variable<String>(id)],
      updates: {_db.syncQueueTable},
      updateKind: UpdateKind.delete,
    );
  }

  Future<void> markAsFailed(String id) async {
    await _db.customUpdate(
      "UPDATE sync_queue SET status = 'FAILED', retry_count = retry_count + 1 WHERE id = ?1",
      variables: [Variable<String>(id)],
      updates: {_db.syncQueueTable},
      updateKind: UpdateKind.update,
    );
  }
}
