// ignore_for_file: prefer_initializing_formals
import '../core/utils/facility_normalizer.dart';
import '../models/referral.dart';
import '../models/referral_status.dart';
import '../services/local_storage/local_storage_service.dart';
import '../services/local_storage/app_database.dart';
import '../services/api/api_service.dart';
import '../services/connectivity/connectivity_service.dart';
import '../services/sms/sms_service.dart';
import '../services/sync/sync_service.dart';
import '../core/utils/logger.dart';
import '../core/errors/app_exceptions.dart';

/// Repository managing referral creation, updates, querying, local storage access,
/// and SMS fallback dispatching.
class ReferralRepository {
  final LocalStorageService localStorage;
  final ApiService apiService;
  final ConnectivityService connectivityService;
  final SmsService smsService;
  final SyncService syncService;

  ReferralRepository({
    required this.localStorage,
    required this.apiService,
    required this.connectivityService,
    required this.smsService,
    SyncService? syncService,
  }) : syncService = syncService ??
            SyncService(
              localStorage: localStorage,
              apiService: apiService,
              connectivityService: connectivityService,
            );


  /// Creates a new referral offline using atomic LocalStorage transaction.
  /// Persists Patient, Referral (CREATED), Event (CREATED), and SyncQueue item (PENDING) in SQLite.
  /// Evaluates network connectivity:
  /// - If ONLINE: triggers immediate API sync via SyncService.
  /// - If OFFLINE (or API sync fails): triggers SMS fallback and records SMS_SENT/SMS_FAILED event.
  Future<Referral> createReferralOffline({
    required String patientName,
    required int patientAge,
    required String patientGender,
    String? patientPhone,
    String? patientLocation,
    required String sourceFacility,
    required String destinationFacility,
    required String reason,
    String? clinicalNotes,
    ReferralUrgency urgency = ReferralUrgency.routine,
    String? customReferralId,
    String? createdByStaff,
    String recipientPhoneNumber = '+91 9988776655',
    bool autoSync = true,
  }) async {
    final actualSourceFacility = FacilityNormalizer.normalizeSourceFacility(sourceFacility);
    final actualDestFacility = FacilityNormalizer.normalizeDestinationFacility(destinationFacility);

    final row = await localStorage.createReferralTransaction(
      patientName: patientName,
      patientAge: patientAge,
      patientGender: patientGender,
      patientPhone: patientPhone,
      patientLocation: patientLocation,
      sourceFacility: actualSourceFacility,
      destinationFacility: actualDestFacility,
      reason: reason,
      clinicalNotes: clinicalNotes,
      urgency: urgency,
      customReferralId: customReferralId,
      createdByStaff: createdByStaff,
    );

    AppLogger.info(
      'Referral ${row.referralId} created offline in SQLite',
      'ReferralRepository',
    );

    final domainReferral = await localStorage.getDomainReferralById(row.referralId);
    if (domainReferral == null) {
      throw const StorageException('Failed to retrieve created referral from local database');
    }

    if (autoSync) {
      // Evaluate connectivity and execute the appropriate channel
      final isOnline = await connectivityService.checkConnectivity();
      if (isOnline) {
        try {
          await syncService.syncPendingReferrals();
        } catch (e) {
          AppLogger.warning(
            'Immediate API sync threw exception: $e',
            'ReferralRepository',
          );
        }

        // Check the actual persisted sync state in SQLite
        final syncCheck = await localStorage.getDomainReferralById(row.referralId);
        if (syncCheck != null && syncCheck.syncState != SyncState.synced) {
          AppLogger.warning(
            'Referral ${row.referralId} remains unsynced after online sync pass (state: ${syncCheck.syncState}). Triggering SMS fallback channel.',
            'ReferralRepository',
          );
          await sendSmsFallback(
            domainReferral.referralToken,
            recipientPhoneNumber: recipientPhoneNumber,
          );
        }
      } else {
        // Offline mode: automatically dispatch SMS fallback
        await sendSmsFallback(
          domainReferral.referralToken,
          recipientPhoneNumber: recipientPhoneNumber,
        );
      }
    }

    final updated = await localStorage.getDomainReferralById(row.referralId);
    return updated ?? domainReferral;
  }

