import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/sync_queue.dart';

part 'sync_queue_dao.g.dart';

@DriftAccessor(tables: [SyncQueue])
class SyncQueueDao extends DatabaseAccessor<AppDatabase> with _$SyncQueueDaoMixin {
  SyncQueueDao(super.db);

  /// Adds a new operation to the offline sync queue.
  Future<int> addToQueue(SyncQueueCompanion item) => into(syncQueue).insert(item);

  /// Retrieves all pending sync items sorted by creation time.
  Future<List<SyncQueueData>> getPendingItems() =>
      (select(syncQueue)
            ..where((tbl) => tbl.status.equals('PENDING'))
            ..orderBy([(tbl) => OrderingTerm.asc(tbl.createdAt)]))
          .get();

  /// Retrieves all eligible sync items (PENDING or FAILED with retryCount < maxRetries).
  Future<List<SyncQueueData>> getEligibleItems(int maxRetries) =>
      (select(syncQueue)
            ..where((tbl) =>
                tbl.status.equals('PENDING') |
                (tbl.status.equals('FAILED') & tbl.retryCount.isSmallerThanValue(maxRetries)))
            ..orderBy([(tbl) => OrderingTerm.asc(tbl.createdAt)]))
          .get();

  /// Retrieves all failed items that are still eligible for retry.
  Future<List<SyncQueueData>> getRetryableFailedItems(int maxRetries) =>
      (select(syncQueue)
            ..where((tbl) =>
                tbl.status.equals('FAILED') & tbl.retryCount.isSmallerThanValue(maxRetries))
            ..orderBy([(tbl) => OrderingTerm.asc(tbl.createdAt)]))
          .get();

  /// Retrieves all failed sync queue items.
  Future<List<SyncQueueData>> getFailedItems() =>
      (select(syncQueue)
            ..where((tbl) => tbl.status.equals('FAILED'))
            ..orderBy([(tbl) => OrderingTerm.asc(tbl.createdAt)]))
          .get();

  /// Marks a sync queue item as currently syncing.
  Future<int> markSyncing(int id) {
    return (update(syncQueue)..where((tbl) => tbl.id.equals(id))).write(
      SyncQueueCompanion(
        status: const Value('SYNCING'),
        lastAttempt: Value(DateTime.now()),
      ),
    );
  }

  /// Marks a sync queue item as successfully synced.
  Future<int> markSuccess(int id) {
    return (update(syncQueue)..where((tbl) => tbl.id.equals(id))).write(
      SyncQueueCompanion(
        status: const Value('SUCCESS'),
        lastAttempt: Value(DateTime.now()),
      ),
    );
  }

  /// Marks a sync queue item as failed with optional status reset to PENDING for retry.
  Future<int> markFailed(int id, {bool resetToPending = true}) {
    return (update(syncQueue)..where((tbl) => tbl.id.equals(id))).write(
      SyncQueueCompanion(
        status: Value(resetToPending ? 'PENDING' : 'FAILED'),
        lastAttempt: Value(DateTime.now()),
      ),
    );
  }

  /// Increments the retry count and updates the last attempt timestamp.
  Future<int> incrementRetryCount(int id) async {
    final item = await (select(syncQueue)..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
    if (item == null) return 0;
    return (update(syncQueue)..where((tbl) => tbl.id.equals(id))).write(
      SyncQueueCompanion(
        retryCount: Value(item.retryCount + 1),
        lastAttempt: Value(DateTime.now()),
      ),
    );
  }

  /// Resets all failed items to PENDING with retryCount reset to 0 for manual retry.
  Future<int> resetFailedItemsToPending() {
    return (update(syncQueue)..where((tbl) => tbl.status.equals('FAILED'))).write(
      const SyncQueueCompanion(
        status: Value('PENDING'),
        retryCount: Value(0),
      ),
    );
  }

  /// Deletes a sync queue item by its ID.
  Future<int> deleteQueueItem(int id) =>
      (delete(syncQueue)..where((tbl) => tbl.id.equals(id))).go();
}
