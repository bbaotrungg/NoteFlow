import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noteflow_ai/data/local/database/app_database.dart';
import 'package:noteflow_ai/data/sync/offline_sync_engine.dart';
import 'package:noteflow_ai/domain/entities/sync_queue_item_entity.dart';

void main() {
  late AppDatabase db;
  late OfflineSyncEngine syncEngine;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    syncEngine = OfflineSyncEngine(db: db);
  });

  tearDown(() async {
    await db.close();
  });

  group('OfflineSyncEngine - Last-Write-Wins (LWW) Conflict Resolution Tests', () {
    test('Local wins when local updatedAt timestamp is strictly newer than remote', () {
      final localTime = DateTime.utc(2026, 11, 8, 14, 30, 0);
      final remoteTime = DateTime.utc(2026, 11, 8, 14, 25, 0);

      final localWins = syncEngine.shouldLocalWinConflict(
        localUpdatedAt: localTime,
        remoteUpdatedAt: remoteTime,
      );

      expect(localWins, isTrue, reason: 'Local change occurred after remote change');
    });

    test('Remote wins when remote updatedAt timestamp is strictly newer than local', () {
      final localTime = DateTime.utc(2026, 11, 8, 14, 20, 0);
      final remoteTime = DateTime.utc(2026, 11, 8, 14, 25, 0);

      final localWins = syncEngine.shouldLocalWinConflict(
        localUpdatedAt: localTime,
        remoteUpdatedAt: remoteTime,
      );

      expect(localWins, isFalse, reason: 'Remote change occurred after local change');
    });

    test('Local wins tie-breaker when both timestamps are exactly identical', () {
      final exactTime = DateTime.utc(2026, 11, 8, 15, 0, 0, 500);

      final localWins = syncEngine.shouldLocalWinConflict(
        localUpdatedAt: exactTime,
        remoteUpdatedAt: exactTime,
      );

      expect(localWins, isTrue, reason: 'Tie-breaker favors local copy to prevent data loss on device');
    });

    test('Correctly compares timestamps across different timezone offsets using UTC normalization', () {
      // Local time in UTC+7 (Vietnam standard time): 17:00:00 = 10:00:00 UTC
      final localTimeVn = DateTime.parse('2026-11-08T17:00:00+07:00');
      // Remote time in UTC (Supabase cloud): 10:00:00 UTC
      final remoteTimeUtc = DateTime.parse('2026-11-08T10:00:00Z');

      expect(
        syncEngine.shouldLocalWinConflict(
          localUpdatedAt: localTimeVn,
          remoteUpdatedAt: remoteTimeUtc,
        ),
        isTrue,
        reason: '17:00+07:00 and 10:00Z represent the identical UTC instant (tie-breaker)',
      );

      // Remote time 1 second later: 10:00:01 UTC
      final remoteTimeOneSecondLater = DateTime.parse('2026-11-08T10:00:01Z');
      expect(
        syncEngine.shouldLocalWinConflict(
          localUpdatedAt: localTimeVn,
          remoteUpdatedAt: remoteTimeOneSecondLater,
        ),
        isFalse,
        reason: 'Remote is 1 second newer in normalized UTC',
      );
    });

    test('Microsecond resolution is preserved during conflict comparison', () {
      final localTime = DateTime.utc(2026, 11, 8, 12, 0, 0, 0, 100);
      final remoteTime = DateTime.utc(2026, 11, 8, 12, 0, 0, 0, 50);

      expect(
        syncEngine.shouldLocalWinConflict(
          localUpdatedAt: localTime,
          remoteUpdatedAt: remoteTime,
        ),
        isTrue,
      );
    });
  });

  group('SyncQueueItemEntity & Enums Serialization Tests', () {
    test('SyncOperation parses uppercase, lowercase and fallback gracefully', () {
      expect(SyncOperation.fromString('INSERT'), equals(SyncOperation.insert));
      expect(SyncOperation.fromString('insert'), equals(SyncOperation.insert));
      expect(SyncOperation.fromString('UPDATE'), equals(SyncOperation.update));
      expect(SyncOperation.fromString('DELETE'), equals(SyncOperation.delete));
      expect(SyncOperation.fromString('INVALID_OP'), equals(SyncOperation.update));
    });

    test('SyncStatus parses uppercase, lowercase and fallback gracefully', () {
      expect(SyncStatus.fromString('PENDING'), equals(SyncStatus.pending));
      expect(SyncStatus.fromString('pending'), equals(SyncStatus.pending));
      expect(SyncStatus.fromString('SYNCING'), equals(SyncStatus.syncing));
      expect(SyncStatus.fromString('FAILED'), equals(SyncStatus.failed));
      expect(SyncStatus.fromString('UNKNOWN_STATUS'), equals(SyncStatus.pending));
    });

    test('SyncQueueItemEntity maintains state correctly', () {
      final item = SyncQueueItemEntity(
        id: 'sync-001',
        tableName: 'subjects',
        recordId: 'sub-001',
        operation: SyncOperation.update,
        payloadJson: '{"id":"sub-001","title":"Toán Rời Rạc"}',
        status: SyncStatus.pending,
        retryCount: 2,
        createdAt: DateTime.utc(2026, 11, 8, 8, 0),
      );

      expect(item.id, 'sync-001');
      expect(item.tableName, 'subjects');
      expect(item.operation.dbValue, 'UPDATE');
      expect(item.status.dbValue, 'PENDING');
      expect(item.retryCount, 2);
    });
  });
}
