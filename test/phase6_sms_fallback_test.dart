import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relycare/models/identity_match.dart';
import 'package:relycare/models/patient.dart';
import 'package:relycare/models/referral.dart';
import 'package:relycare/models/user_model.dart';
import 'package:relycare/providers/referral_provider.dart';
import 'package:relycare/repositories/patient_repository.dart';
import 'package:relycare/repositories/referral_repository.dart';
import 'package:relycare/services/api/api_service.dart';
import 'package:relycare/services/connectivity/connectivity_service.dart';
import 'package:relycare/services/local_storage/app_database.dart';
import 'package:relycare/services/local_storage/local_storage_service.dart';
import 'package:relycare/services/sms/sms_service.dart';

/// Fake API stub for testing isolation.
class FakeApiStub implements ApiService {
  @override
  void setAuthToken(String? token) {}

  @override
  Future<Map<String, dynamic>> login(String username, String password) async => {};

  @override
  Future<UserModel> getMe() async => const UserModel(
        id: 1,
        username: 'test_user',
        role: 'PHC_STAFF',
        facilityId: 'PHC_TEST',
        isActive: true,
      );

  @override
  Future<Referral> createReferral(Referral referral) async => referral;


  @override
  Future<Referral> getReferral(String referralId) async => throw UnimplementedError();

  @override
  Future<List<Referral>> fetchReferrals({int skip = 0, int limit = 100, String? status}) async => [];

  @override
  Future<void> updateReferralStatus(String referralId, String status) async {}

  @override
  Future<List<Referral>> syncBatch(List<Referral> queuedReferrals) async => [];

