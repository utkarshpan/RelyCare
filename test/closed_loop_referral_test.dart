import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:relycare/models/referral.dart';
import 'package:relycare/models/patient.dart';
import 'package:relycare/models/identity_match.dart';
import 'package:relycare/models/referral_status.dart';
import 'package:relycare/models/referral_guardian_status.dart';
import 'package:relycare/models/user_model.dart';
import 'package:relycare/providers/referral_provider.dart';
import 'package:relycare/repositories/referral_repository.dart';
import 'package:relycare/services/api/api_service.dart';
import 'package:relycare/services/connectivity/connectivity_service.dart';
import 'package:relycare/services/local_storage/app_database.dart';
import 'package:relycare/services/local_storage/local_storage_service.dart';
import 'package:relycare/services/sms/sms_service.dart';
import 'package:relycare/services/guardian/referral_guardian_service.dart';

class MockClosedLoopApiService implements ApiService {
  final Map<String, Referral> serverStore = {};

  @override
  void setAuthToken(String? token) {}

  @override
  Future<Map<String, dynamic>> login(String username, String password) async => {};

  @override
  Future<UserModel> getMe() async => const UserModel(
        id: 1,
        username: 'hospital_staff',
        role: 'HOSPITAL_STAFF',
        facilityId: 'DH-TEST',
        isActive: true,
      );

  @override
  Future<Referral> createReferral(Referral referral) async {
    serverStore[referral.referralToken] = referral;
    return referral;
  }

  @override
  Future<Referral> getReferral(String referralId) async {
    if (!serverStore.containsKey(referralId)) {
      throw Exception('Referral $referralId not found');
    }
    return serverStore[referralId]!;
  }

  @override
  Future<List<Referral>> fetchReferrals({int skip = 0, int limit = 100, String? status}) async {
    var items = serverStore.values.toList();
    if (status != null) {
      items = items.where((r) => r.status.code == status).toList();
    }
    return items;
  }

  @override
  Future<void> updateReferralStatus(String referralId, String status) async {
    if (!serverStore.containsKey(referralId)) {
      throw Exception('Referral $referralId not found');
    }
    final existing = serverStore[referralId]!;
    final updated = Referral(
      id: existing.id,
      referralToken: existing.referralToken,
      patientId: existing.patientId,
      patient: existing.patient,
      sourceFacilityId: existing.sourceFacilityId,
      destinationFacilityId: existing.destinationFacilityId,
      referralReason: existing.referralReason,
      urgency: existing.urgency,
      clinicalNotesSummary: existing.clinicalNotesSummary,
      status: ReferralStatusExtension.fromString(status),
      syncState: SyncState.synced,
      createdAt: existing.createdAt,
      updatedAt: DateTime.now(),
    );
    serverStore[referralId] = updated;
  }

  @override
  Future<List<Referral>> syncBatch(List<Referral> queuedReferrals) async => queuedReferrals;

  @override
  Future<List<IdentityMatch>> requestIdentityMatches(Patient incomingPatient) async => [];
}

class MockOnlineConnectivityService implements ConnectivityService {
  @override
  Future<ConnectivityStatus> checkConnectivityStatus() async => ConnectivityStatus.online;

  @override
  Future<bool> checkConnectivity() async => true;

  @override
  Stream<ConnectivityStatus> get onStatusChanged => const Stream.empty();

  @override
  Stream<bool> get onConnectivityChanged => const Stream.empty();

  @override
  ConnectivityStatus get currentStatus => ConnectivityStatus.online;

  @override
  void dispose() {}
}

class MockOfflineConnectivityService implements ConnectivityService {
  @override
  Future<ConnectivityStatus> checkConnectivityStatus() async => ConnectivityStatus.offline;

  @override
  Future<bool> checkConnectivity() async => false;

  @override
  Stream<ConnectivityStatus> get onStatusChanged => const Stream.empty();

  @override
  Stream<bool> get onConnectivityChanged => const Stream.empty();

  @override
  ConnectivityStatus get currentStatus => ConnectivityStatus.offline;

  @override
  void dispose() {}
}

