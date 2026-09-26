import '../models/referral.dart';
import '../services/local_storage/local_storage_service.dart';
import '../services/sync/sync_service.dart';

/// Repository responsible for sync queue operations, retry triggers, and queue metrics.
class SyncRepository {
  final LocalStorageService localStorage;
  final SyncService syncService;

  SyncRepository({
    required this.localStorage,
    required this.syncService,
  });

  /// Gets the count of records currently waiting in the offline queue with status PENDING.
  Future<int> getPendingQueueCount() async {
    final pending = await localStorage.getPendingSyncItems();
    return pending.length;
  }

  /// Gets the count of records in the offline queue with status FAILED.
  Future<int> getFailedQueueCount() async {
    final failed = await localStorage.getFailedSyncItems();
    return failed.length;
  }

  /// Triggers a synchronization pass for eligible pending/failed queue items.
  Future<int> triggerSync() async {
    return await syncService.syncPendingReferrals();
  }

  /// Triggers a retry pass specifically for retryable failed queue items.
  Future<int> retryFailed() async {
    return await syncService.retryFailedItems();
  }

  /// Resets all failed queue items to PENDING with retry count reset to 0 for manual retry.
  Future<void> resetFailedItems() async {
    await localStorage.resetAllFailedSyncItems();
  }

  /// Triggers pull-sync to fetch latest server referrals into local SQLite.
  Future<List<Referral>> pullReferrals({int skip = 0, int limit = 100, String? status}) async {
    return await syncService.pullReferralsFromServer(skip: skip, limit: limit, status: status);
  }
}
