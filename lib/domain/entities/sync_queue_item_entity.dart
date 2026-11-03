enum SyncOperation {
  insert('INSERT'),
  update('UPDATE'),
  delete('DELETE');

  final String dbValue;
  const SyncOperation(this.dbValue);

  static SyncOperation fromString(String value) {
    return SyncOperation.values.firstWhere(
      (e) => e.dbValue.toUpperCase() == value.toUpperCase(),
      orElse: () => SyncOperation.update,
    );
  }
}

enum SyncStatus {
  pending('PENDING'),
  syncing('SYNCING'),
  failed('FAILED');

  final String dbValue;
  const SyncStatus(this.dbValue);

  static SyncStatus fromString(String value) {
    return SyncStatus.values.firstWhere(
      (e) => e.dbValue.toUpperCase() == value.toUpperCase(),
      orElse: () => SyncStatus.pending,
    );
  }
}

/// Thực thể Hàng đợi đồng bộ (SYNC_QUEUE) phục vụ kiến trúc Offline-First
class SyncQueueItemEntity {
  final String id;
  final String tableName;
  final String recordId;
  final SyncOperation operation;
  final String payloadJson;
  final SyncStatus status;
  final int retryCount;
  final DateTime createdAt;

  const SyncQueueItemEntity({
    required this.id,
    required this.tableName,
    required this.recordId,
    required this.operation,
    required this.payloadJson,
    this.status = SyncStatus.pending,
    this.retryCount = 0,
    required this.createdAt,
  });
}