void main() {
  group('Closed-Loop Referral & Follow-up Lifecycle Unit Tests', () {
    late AppDatabase db;
    late LocalStorageService localStorage;
    late MockClosedLoopApiService apiService;
    late MockOnlineConnectivityService connectivityService;
    late MockSmsService smsService;
    late ReferralRepository repository;
    late ReferralProvider provider;
    const guardianService = ReferralGuardianService();

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      localStorage = LocalStorageServiceImpl(db);
      apiService = MockClosedLoopApiService();
      connectivityService = MockOnlineConnectivityService();
      smsService = MockSmsService();

      repository = ReferralRepository(
        localStorage: localStorage,
        apiService: apiService,
        connectivityService: connectivityService,
        smsService: smsService,
      );

      provider = ReferralProvider(referralRepository: repository);
    });

    tearDown(() async {
      provider.dispose();
      await db.close();
    });

    test('Test 1: Hospital can move SENT -> RECEIVED', () async {
      final referral = await provider.createReferral(
        patientName: 'Kavita Verma',
        patientAge: 32,
        patientGender: 'Female',
        sourceFacility: 'PHC-TEST',
        destinationFacility: 'DH-TEST',
        reason: 'High risk pregnancy evaluation',
        customReferralId: 'RC-LOOP-001',
      );
      expect(referral, isNotNull);
      await apiService.createReferral(referral!);

      // Hospital updates status to RECEIVED
      await provider.updateReferralStatus(
        'RC-LOOP-001',
        ReferralStatus.received,
        facilityId: 'DH-TEST',
        performedBy: 'Dr. Verma',
      );

      final updated = await repository.getReferralById('RC-LOOP-001');
      expect(updated!.status, equals(ReferralStatus.received));

      final events = await repository.getReferralEvents('RC-LOOP-001');
      expect(events.any((e) => e.eventType == 'RECEIVED'), isTrue);
    });

    test('Test 2: Hospital can move RECEIVED -> PATIENT_ARRIVED', () async {
      final ref = await provider.createReferral(
        patientName: 'Ramesh Gupta',
        patientAge: 45,
        patientGender: 'Male',
        sourceFacility: 'PHC-TEST',
        destinationFacility: 'DH-TEST',
        reason: 'Chest pain',
        customReferralId: 'RC-LOOP-002',
      );
      await apiService.createReferral(ref!);

      await provider.updateReferralStatus('RC-LOOP-002', ReferralStatus.received);
      await provider.updateReferralStatus('RC-LOOP-002', ReferralStatus.patientArrived);

      final updated = await repository.getReferralById('RC-LOOP-002');
      expect(updated!.status, equals(ReferralStatus.patientArrived));

      final events = await repository.getReferralEvents('RC-LOOP-002');
      expect(events.any((e) => e.eventType == 'PATIENT_ARRIVED'), isTrue);
    });

    test('Test 3: Hospital can move PATIENT_ARRIVED -> UNDER_TREATMENT', () async {
      final ref = await provider.createReferral(
        patientName: 'Sunita Devi',
        patientAge: 50,
        patientGender: 'Female',
        sourceFacility: 'PHC-TEST',
        destinationFacility: 'DH-TEST',
        reason: 'Fracture management',
        customReferralId: 'RC-LOOP-003',
      );
      await apiService.createReferral(ref!);

      await provider.updateReferralStatus('RC-LOOP-003', ReferralStatus.received);
      await provider.updateReferralStatus('RC-LOOP-003', ReferralStatus.patientArrived);
      await provider.updateReferralStatus('RC-LOOP-003', ReferralStatus.underTreatment);

      final updated = await repository.getReferralById('RC-LOOP-003');
      expect(updated!.status, equals(ReferralStatus.underTreatment));

      final events = await repository.getReferralEvents('RC-LOOP-003');
      expect(events.any((e) => e.eventType == 'UNDER_TREATMENT'), isTrue);
    });

    test('Test 4: Hospital can move UNDER_TREATMENT -> COMPLETED', () async {
      final ref = await provider.createReferral(
        patientName: 'Anil Kumar',
        patientAge: 29,
        patientGender: 'Male',
        sourceFacility: 'PHC-TEST',
        destinationFacility: 'DH-TEST',
        reason: 'Abdominal pain',
        customReferralId: 'RC-LOOP-004',
      );
      await apiService.createReferral(ref!);

      await provider.updateReferralStatus('RC-LOOP-004', ReferralStatus.received);
      await provider.updateReferralStatus('RC-LOOP-004', ReferralStatus.patientArrived);
      await provider.updateReferralStatus('RC-LOOP-004', ReferralStatus.underTreatment);
      await provider.updateReferralStatus('RC-LOOP-004', ReferralStatus.completed);

      final updated = await repository.getReferralById('RC-LOOP-004');
      expect(updated!.status, equals(ReferralStatus.completed));

      final events = await repository.getReferralEvents('RC-LOOP-004');
      expect(events.any((e) => e.eventType == 'COMPLETED'), isTrue);
    });

    test('Test 5: PHC pull receives downstream status updates', () async {
      final referral = await provider.createReferral(
        patientName: 'Rajesh Sharma',
        patientAge: 40,
        patientGender: 'Male',
        sourceFacility: 'PHC-TEST',
        destinationFacility: 'DH-TEST',
        reason: 'Cardiology evaluation',
        customReferralId: 'RC-LOOP-005',
      );

      // Simulate server store having COMPLETED status updated by hospital
      await apiService.createReferral(referral!);
      await localStorage.updateReferralSyncStatus('RC-LOOP-005', 'SYNCED');
      await apiService.updateReferralStatus('RC-LOOP-005', 'COMPLETED');

      // PHC pulls referrals from server
      await provider.pullReferrals();

      final pulled = await repository.getReferralById('RC-LOOP-005');
      expect(pulled!.status, equals(ReferralStatus.completed));
    });

    test('Test 6: Referral reaches COMPLETED and remains completed', () async {
      final ref = await provider.createReferral(
        patientName: 'Pooja Singh',
        patientAge: 24,
        patientGender: 'Female',
        sourceFacility: 'PHC-TEST',
        destinationFacility: 'DH-TEST',
        reason: 'Routine consult',
        customReferralId: 'RC-LOOP-006',
      );
      await apiService.createReferral(ref!);

      await provider.updateReferralStatus('RC-LOOP-006', ReferralStatus.completed);
      final completedRef = await repository.getReferralById('RC-LOOP-006');
      expect(completedRef!.status, equals(ReferralStatus.completed));
    });

    test('Test 7: Guardian remains NORMAL for RECEIVED, PATIENT_ARRIVED, UNDER_TREATMENT, COMPLETED', () {
      final baseTime = DateTime(2026, 9, 26, 10, 0);
      final statuses = [
        ReferralStatus.received,
        ReferralStatus.patientArrived,
        ReferralStatus.underTreatment,
        ReferralStatus.completed,
      ];

      for (final s in statuses) {
        final ref = Referral(
          id: '1',
          referralToken: 'RC-GUARDIAN-TEST',
          patientId: 'P1',
          sourceFacilityId: 'PHC-TEST',
          destinationFacilityId: 'DH-TEST',
          referralReason: 'Check',
          urgency: ReferralUrgency.routine,
          status: s,
          syncState: SyncState.synced,
          createdAt: baseTime,
          updatedAt: baseTime,
        );

        final eval = guardianService.evaluateReferral(referral: ref, currentTime: baseTime);
        expect(eval.status, equals(ReferralGuardianStatus.normal));
      }
    });

    test('Test 8: Backend server reflects status changes cleanly', () async {
      final referral = await provider.createReferral(
        patientName: 'Deepak Patel',
        patientAge: 38,
        patientGender: 'Male',
        sourceFacility: 'PHC-TEST',
        destinationFacility: 'DH-TEST',
        reason: 'Ultrasound required',
        customReferralId: 'RC-LOOP-008',
      );
      await apiService.createReferral(referral!);

      await repository.updateStatus('RC-LOOP-008', ReferralStatus.received);
      final serverRef = await apiService.getReferral('RC-LOOP-008');
      expect(serverRef.status, equals(ReferralStatus.received));
    });

    test('Test 9: Timeline events are recorded for each status transition', () async {
      final ref = await provider.createReferral(
        patientName: 'Maya Verma',
        patientAge: 35,
        patientGender: 'Female',
        sourceFacility: 'PHC-TEST',
        destinationFacility: 'DH-TEST',
        reason: 'Diabetic screening',
        customReferralId: 'RC-LOOP-009',
      );
      await apiService.createReferral(ref!);

      await provider.updateReferralStatus('RC-LOOP-009', ReferralStatus.received);
      await provider.updateReferralStatus('RC-LOOP-009', ReferralStatus.patientArrived);

      final events = await repository.getReferralEvents('RC-LOOP-009');
      final eventTypes = events.map((e) => e.eventType).toList();

      expect(eventTypes, contains('CREATED'));
      expect(eventTypes, contains('RECEIVED'));
      expect(eventTypes, contains('PATIENT_ARRIVED'));
    });

    test('Test 10: Offline status update persists locally in SQLite', () async {
      final offlineRepo = ReferralRepository(
        localStorage: localStorage,
        apiService: apiService,
        connectivityService: MockOfflineConnectivityService(),
        smsService: smsService,
      );

      await offlineRepo.createReferralOffline(
        patientName: 'Offline Patient',
        patientAge: 60,
        patientGender: 'Male',
        sourceFacility: 'PHC-TEST',
        destinationFacility: 'DH-TEST',
        reason: 'Offline care',
        customReferralId: 'RC-LOOP-010',
      );

      await offlineRepo.updateStatus('RC-LOOP-010', ReferralStatus.patientArrived);

      final localRef = await offlineRepo.getReferralById('RC-LOOP-010');
      expect(localRef!.status, equals(ReferralStatus.patientArrived));
    });
  });
}