  @override
  Future<List<IdentityMatch>> requestIdentityMatches(Patient incomingPatient) async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 6: SMS Fallback for Offline Referrals Tests', () {
    late AppDatabase db;
    late LocalStorageService localStorage;
    late MockSmsService mockSmsService;
    late ReferralRepository referralRepository;
    late PatientRepository patientRepository;
    late ReferralProvider referralProvider;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      localStorage = LocalStorageServiceImpl(db);
      mockSmsService = MockSmsService();
      referralRepository = ReferralRepository(
        localStorage: localStorage,
        apiService: FakeApiStub(),
        connectivityService: ConnectivityServiceImpl(),
        smsService: mockSmsService,
      );
      patientRepository = PatientRepository(
        localStorage: localStorage,
        apiService: FakeApiStub(),
        connectivityService: ConnectivityServiceImpl(),
      );
      referralProvider = ReferralProvider(
        referralRepository: referralRepository,
      );
    });

    tearDown(() async {
      await localStorage.close();
    });

    test('Test A: Correct SMS message generation produces compact privacy-safe payload', () async {
      final referral = await referralProvider.createReferral(
        patientName: 'Rahul Sharma',
        patientAge: 42,
        patientGender: 'Male',
        patientPhone: '+91 9876543210',
        sourceFacility: 'PHC Rampur',
        destinationFacility: 'District Hospital East',
        reason: 'Severe acute abdomen',
        clinicalNotes: 'Peritoneal signs positive, high fever 102F',
      );
      expect(referral, isNotNull);

      final payload = referralRepository.generateSmsPayload(referral!);

      // Verify compact format contains necessary routing fields
      expect(payload, contains('RelyCare Referral'));
      expect(payload, contains('REF: ${referral.referralToken}'));
      expect(payload, contains('PHC: PHC Rampur'));
      expect(payload, contains('PAT: Rahul S')); // Sanitized name for privacy
      expect(payload, contains('AGE: 42'));
      expect(payload, contains('DST: District Hospital East'));

      // Critical Privacy Rule: Clinical notes / diagnoses must NEVER be in unencrypted SMS
      expect(payload, isNot(contains('Peritoneal signs')));
      expect(payload, isNot(contains('high fever')));
    });

    test('Test B: Successful SMS send records SMS_SENT event and sets status to sent', () async {
      final referral = await referralProvider.createReferral(
        patientName: 'Sunita Devi',
        patientAge: 29,
        patientGender: 'Female',
        sourceFacility: 'PHC Kalyanpur',
        destinationFacility: 'DH Gorakhpur',
        reason: 'High-risk delivery',
      );

      final result = await referralProvider.sendSmsFallback(
        referral!.referralToken,
        recipientPhoneNumber: '+91 9988776655',
        forceRetry: true,
      );

      expect(result, isNotNull);
      expect(result!.isSuccess, isTrue);
      expect(result.messageId, startsWith('MOCK-SMS-'));
      expect(mockSmsService.sentPayloads.length, greaterThanOrEqualTo(1));
      expect(mockSmsService.sentRecipients.first, equals('+91 9988776655'));

      // Verify delivery status
      final status = await referralProvider.getSmsDeliveryStatus(referral.referralToken);
      expect(status, equals(SmsDeliveryStatus.sent));

      // Verify SMS_SENT event recorded in SQLite timeline
      final events = await referralProvider.getReferralEvents(referral.id);
      expect(events.any((e) => e.eventType == 'SMS_SENT'), isTrue);
    });

    test('Test C: SMS failure records SMS_FAILED event and exposes failure safely', () async {
      mockSmsService.shouldFail = true;

      final referral = await referralProvider.createReferral(
        patientName: 'Devendra Patel',
        patientAge: 55,
        patientGender: 'Male',
        sourceFacility: 'PHC West',
        destinationFacility: 'DH West',
        reason: 'Chest pain',
      );

      final result = await referralProvider.sendSmsFallback(
        referral!.referralToken,
        recipientPhoneNumber: '+91 9988776655',
      );

      expect(result, isNotNull);
      expect(result!.isSuccess, isFalse);
      expect(result.errorMessage, contains('transmission failed'));
      expect(mockSmsService.sentPayloads.isEmpty, isTrue);

      // Verify delivery status is failed
      final status = await referralProvider.getSmsDeliveryStatus(referral.referralToken);
      expect(status, equals(SmsDeliveryStatus.failed));

      // Verify SMS_FAILED event recorded in SQLite timeline
      final events = await referralProvider.getReferralEvents(referral.id);
      expect(events.any((e) => e.eventType == 'SMS_FAILED'), isTrue);
    });

    test('Test D: Referral remains locally stored after SMS failure with zero data loss', () async {
      mockSmsService.shouldFail = true;

      final referral = await referralProvider.createReferral(
        patientName: 'Asha Rani',
        patientAge: 35,
        patientGender: 'Female',
        sourceFacility: 'PHC North',
        destinationFacility: 'DH Central',
        reason: 'Severe anemia',
        clinicalNotes: 'Hb 6.5 g/dL',
      );

      await referralProvider.sendSmsFallback(
        referral!.referralToken,
        recipientPhoneNumber: '+91 9123456789',
      );

      // Verify referral still exists in SQLite
      final localRef = await referralRepository.getReferralById(referral.id);
      expect(localRef, isNotNull);
      expect(localRef!.patient?.fullName, equals('Asha Rani'));
      expect(localRef.clinicalNotesSummary, equals('Hb 6.5 g/dL'));

      // Verify patient still exists in SQLite
      final localPatient = await patientRepository.getPatientById(referral.patientId);
      expect(localPatient, isNotNull);
      expect(localPatient!.fullName, equals('Asha Rani'));
    });

    test('Test E: Duplicate successful SMS is prevented on second send attempt', () async {
      final referral = await referralProvider.createReferral(
        patientName: 'Manoj Tiwari',
        patientAge: 40,
        patientGender: 'Male',
        sourceFacility: 'PHC East',
        destinationFacility: 'DH East',
        reason: 'Fracture',
      );

      // First send -> succeeds
      final res1 = await referralProvider.sendSmsFallback(
        referral!.referralToken,
        recipientPhoneNumber: '+91 9876543210',
      );
      expect(res1!.isSuccess, isTrue);
      expect(mockSmsService.sentPayloads.length, equals(1));

      // Second send without forceRetry -> duplicate prevented
      final res2 = await referralProvider.sendSmsFallback(
        referral.referralToken,
        recipientPhoneNumber: '+91 9876543210',
        forceRetry: false,
      );
      expect(res2!.isSuccess, isTrue);
      expect(res2.messageId, equals('ALREADY_SENT'));
      expect(mockSmsService.sentPayloads.length, equals(1),
          reason: 'Gateway must not be called a second time for already sent referral');
    });

    test('Test F: Manual retry with forceRetry allows re-attempting failed SMS', () async {
      mockSmsService.shouldFail = true;

      final referral = await referralProvider.createReferral(
        patientName: 'Kavita Yadav',
        patientAge: 26,
        patientGender: 'Female',
        sourceFacility: 'PHC Subcenter',
        destinationFacility: 'DH Gorakhpur',
        reason: 'Postpartum care',
      );

      // Attempt 1 -> fails
      final res1 = await referralProvider.sendSmsFallback(
        referral!.referralToken,
        recipientPhoneNumber: '+91 9988771122',
      );
      expect(res1!.isSuccess, isFalse);
      expect(await referralProvider.getSmsDeliveryStatus(referral.referralToken),
          equals(SmsDeliveryStatus.failed));

      // Modem / mock recovery
      mockSmsService.shouldFail = false;

      // Attempt 2 (retry) -> succeeds
      final res2 = await referralProvider.sendSmsFallback(
        referral.referralToken,
        recipientPhoneNumber: '+91 9988771122',
        forceRetry: true,
      );
      expect(res2!.isSuccess, isTrue);
      expect(mockSmsService.sentPayloads.length, equals(1));
    });

    test('Test G: Retry success transitions state from failed to sent in SQLite events', () async {
      mockSmsService.shouldFail = true;

      final referral = await referralProvider.createReferral(
        patientName: 'Vikram Singh',
        patientAge: 51,
        patientGender: 'Male',
        sourceFacility: 'PHC Alpha',
        destinationFacility: 'DH Beta',
        reason: 'Trauma evaluation',
      );

      // Verify delivery status is failed from automatic creation dispatch
      expect(await referralProvider.getSmsDeliveryStatus(referral!.referralToken),
          equals(SmsDeliveryStatus.failed));

      // Retry succeeds
      mockSmsService.shouldFail = false;
      await referralProvider.sendSmsFallback(
        referral.referralToken,
        recipientPhoneNumber: '+91 9988112233',
        forceRetry: true,
      );
      expect(await referralProvider.getSmsDeliveryStatus(referral.referralToken),
          equals(SmsDeliveryStatus.sent));

      final events = await referralProvider.getReferralEvents(referral.id);
      expect(events.where((e) => e.eventType == 'SMS_FAILED').length, equals(1));
      expect(events.where((e) => e.eventType == 'SMS_SENT').length, equals(1));
    });

    test('Test H: SMS success does NOT mark referral as API SYNCED', () async {
      final referral = await referralProvider.createReferral(
        patientName: 'Geeta Kumari',
        patientAge: 31,
        patientGender: 'Female',
        sourceFacility: 'PHC Kalyanpur',
        destinationFacility: 'DH Gorakhpur',
        reason: 'Severe anemia',
      );

      // Verify referral initial syncState is pendingSync
      expect(referral!.syncState, equals(SyncState.pendingSync));

      // Dispatch SMS successfully
      final smsResult = await referralProvider.sendSmsFallback(
        referral.referralToken,
        recipientPhoneNumber: '+91 9876543210',
      );
      expect(smsResult!.isSuccess, isTrue);

      // Verify referral remains pendingSync for future internet synchronization
      final localRef = await referralRepository.getReferralById(referral.id);
      expect(localRef!.syncState, equals(SyncState.pendingSync));

      // Verify sync queue item in SQLite remains PENDING
      final pendingQueue = await localStorage.getPendingSyncItems();
      expect(pendingQueue.length, equals(1));
      expect(pendingQueue.first.entityId, equals(referral.referralToken));
      expect(pendingQueue.first.status, equals('PENDING'));
    });
  });
}
