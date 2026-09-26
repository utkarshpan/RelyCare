import '../../models/referral.dart';
import '../../models/referral_status.dart';
import '../../models/referral_guardian_status.dart';
import '../local_storage/app_database.dart';
import '../../core/constants/app_constants.dart';

/// Pure evaluator service for RelyCare Referral Guardian.
///
/// Evaluates operational continuity status (NORMAL, AT_RISK, ACTION_REQUIRED)
/// based strictly on existing referral status, SyncQueue retries, events timeline,
/// and operational time windows.
///
/// OPERATIONAL SAFETY PRINCIPLES:
/// - Pure computation only: NO network requests, NO database mutations, NO SMS triggers.
/// - Workflow continuity monitoring: Does NOT make medical predictions, clinical risk assessments, or diagnose patients.
/// - Operational language: Returns operational summaries (e.g. "Referral awaiting hospital acknowledgement").
class ReferralGuardianService {
  const ReferralGuardianService();

  /// Evaluates operational guardian status for a referral.
  ReferralGuardianEvaluation evaluateReferral({
    required Referral referral,
    SyncQueueData? syncQueueData,
    List<ReferralEventData>? events,
    DateTime? currentTime,
    int maxSyncRetries = AppConstants.maxSyncRetries,
    Duration atRiskWindow = AppConstants.guardianAtRiskWindow,
    Duration actionRequiredWindow = AppConstants.guardianActionRequiredWindow,
  }) {
    final now = currentTime ?? DateTime.now();

    // 1. Progressed / Acknowledged referrals (RECEIVED, PATIENT_ARRIVED, UNDER_TREATMENT, COMPLETED) are NORMAL
    if (referral.status == ReferralStatus.received ||
        referral.status == ReferralStatus.patientArrived ||
        referral.status == ReferralStatus.underTreatment ||
        referral.status == ReferralStatus.completed) {
      return const ReferralGuardianEvaluation(
        status: ReferralGuardianStatus.normal,
        operationalSummary: 'Referral progressing normally: Acknowledged by destination facility.',
      );
    }

    final hasSmsFailed = events?.any((e) => e.eventType == 'SMS_FAILED') ?? false;
    final hasSmsSent = events?.any((e) => e.eventType == 'SMS_SENT') ?? false;
    final isSyncFailedMax = syncQueueData != null &&
        syncQueueData.status == 'FAILED' &&
        syncQueueData.retryCount >= maxSyncRetries;

    final elapsedTime = now.difference(referral.createdAt);

    // 2. Check ACTION_REQUIRED conditions
    if (isSyncFailedMax) {
      return const ReferralGuardianEvaluation(
        status: ReferralGuardianStatus.actionRequired,
        operationalSummary: 'Referral requires facility follow-up: Maximum sync retries exhausted.',
      );
    }

    if (hasSmsFailed) {
      return const ReferralGuardianEvaluation(
        status: ReferralGuardianStatus.actionRequired,
        operationalSummary: 'Referral requires facility follow-up: SMS fallback delivery failed.',
      );
    }

    if (elapsedTime >= actionRequiredWindow) {
      return const ReferralGuardianEvaluation(
        status: ReferralGuardianStatus.actionRequired,
        operationalSummary: 'Referral requires facility follow-up: Extended operational window elapsed without hospital acknowledgement.',
      );
    }

    // 3. Check AT_RISK conditions
    if (syncQueueData != null &&
        (syncQueueData.retryCount == 1 || syncQueueData.retryCount == 2)) {
      return ReferralGuardianEvaluation(
        status: ReferralGuardianStatus.atRisk,
        operationalSummary: 'Referral awaiting hospital acknowledgement: Sync retry attempt ${syncQueueData.retryCount} in progress.',
      );
    }

    if (hasSmsSent) {
      return const ReferralGuardianEvaluation(
        status: ReferralGuardianStatus.atRisk,
        operationalSummary: 'Referral awaiting hospital acknowledgement: Notified destination facility via SMS fallback.',
      );
    }

    if (elapsedTime >= atRiskWindow) {
      return const ReferralGuardianEvaluation(
        status: ReferralGuardianStatus.atRisk,
        operationalSummary: 'Referral awaiting hospital acknowledgement: Standard operational response window elapsed.',
      );
    }

    // 4. Default: NORMAL
    return const ReferralGuardianEvaluation(
      status: ReferralGuardianStatus.normal,
      operationalSummary: 'Referral progressing normally: Awaiting routine facility routing.',
    );
  }
}
