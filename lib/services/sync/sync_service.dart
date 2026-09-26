// ignore_for_file: prefer_initializing_formals
import '../local_storage/local_storage_service.dart';
import '../local_storage/app_database.dart';
import '../api/api_service.dart';
import '../connectivity/connectivity_service.dart';
import '../../models/referral.dart';
import '../../core/errors/app_exceptions.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/facility_normalizer.dart';
import '../../core/utils/logger.dart';

/// Orchestration service responsible for processing the offline sync queue,
/// handling sync failures, and managing retries up to [maxRetries].
class SyncService {
  final LocalStorageService localStorage;
  final ApiService apiService;
  final ConnectivityService connectivityService;
  final int maxRetries;

  bool _isSyncing = false;

  bool get isSyncing => _isSyncing;

  SyncService({
    required this.localStorage,
    required this.apiService,
    required this.connectivityService,
    this.maxRetries = AppConstants.maxSyncRetries,
  });

  /// Synchronizes all eligible sync queue items (PENDING or FAILED with retryCount < maxRetries)
  /// and pulls the latest referrals from the backend into local SQLite.
  ///
  /// Flow:
  /// 1. Verifies connectivity is ONLINE. If OFFLINE, returns 0 without modifying queue or retry counts.
  /// 2. Ensures no concurrent sync execution via [_isSyncing] guard.
  /// 3. Step 1: PUSH — Reads eligible queue items in FIFO order and posts to backend.
  /// 4. Step 2: PULL — Fetches latest referrals from backend and ingests via [upsertReferralFromSync].
  /// 5. Updates local SQLite safely without overwriting pending local modifications.
  Future<int> syncPendingReferrals() async {
    final isOnline = await connectivityService.checkConnectivity();
    if (!isOnline) {
      AppLogger.warning('Cannot sync: Device is offline', 'SyncService');
      return 0;
    }

    if (_isSyncing) {
      AppLogger.info('Sync already in progress, skipping concurrent trigger', 'SyncService');
      return 0;
    }

    _isSyncing = true;
    try {
      // Step 1: PUSH pending/eligible offline items
      final eligibleItems = await localStorage.getEligibleSyncItems(maxRetries);
      int syncedCount = 0;
      if (eligibleItems.isNotEmpty) {
        syncedCount = await _processQueueItems(eligibleItems);
      }

      // Step 2: PULL latest server referrals into local SQLite
      try {
        await _executePull();
      } catch (e, stack) {
        AppLogger.error('Pull step failed during sync pass: $e', e, stack, 'SyncService');
        // Do not mask push results if pull fails, but log error
      }

      return syncedCount;
    } catch (e, stack) {
      AppLogger.error('Unexpected error during sync pass', e, stack, 'SyncService');
      return 0;
    } finally {
      _isSyncing = false;
    }
  }

  /// Pulls the latest referrals from FastAPI backend into local SQLite database.
  ///
  /// Throws [NetworkException] if offline or if the API request fails.
  Future<List<Referral>> pullReferralsFromServer({
    int skip = 0,
    int limit = 100,
    String? status,
  }) async {
    final isOnline = await connectivityService.checkConnectivity();
    if (!isOnline) {
      AppLogger.warning('Cannot pull: Device is offline', 'SyncService');
      throw const NetworkException('Device is offline');
    }

    if (_isSyncing) {
      AppLogger.info('Sync already in progress, skipping concurrent pull trigger', 'SyncService');
      return [];
    }

    _isSyncing = true;
    try {
      return await _executePull(skip: skip, limit: limit, status: status);
    } catch (e, stack) {
      AppLogger.error('Failed to pull referrals from server', e, stack, 'SyncService');
      rethrow;
    } finally {
      _isSyncing = false;
    }
  }

  /// Internal helper to download and upsert server referrals into SQLite.
  Future<List<Referral>> _executePull({
    int skip = 0,
    int limit = 100,
    String? status,
  }) async {
    final serverReferrals = await apiService.fetchReferrals(
      skip: skip,
      limit: limit,
      status: status,
    );

    final upserted = <Referral>[];
    for (final referral in serverReferrals) {
      final saved = await localStorage.upsertReferralFromSync(referral);
      upserted.add(saved);
    }

    AppLogger.info('Successfully pulled and upserted ${upserted.length} referrals from server', 'SyncService');
    return upserted;
  }