  /// Creates a referral from a domain Referral entity using the atomic transaction.
  Future<Referral> createReferral(Referral referral) async {
    return await createReferralOffline(
      patientName: referral.patient?.fullName ?? 'Unknown Patient',
      patientAge: referral.patient?.age ?? 0,
      patientGender: referral.patient?.gender ?? 'Other',
      patientPhone: referral.patient?.contactNumber,
      patientLocation: referral.patient?.villageOrLocation,
      sourceFacility: referral.sourceFacilityId,
      destinationFacility: referral.destinationFacilityId,
      reason: referral.referralReason,
      clinicalNotes: referral.clinicalNotesSummary,
      urgency: referral.urgency,
      customReferralId: referral.referralToken.isNotEmpty ? referral.referralToken : null,
    );
  }

  /// Retrieves all referrals from local SQLite storage.
  Future<List<Referral>> getAllReferrals() async {
    return await localStorage.getAllDomainReferrals();
  }

  /// Retrieves a single referral by its unique referral token ID.
  Future<Referral?> getReferralById(String id) async {
    return await localStorage.getDomainReferralById(id);
  }

  /// Retrieves timeline events for a given referral.
  Future<List<ReferralEventData>> getReferralEvents(String referralId) async {
    return await localStorage.getReferralEvents(referralId);
  }

  /// Updates status (e.g. PATIENT_ARRIVED, UNDER_TREATMENT, COMPLETED).
  Future<void> updateStatus(String referralId, ReferralStatus status) async {
    await localStorage.updateReferralStatus(referralId, status.code);
  }

  /// Pulls the latest referrals from FastAPI backend into local SQLite via shared SyncService.
  Future<List<Referral>> pullReferralsFromServer({int skip = 0, int limit = 100, String? status}) async {
    return await syncService.pullReferralsFromServer(skip: skip, limit: limit, status: status);
  }


  // ==========================================
  // PHASE 6: SMS FALLBACK OPERATIONS
  // ==========================================

  /// Sends a privacy-safe compact SMS fallback message for a locally stored referral.
  ///
  /// Rules:
  /// - Verifies local existence of referral.
  /// - Prevents duplicate successful sends unless [forceRetry] is true.
  /// - Records SMS_SENT or SMS_FAILED event in SQLite timeline.
  /// - Preserves local SQLite data regardless of SMS outcome.
  /// - Does NOT modify referral syncStatus (SMS is independent from API sync).
  Future<SmsResult> sendSmsFallback(
    String referralToken, {
    String recipientPhoneNumber = '+91 9988776655',
    bool forceRetry = false,
  }) async {
    final referral = await localStorage.getDomainReferralById(referralToken);
    if (referral == null) {
      return SmsResult.failure(
        payload: '',
        errorMessage: 'Referral $referralToken not found in local database',
      );
    }

    // Duplicate protection
    final currentSmsStatus = await localStorage.getSmsDeliveryStatus(referralToken);
    if (currentSmsStatus == SmsDeliveryStatus.sent && !forceRetry) {
      AppLogger.info(
        'Referral $referralToken has already been successfully sent via SMS. Skipping duplicate send.',
        'ReferralRepository',
      );
      return SmsResult.success(
        payload: smsService.generateSmsPayload(referral),
        messageId: 'ALREADY_SENT',
      );
    }

    // Dispatch SMS via service abstraction
    final result = await smsService.sendReferralSms(
      recipientPhoneNumber: recipientPhoneNumber,
      referral: referral,
    );

    // Record delivery event locally in SQLite
    if (result.isSuccess) {
      await localStorage.addReferralEvent(
        referralId: referral.referralToken,
        eventType: 'SMS_SENT',
        facility: referral.sourceFacilityId,
        performedBy: 'SMS Fallback Gateway',
        metadata: 'SMS dispatched to $recipientPhoneNumber (ID: ${result.messageId})',
      );
    } else {
      await localStorage.addReferralEvent(
        referralId: referral.referralToken,
        eventType: 'SMS_FAILED',
        facility: referral.sourceFacilityId,
        performedBy: 'SMS Fallback Gateway',
        metadata: 'SMS delivery failed: ${result.errorMessage}',
      );
    }

    return result;
  }

  /// Retrieves the current SMS delivery status for a given referral.
  Future<SmsDeliveryStatus> getSmsStatus(String referralToken) async {
    return await localStorage.getSmsDeliveryStatus(referralToken);
  }

  /// Generates the privacy-safe SMS representation for a given referral.
  String generateSmsPayload(Referral referral) {
    return smsService.generateSmsPayload(referral);
  }
}
