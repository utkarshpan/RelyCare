import 'package:flutter_test/flutter_test.dart';
import 'package:relycare/models/referral.dart';
import 'package:relycare/models/referral_status.dart';
import 'package:relycare/models/referral_guardian_status.dart';
import 'package:relycare/services/guardian/referral_guardian_service.dart';
import 'package:relycare/services/local_storage/app_database.dart';

void main() {
  group('Referral Guardian Evaluator Unit Tests', () {
    const guardianService = ReferralGuardianService();
    final baseTime = DateTime(2026, 9, 26, 10, 0, 0);

    Referral createTestReferral({
      ReferralStatus status = ReferralStatus.created,
      DateTime? createdAt,
    }) {
      return Referral(
        id: '1',
        referralToken: 'RC-2026-TEST01',
        patientId: 'P1',
        sourceFacilityId: 'PHC-TEST',
        destinationFacilityId: 'DH-TEST',
        referralReason: 'Evaluation',
        urgency: ReferralUrgency.urgent,
        status: status,
        syncState: SyncState.pendingSync,
        createdAt: createdAt ?? baseTime,
        updatedAt: createdAt ?? baseTime,
      );
    }

    SyncQueueData createTestSyncQueue({
      int retryCount = 0,
      String status = 'PENDING',
    }) {
      return SyncQueueData(
        id: 1,
        entityType: 'REFERRAL',
        entityId: 'RC-2026-TEST01',
        operation: 'CREATE',
        payload: '{}',
        status: status,
        retryCount: retryCount,
        createdAt: baseTime,
      );
    }

    ReferralEventData createTestEvent(String eventType) {
      return ReferralEventData(
        id: 1,
        referralId: 'RC-2026-TEST01',
        eventType: eventType,
        facility: 'PHC-TEST',
        timestamp: baseTime,
      );
    }

    test('Test 1: RECEIVED status evaluates to NORMAL', () {
      final referral = createTestReferral(status: ReferralStatus.received);
      final eval = guardianService.evaluateReferral(referral: referral, currentTime: baseTime);

      expect(eval.status, equals(ReferralGuardianStatus.normal));
      expect(eval.operationalSummary, contains('Acknowledged by destination facility'));
    });

    test('Test 2: PATIENT_ARRIVED status evaluates to NORMAL', () {
      final referral = createTestReferral(status: ReferralStatus.patientArrived);
      final eval = guardianService.evaluateReferral(referral: referral, currentTime: baseTime);

      expect(eval.status, equals(ReferralGuardianStatus.normal));
    });

    test('Test 3: UNDER_TREATMENT status evaluates to NORMAL', () {
      final referral = createTestReferral(status: ReferralStatus.underTreatment);
      final eval = guardianService.evaluateReferral(referral: referral, currentTime: baseTime);

      expect(eval.status, equals(ReferralGuardianStatus.normal));
    });

    test('Test 4: COMPLETED status evaluates to NORMAL', () {
      final referral = createTestReferral(status: ReferralStatus.completed);
      final eval = guardianService.evaluateReferral(referral: referral, currentTime: baseTime);

      expect(eval.status, equals(ReferralGuardianStatus.normal));
    });

    test('Test 5: retryCount 0 evaluates to NORMAL when otherwise progressing within window', () {
      final referral = createTestReferral(status: ReferralStatus.created);
      final syncQueue = createTestSyncQueue(retryCount: 0, status: 'PENDING');
      final eval = guardianService.evaluateReferral(
        referral: referral,
        syncQueueData: syncQueue,
        currentTime: baseTime.add(const Duration(minutes: 15)),
      );

      expect(eval.status, equals(ReferralGuardianStatus.normal));
      expect(eval.operationalSummary, contains('Awaiting routine facility routing'));
    });

    test('Test 6: retryCount 1 evaluates to AT_RISK', () {
      final referral = createTestReferral(status: ReferralStatus.created);
      final syncQueue = createTestSyncQueue(retryCount: 1, status: 'FAILED');
      final eval = guardianService.evaluateReferral(
        referral: referral,
        syncQueueData: syncQueue,
        currentTime: baseTime.add(const Duration(minutes: 15)),
      );

      expect(eval.status, equals(ReferralGuardianStatus.atRisk));
      expect(eval.operationalSummary, contains('Sync retry attempt 1 in progress'));
    });

    test('Test 7: retryCount 2 evaluates to AT_RISK', () {
      final referral = createTestReferral(status: ReferralStatus.created);
      final syncQueue = createTestSyncQueue(retryCount: 2, status: 'FAILED');
      final eval = guardianService.evaluateReferral(
        referral: referral,
        syncQueueData: syncQueue,
        currentTime: baseTime.add(const Duration(minutes: 15)),
      );

      expect(eval.status, equals(ReferralGuardianStatus.atRisk));
      expect(eval.operationalSummary, contains('Sync retry attempt 2 in progress'));
    });

    test('Test 8: retryCount >= maxSyncRetries AND status FAILED evaluates to ACTION_REQUIRED', () {
      final referral = createTestReferral(status: ReferralStatus.created);
      final syncQueue = createTestSyncQueue(retryCount: 3, status: 'FAILED');
      final eval = guardianService.evaluateReferral(
        referral: referral,
        syncQueueData: syncQueue,
        maxSyncRetries: 3,
        currentTime: baseTime.add(const Duration(minutes: 15)),
      );

      expect(eval.status, equals(ReferralGuardianStatus.actionRequired));
      expect(eval.operationalSummary, contains('Maximum sync retries exhausted'));
    });

    test('Test 9: SMS_SENT event evaluates to AT_RISK without making medical risk claims', () {
      final referral = createTestReferral(status: ReferralStatus.created);
      final events = [createTestEvent('SMS_SENT')];
      final eval = guardianService.evaluateReferral(
        referral: referral,
        events: events,
        currentTime: baseTime.add(const Duration(minutes: 15)),
      );

      expect(eval.status, equals(ReferralGuardianStatus.atRisk));
      expect(eval.operationalSummary, contains('Notified destination facility via SMS fallback'));
      expect(eval.operationalSummary, isNot(contains('medical emergency')));
      expect(eval.operationalSummary, isNot(contains('danger')));
    });

    test('Test 10: SMS_FAILED event evaluates to ACTION_REQUIRED while preserving referral state', () {
      final referral = createTestReferral(status: ReferralStatus.created);
      final events = [createTestEvent('SMS_FAILED')];
      final eval = guardianService.evaluateReferral(
        referral: referral,
        events: events,
        currentTime: baseTime.add(const Duration(minutes: 15)),
      );

      expect(eval.status, equals(ReferralGuardianStatus.actionRequired));
      expect(eval.operationalSummary, contains('SMS fallback delivery failed'));
      // Verify domain model remains untouched
      expect(referral.status, equals(ReferralStatus.created));
      expect(referral.syncState, equals(SyncState.pendingSync));
    });

    test('Test 11: Elapsed time exceeding atRiskWindow evaluates to AT_RISK', () {
      final referral = createTestReferral(status: ReferralStatus.created, createdAt: baseTime);
      final eval = guardianService.evaluateReferral(
        referral: referral,
        atRiskWindow: const Duration(hours: 2),
        currentTime: baseTime.add(const Duration(hours: 3)),
      );

      expect(eval.status, equals(ReferralGuardianStatus.atRisk));
      expect(eval.operationalSummary, contains('Standard operational response window elapsed'));
    });

    test('Test 12: Elapsed time exceeding actionRequiredWindow evaluates to ACTION_REQUIRED', () {
      final referral = createTestReferral(status: ReferralStatus.created, createdAt: baseTime);
      final eval = guardianService.evaluateReferral(
        referral: referral,
        actionRequiredWindow: const Duration(hours: 6),
        currentTime: baseTime.add(const Duration(hours: 7)),
      );

      expect(eval.status, equals(ReferralGuardianStatus.actionRequired));
      expect(eval.operationalSummary, contains('Extended operational window elapsed'));
    });
  });
}