  /// Manually retries only failed queue items that have not exceeded [maxRetries].
  Future<int> retryFailedItems() async {
    final isOnline = await connectivityService.checkConnectivity();
    if (!isOnline) {
      AppLogger.warning('Cannot retry: Device is offline', 'SyncService');
      return 0;
    }

    if (_isSyncing) {
      AppLogger.info('Sync/Retry already in progress, skipping concurrent trigger', 'SyncService');
      return 0;
    }

    _isSyncing = true;
    try {
      final retryableItems = await localStorage.getRetryableFailedItems(maxRetries);
      if (retryableItems.isEmpty) {
        AppLogger.info('No retryable failed items found', 'SyncService');
        return 0;
      }

      return await _processQueueItems(retryableItems);
    } catch (e, stack) {
      AppLogger.error('Unexpected error during retry pass', e, stack, 'SyncService');
      return 0;
    } finally {
      _isSyncing = false;
    }
  }

  /// Internal sequential processor for a list of sync queue items.
  Future<int> _processQueueItems(List<SyncQueueData> queueItems) async {
    int syncedCount = 0;

    AppLogger.info(
      'Processing ${queueItems.length} items in sync queue (Max retries: $maxRetries)',
      'SyncService',
    );

    for (final queueItem in queueItems) {
      // Mark item as SYNCING before calling API
      await localStorage.markSyncing(queueItem.id);

      try {
        final referral = await localStorage.getDomainReferralById(queueItem.entityId);
        if (referral == null) {
          AppLogger.warning(
            'Referral ${queueItem.entityId} not found locally for queue item #${queueItem.id}',
            'SyncService',
          );
          await localStorage.markSyncFailed(queueItem.id, resetToPending: false);
          continue;
        }

        var referralToSend = referral;
        final normalizedSource = FacilityNormalizer.normalizeSourceFacility(
          referral.sourceFacilityId.trim().isEmpty ? FacilityNormalizer.defaultPhcFacility : referral.sourceFacilityId,
        );
        final normalizedDest = FacilityNormalizer.normalizeDestinationFacility(
          referral.destinationFacilityId.trim().isEmpty ? FacilityNormalizer.defaultHospitalFacility : referral.destinationFacilityId,
        );
        if (normalizedSource != referral.sourceFacilityId || normalizedDest != referral.destinationFacilityId) {
          referralToSend = Referral(
            id: referral.id,
            referralToken: referral.referralToken,
            patientId: referral.patientId,
            patient: referral.patient,
            sourceFacilityId: normalizedSource,
            destinationFacilityId: normalizedDest,
            referralReason: referral.referralReason,
            urgency: referral.urgency,
            clinicalNotesSummary: referral.clinicalNotesSummary,
            status: referral.status,
            syncState: referral.syncState,
            createdAt: referral.createdAt,
            updatedAt: referral.updatedAt,
          );
        }

        // Attempt API synchronization
        try {
          await apiService.createReferral(referralToSend);
        } on DuplicateReferralException catch (dupEx) {
          // Reconcile 409 Duplicate: check if referral exists on server
          try {
            await apiService.getReferral(dupEx.referralId);
            AppLogger.info(
              'Reconciled duplicate referral ${dupEx.referralId} from server on 409 Conflict',
              'SyncService',
            );
          } catch (fetchErr, fetchStack) {
            AppLogger.error(
              'Failed to verify duplicate referral ${dupEx.referralId} on server: $fetchErr',
              fetchErr,
              fetchStack,
              'SyncService',
            );
            rethrow;
          }
        }

        // On success: mark queue item SUCCESS and local referral SYNCED
        await localStorage.markSyncSuccess(queueItem.id);
        await localStorage.updateReferralSyncStatus(referral.referralToken, 'SYNCED');

        syncedCount++;
        AppLogger.info(
          'Successfully synced referral ${referral.referralToken} (Queue #${queueItem.id})',
          'SyncService',
        );

      } on UnauthenticatedException catch (unauthEx) {
        AppLogger.warning(
          'Authentication token expired or invalid during sync pass (${unauthEx.message}). Resetting queue item #${queueItem.id} to PENDING without incrementing retry count and aborting sync pass cleanly.',
          'SyncService',
        );
        await localStorage.resetSyncToPending(queueItem.id);
        break;
      } catch (e, stack) {
        AppLogger.error(
          'Failed to sync queue item #${queueItem.id} (${queueItem.entityId}): $e',
          e,
          stack,
          'SyncService',
        );
        // On failure: mark FAILED and increment retryCount (without deleting data or marking referral synced)
        await localStorage.markSyncFailed(queueItem.id, resetToPending: false);
      }
    }

    return syncedCount;
  }

}
