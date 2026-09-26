import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';

import 'package:relycare/core/errors/app_exceptions.dart';
import 'package:relycare/models/identity_match.dart';
import 'package:relycare/models/patient.dart';
import 'package:relycare/models/referral.dart';
import 'package:relycare/models/referral_status.dart';
import 'package:relycare/models/user_model.dart';
import 'package:relycare/providers/sync_provider.dart';
import 'package:relycare/repositories/referral_repository.dart';
import 'package:relycare/repositories/sync_repository.dart';
import 'package:relycare/services/api/api_service.dart';
import 'package:relycare/services/connectivity/connectivity_service.dart';
import 'package:relycare/services/local_storage/app_database.dart';
import 'package:relycare/services/local_storage/local_storage_service.dart';
import 'package:relycare/services/sms/sms_service.dart';
import 'package:relycare/services/sync/sync_service.dart';

/// Configurable Fake API Service for testing pull-sync scenarios.
class FakePullApiService implements ApiService {
  List<Referral> serverReferrals = [];
  final List<Referral> createdReferrals = [];
  bool shouldThrowFetchError = false;
  bool shouldThrowCreateError = false;
  bool shouldThrowDuplicateOnCreate = false;
  bool shouldThrowGetError = false;
  Duration simulatedDelay = Duration.zero;

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
  Future<List<Referral>> fetchReferrals({int skip = 0, int limit = 100, String? status}) async {
    if (simulatedDelay > Duration.zero) {
      await Future<void>.delayed(simulatedDelay);
    }
    if (shouldThrowFetchError) {
      throw const NetworkException('500 Internal Server Error: Failed to fetch referrals', statusCode: 500);
    }
    var list = serverReferrals;
    if (status != null) {
      list = list.where((r) => r.status.code == status).toList();
    }
    return list.skip(skip).take(limit).toList();
  }

  @override
  Future<Referral> createReferral(Referral referral) async {
    if (simulatedDelay > Duration.zero) {
      await Future<void>.delayed(simulatedDelay);
    }
    if (shouldThrowDuplicateOnCreate) {
      throw DuplicateReferralException(referral.referralToken);
    }
    if (shouldThrowCreateError) {
      throw const NetworkException('500 Internal Server Error: Database failure', statusCode: 500);
    }
    createdReferrals.add(referral);
    return referral;
  }

  @override
  Future<Referral> getReferral(String referralId) async {
    if (shouldThrowGetError) {
      throw const NetworkException('404 Not Found', statusCode: 404);
    }
    return serverReferrals.firstWhere((r) => r.referralToken == referralId);
  }


  @override
  Future<void> updateReferralStatus(String referralId, String status) async {}

  @override
  Future<List<Referral>> syncBatch(List<Referral> queuedReferrals) async => [];

  @override
  Future<List<IdentityMatch>> requestIdentityMatches(Patient incomingPatient) async => [];
}

/// Fake Connectivity Service.
class FakePullConnectivityService implements ConnectivityService {
  ConnectivityStatus _status;
  final _controller = StreamController<ConnectivityStatus>.broadcast();

  FakePullConnectivityService({ConnectivityStatus initialStatus = ConnectivityStatus.online})
      : _status = initialStatus;

  @override
  ConnectivityStatus get currentStatus => _status;

  @override
  Future<ConnectivityStatus> checkConnectivityStatus() async => _status;

  @override
  Future<bool> checkConnectivity() async => _status == ConnectivityStatus.online;

  @override
  Stream<ConnectivityStatus> get onStatusChanged => _controller.stream;

  @override
  Stream<bool> get onConnectivityChanged =>
      _controller.stream.map((s) => s == ConnectivityStatus.online);

  void setStatus(ConnectivityStatus newStatus) {
    _status = newStatus;
    _controller.add(newStatus);
  }

  @override
  void dispose() {
    _controller.close();
  }
}

/// Fake SMS Service for repository instantiation.
class FakePullSmsService implements SmsService {
  @override
  Future<SmsResult> sendReferralSms({required String recipientPhoneNumber, required Referral referral}) async {
    return SmsResult.success(payload: 'SMS', messageId: '1');
  }

  @override
  String generateSmsPayload(Referral referral) => 'SMS';
}

void main() {
  late AppDatabase db;
  late LocalStorageService localStorage;
  late FakePullApiService apiService;
  late FakePullConnectivityService connectivityService;
  late SyncService syncService;
  late SyncRepository syncRepository;
  late ReferralRepository referralRepository;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    localStorage = LocalStorageServiceImpl(db);
    apiService = FakePullApiService();
    connectivityService = FakePullConnectivityService();
    syncService = SyncService(
      localStorage: localStorage,
      apiService: apiService,
      connectivityService: connectivityService,
    );
    syncRepository = SyncRepository(localStorage: localStorage, syncService: syncService);
    referralRepository = ReferralRepository(
      localStorage: localStorage,
      apiService: apiService,
      connectivityService: connectivityService,
      smsService: FakePullSmsService(),
      syncService: syncService,
    );
  });


  tearDown(() async {
    connectivityService.dispose();
    await localStorage.close();
  });

  group('Phase 2 Pull-Sync Comprehensive Tests', () {
    // 1. Server has one referral -> pull-sync imports it into local SQLite
    test('1. Server has one referral -> pull-sync imports it into local SQLite', () async {
      final serverRef = Referral(
        id: 'RC-SRV-001',
        referralToken: 'RC-SRV-001',
        patientId: '',
        patient: Patient(
          id: '',
          fullName: 'Aarav Sharma',
          age: 28,
          gender: 'Male',
          villageOrLocation: 'Zone A',
          contactNumber: '+91 9876543210',
          createdAt: DateTime.now(),
        ),
        sourceFacilityId: 'PHC-01',
        destinationFacilityId: 'DH-01',
        referralReason: 'Chest pain',
        urgency: ReferralUrgency.urgent,
        status: ReferralStatus.created,
        syncState: SyncState.synced,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      apiService.serverReferrals = [serverRef];

      final pulled = await syncService.pullReferralsFromServer();
      expect(pulled.length, equals(1));
      expect(pulled.first.referralToken, equals('RC-SRV-001'));

      final localList = await localStorage.getAllDomainReferrals();
      expect(localList.length, equals(1));
      expect(localList.first.referralToken, equals('RC-SRV-001'));
      expect(localList.first.syncState, equals(SyncState.synced));
    });

    // 2. Pulled referral gets a valid local Patient.id
    test('2. Pulled referral gets a valid local integer Patient.id', () async {
      final serverRef = Referral(
        id: 'RC-SRV-002',
        referralToken: 'RC-SRV-002',
        patientId: '',
        patient: Patient(
          id: '',
          fullName: 'Bhavna Roy',
          age: 34,
          gender: 'Female',
          contactNumber: '+91 9876500000',
          villageOrLocation: 'Zone B',
          createdAt: DateTime.now(),
        ),
        sourceFacilityId: 'PHC-02',
        destinationFacilityId: 'DH-02',
        referralReason: 'Routine antenatal check',
        urgency: ReferralUrgency.routine,
        status: ReferralStatus.created,
        syncState: SyncState.synced,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      apiService.serverReferrals = [serverRef];

      final pulled = await syncService.pullReferralsFromServer();
      final localRef = pulled.first;

      final intId = int.tryParse(localRef.patientId);
      expect(intId, isNotNull);
      expect(intId!, isPositive);

      final localPatient = await localStorage.getPatientById(intId);
      expect(localPatient, isNotNull);
      expect(localPatient!.name, equals('Bhavna Roy'));
    });

    // 3. Pulled referral does NOT use referralToken as Patient.id
    test('3. Pulled referral does NOT use referralToken as Patient.id', () async {
      final serverRef = Referral(
        id: 'RC-SRV-003',
        referralToken: 'RC-SRV-003',
        patientId: '',
        patient: Patient(
          id: '',
          fullName: 'Chetan Verma',
          age: 45,
          gender: 'Male',
          contactNumber: '+91 9876511111',
          villageOrLocation: 'Zone C',
          createdAt: DateTime.now(),
        ),
        sourceFacilityId: 'PHC-03',
        destinationFacilityId: 'DH-03',
        referralReason: 'Diabetic checkup',
        urgency: ReferralUrgency.routine,
        status: ReferralStatus.created,
        syncState: SyncState.synced,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      apiService.serverReferrals = [serverRef];

      final pulled = await syncService.pullReferralsFromServer();
      expect(pulled.first.patientId, isNot(equals('RC-SRV-003')));
      expect(pulled.first.patient?.id, isNot(equals('RC-SRV-003')));
    });

    // 4. Pulling the same referral twice creates only one local referral
    test('4. Pulling the same referral twice creates only one local referral', () async {
      final serverRef = Referral(
        id: 'RC-SRV-004',
        referralToken: 'RC-SRV-004',
        patientId: '',
        patient: Patient(
          id: '',
          fullName: 'Deepa Sen',
          age: 52,
          gender: 'Female',
          contactNumber: '+91 9876522222',
          villageOrLocation: 'Zone D',
          createdAt: DateTime.now(),
        ),
        sourceFacilityId: 'PHC-04',
        destinationFacilityId: 'DH-04',
        referralReason: 'Joint pain',
        urgency: ReferralUrgency.routine,
        status: ReferralStatus.created,
        syncState: SyncState.synced,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      apiService.serverReferrals = [serverRef];

      await syncService.pullReferralsFromServer();
      await syncService.pullReferralsFromServer();

      final allRefs = await localStorage.getAllDomainReferrals();
      expect(allRefs.length, equals(1));
      expect(allRefs.first.referralToken, equals('RC-SRV-004'));
    });

    // 5. Two referrals belonging to the same patient reuse the same local Patient.id
    test('5. Two referrals for the same patient reuse the same local Patient.id', () async {
      final patient = Patient(
        id: '',
        fullName: 'Eshaan Joshi',
        age: 60,
        gender: 'Male',
        contactNumber: '+91 9876533333',
        villageOrLocation: 'Zone E',
        createdAt: DateTime.now(),
      );

      final ref1 = Referral(
        id: 'RC-SRV-005A',
        referralToken: 'RC-SRV-005A',
        patientId: '',
        patient: patient,
        sourceFacilityId: 'PHC-01',
        destinationFacilityId: 'DH-01',
        referralReason: 'Initial visit',
        urgency: ReferralUrgency.routine,
        status: ReferralStatus.completed,
        syncState: SyncState.synced,
        createdAt: DateTime.now().subtract(const Duration(days: 5)),
        updatedAt: DateTime.now().subtract(const Duration(days: 4)),
      );

      final ref2 = Referral(
        id: 'RC-SRV-005B',
        referralToken: 'RC-SRV-005B',
        patientId: '',
        patient: patient,
        sourceFacilityId: 'PHC-01',
        destinationFacilityId: 'DH-01',
        referralReason: 'Follow-up visit',
        urgency: ReferralUrgency.routine,
        status: ReferralStatus.created,
        syncState: SyncState.synced,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      apiService.serverReferrals = [ref1, ref2];
      await syncService.pullReferralsFromServer();

      final allRefs = await localStorage.getAllDomainReferrals();
      expect(allRefs.length, equals(2));
      expect(allRefs[0].patientId, equals(allRefs[1].patientId));

      final allPatients = await localStorage.getAllPatients();
      expect(allPatients.length, equals(1));
      expect(allPatients.first.name, equals('Eshaan Joshi'));
    });

    // 6. Two different patients remain separate
    test('6. Two different patients remain separate in local SQLite', () async {
      final ref1 = Referral(
        id: 'RC-SRV-006A',
        referralToken: 'RC-SRV-006A',
        patientId: '',
        patient: Patient(
          id: '',
          fullName: 'Farhan Khan',
          age: 30,
          gender: 'Male',
          contactNumber: '+91 9876544441',
          villageOrLocation: 'Zone F1',
          createdAt: DateTime.now(),
        ),
        sourceFacilityId: 'PHC-01',
        destinationFacilityId: 'DH-01',
        referralReason: 'Viral fever',
        urgency: ReferralUrgency.routine,
        status: ReferralStatus.created,
        syncState: SyncState.synced,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final ref2 = Referral(
        id: 'RC-SRV-006B',
        referralToken: 'RC-SRV-006B',
        patientId: '',
        patient: Patient(
          id: '',
          fullName: 'Geeta Nair',
          age: 42,
          gender: 'Female',
          contactNumber: '+91 9876544442',
          villageOrLocation: 'Zone F2',
          createdAt: DateTime.now(),
        ),
        sourceFacilityId: 'PHC-01',
        destinationFacilityId: 'DH-01',
        referralReason: 'Hypertension',
        urgency: ReferralUrgency.urgent,
        status: ReferralStatus.created,
        syncState: SyncState.synced,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      apiService.serverReferrals = [ref1, ref2];
      await syncService.pullReferralsFromServer();

      final allPatients = await localStorage.getAllPatients();
      expect(allPatients.length, equals(2));
      expect(allPatients.map((p) => p.name), containsAll(['Farhan Khan', 'Geeta Nair']));
    });

    // 7. URGENT/EMERGENCY/ROUTINE survive pull-sync
    test('7. URGENT, EMERGENCY, and ROUTINE survive pull-sync', () async {
      final refRoutine = Referral(
        id: 'RC-URG-ROUTINE',
        referralToken: 'RC-URG-ROUTINE',
        patientId: '',
        patient: Patient(id: '', fullName: 'P1', age: 20, gender: 'Male', contactNumber: '+91 9001', villageOrLocation: 'V1', createdAt: DateTime.now()),
        sourceFacilityId: 'PHC-01',
        destinationFacilityId: 'DH-01',
        referralReason: 'Checkup',
        urgency: ReferralUrgency.routine,
        status: ReferralStatus.created,
        syncState: SyncState.synced,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final refUrgent = Referral(
        id: 'RC-URG-URGENT',
        referralToken: 'RC-URG-URGENT',
        patientId: '',
        patient: Patient(id: '', fullName: 'P2', age: 30, gender: 'Female', contactNumber: '+91 9002', villageOrLocation: 'V2', createdAt: DateTime.now()),
        sourceFacilityId: 'PHC-01',
        destinationFacilityId: 'DH-01',
        referralReason: 'Bleeding',
        urgency: ReferralUrgency.urgent,
        status: ReferralStatus.created,
        syncState: SyncState.synced,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final refEmergency = Referral(
        id: 'RC-URG-EMERGENCY',
        referralToken: 'RC-URG-EMERGENCY',
        patientId: '',
        patient: Patient(id: '', fullName: 'P3', age: 40, gender: 'Male', contactNumber: '+91 9003', villageOrLocation: 'V3', createdAt: DateTime.now()),
        sourceFacilityId: 'PHC-01',
        destinationFacilityId: 'DH-01',
        referralReason: 'Cardiac arrest',
        urgency: ReferralUrgency.emergency,
        status: ReferralStatus.created,
        syncState: SyncState.synced,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      apiService.serverReferrals = [refRoutine, refUrgent, refEmergency];
      await syncService.pullReferralsFromServer();

      final r1 = await localStorage.getDomainReferralById('RC-URG-ROUTINE');
      final r2 = await localStorage.getDomainReferralById('RC-URG-URGENT');
      final r3 = await localStorage.getDomainReferralById('RC-URG-EMERGENCY');

      expect(r1!.urgency, equals(ReferralUrgency.routine));
      expect(r2!.urgency, equals(ReferralUrgency.urgent));
      expect(r3!.urgency, equals(ReferralUrgency.emergency));
    });

    // 8. Existing local PENDING referral is not overwritten by pull
    test('8. Existing local PENDING referral is not overwritten by pull', () async {
      // Create local offline referral (PENDING)
      await localStorage.createReferralTransaction(
        patientName: 'Local Pending Patient',
        patientAge: 25,
        patientGender: 'Female',
        sourceFacility: 'PHC-01',
        destinationFacility: 'DH-01',
        reason: 'Local unpushed reason',
        customReferralId: 'RC-PENDING-001',
      );

      // Server tries to send a different status
      final staleServerRef = Referral(
        id: 'RC-PENDING-001',
        referralToken: 'RC-PENDING-001',
        patientId: '',
        patient: Patient(id: '', fullName: 'Local Pending Patient', age: 25, gender: 'Female', villageOrLocation: 'Loc', createdAt: DateTime.now()),
        sourceFacilityId: 'PHC-01',
        destinationFacilityId: 'DH-01',
        referralReason: 'Stale server reason',
        urgency: ReferralUrgency.routine,
        status: ReferralStatus.received,
        syncState: SyncState.synced,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      apiService.serverReferrals = [staleServerRef];

      await syncService.pullReferralsFromServer();

      final localRef = await localStorage.getDomainReferralById('RC-PENDING-001');
      expect(localRef!.syncState, equals(SyncState.pendingSync));
      expect(localRef.referralReason, equals('Local unpushed reason'));
    });

    // 9. Existing SYNCED referral can be updated from a newer server response
    test('9. Existing SYNCED referral can be updated from a newer server response', () async {
      // Ingest initial referral as SYNCED
      final initialRef = Referral(
        id: 'RC-SYNCED-001',
        referralToken: 'RC-SYNCED-001',
        patientId: '',
        patient: Patient(id: '', fullName: 'Harish Rao', age: 48, gender: 'Male', contactNumber: '+91 9191919191', villageOrLocation: 'Zone H', createdAt: DateTime.now()),
        sourceFacilityId: 'PHC-01',
        destinationFacilityId: 'DH-01',
        referralReason: 'Fever',
        urgency: ReferralUrgency.routine,
        status: ReferralStatus.created,
        syncState: SyncState.synced,
        createdAt: DateTime.now().subtract(const Duration(hours: 5)),
        updatedAt: DateTime.now().subtract(const Duration(hours: 5)),
      );
      await localStorage.upsertReferralFromSync(initialRef);

      // Newer server status (PATIENT_ARRIVED)
      final updatedServerRef = Referral(
        id: 'RC-SYNCED-001',
        referralToken: 'RC-SYNCED-001',
        patientId: '',
        patient: initialRef.patient,
        sourceFacilityId: 'PHC-01',
        destinationFacilityId: 'DH-01',
        referralReason: 'Fever',
        urgency: ReferralUrgency.routine,
        status: ReferralStatus.patientArrived,
        syncState: SyncState.synced,
        createdAt: initialRef.createdAt,
        updatedAt: DateTime.now(),
      );
      apiService.serverReferrals = [updatedServerRef];

      await syncService.pullReferralsFromServer();

      final localRef = await localStorage.getDomainReferralById('RC-SYNCED-001');
      expect(localRef!.status, equals(ReferralStatus.patientArrived));
    });

    // 10. Offline/network failure does not corrupt local data
    test('10. Offline / network failure does not corrupt local data', () async {
      await localStorage.createReferralTransaction(
        patientName: 'Safe Patient',
        patientAge: 35,
        patientGender: 'Male',
        sourceFacility: 'PHC-01',
        destinationFacility: 'DH-01',
        reason: 'Safe reason',
        customReferralId: 'RC-SAFE-001',
      );

      connectivityService.setStatus(ConnectivityStatus.offline);

      await expectLater(
        syncService.pullReferralsFromServer(),
        throwsA(isA<NetworkException>()),
      );

      final localRef = await localStorage.getDomainReferralById('RC-SAFE-001');
      expect(localRef, isNotNull);
      expect(localRef!.referralReason, equals('Safe reason'));
    });

    // 11. Push-sync still works after pull-sync is added
    test('11. Full bidirectional sync executes PUSH then PULL', () async {
      // Create local offline referral to be pushed
      await localStorage.createReferralTransaction(
        patientName: 'Push Patient',
        patientAge: 29,
        patientGender: 'Female',
        sourceFacility: 'PHC-01',
        destinationFacility: 'DH-01',
        reason: 'Local push reason',
        customReferralId: 'RC-PUSH-001',
      );

      // Setup server with a different referral to be pulled
      final serverRef = Referral(
        id: 'RC-PULL-001',
        referralToken: 'RC-PULL-001',
        patientId: '',
        patient: Patient(id: '', fullName: 'Pull Patient', age: 31, gender: 'Male', contactNumber: '+91 9777777777', villageOrLocation: 'Loc P', createdAt: DateTime.now()),
        sourceFacilityId: 'PHC-02',
        destinationFacilityId: 'DH-02',
        referralReason: 'Server pull reason',
        urgency: ReferralUrgency.urgent,
        status: ReferralStatus.created,
        syncState: SyncState.synced,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      apiService.serverReferrals = [serverRef];

      // Trigger full sync
      final syncedCount = await syncService.syncPendingReferrals();
      expect(syncedCount, equals(1)); // 1 pushed

      // Verify pushed item was sent to API
      expect(apiService.createdReferrals.length, equals(1));
      expect(apiService.createdReferrals.first.referralToken, equals('RC-PUSH-001'));

      // Verify pulled item is now present in local SQLite
      final pulledLocal = await localStorage.getDomainReferralById('RC-PULL-001');
      expect(pulledLocal, isNotNull);
      expect(pulledLocal!.referralReason, equals('Server pull reason'));
    });

    // 12. Multiple sync calls cannot run concurrently
    test('12. Concurrency guard prevents overlapping synchronization runs', () async {
      apiService.simulatedDelay = const Duration(milliseconds: 100);
      apiService.serverReferrals = [
        Referral(
          id: 'RC-CONCUR-01',
          referralToken: 'RC-CONCUR-01',
          patientId: '',
          patient: Patient(id: '', fullName: 'Concurrent P', age: 20, gender: 'Male', contactNumber: '+91 9999900000', villageOrLocation: 'CLoc', createdAt: DateTime.now()),
          sourceFacilityId: 'PHC-01',
          destinationFacilityId: 'DH-01',
          referralReason: 'Test',
          urgency: ReferralUrgency.routine,
          status: ReferralStatus.created,
          syncState: SyncState.synced,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        )
      ];

      final future1 = syncService.pullReferralsFromServer();
      final future2 = syncService.pullReferralsFromServer(); // Should be rejected by guard

      final res1 = await future1;
      final res2 = await future2;

      expect(res1.length, equals(1));
      expect(res2.isEmpty, isTrue); // Skipped because sync was in progress
    });

    // 13. Empty server response is handled correctly
    test('13. Empty server response is handled gracefully', () async {
      apiService.serverReferrals = [];

      final pulled = await syncService.pullReferralsFromServer();
      expect(pulled.isEmpty, isTrue);

      final allRefs = await localStorage.getAllDomainReferrals();
      expect(allRefs.isEmpty, isTrue);
    });

    // 14. API error is surfaced correctly and does not report successful synchronization
    test('14. API 500 error is surfaced correctly in SyncProvider and throws in SyncService', () async {
      apiService.shouldThrowFetchError = true;

      await expectLater(
        syncService.pullReferralsFromServer(),
        throwsA(isA<NetworkException>()),
      );

      final syncProvider = SyncProvider(syncRepository: syncRepository);
      await expectLater(
        syncProvider.pullReferrals(),
        throwsA(isA<NetworkException>()),
      );
      expect(syncProvider.syncError, contains('Pull sync failed'));
    });

    // 15. ReferralRepository pullReferralsFromServer works cleanly
    test('15. ReferralRepository.pullReferralsFromServer fetches and updates SQLite', () async {
      final serverRef = Referral(
        id: 'RC-REPO-001',
        referralToken: 'RC-REPO-001',
        patientId: '',
        patient: Patient(id: '', fullName: 'Repo Patient', age: 40, gender: 'Male', villageOrLocation: 'Repo Zone', createdAt: DateTime.now()),
        sourceFacilityId: 'PHC-01',
        destinationFacilityId: 'DH-01',
        referralReason: 'Repo Reason',
        urgency: ReferralUrgency.routine,
        status: ReferralStatus.created,
        syncState: SyncState.synced,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      apiService.serverReferrals = [serverRef];

      final pulled = await referralRepository.pullReferralsFromServer();
      expect(pulled.length, equals(1));
      expect(pulled.first.referralToken, equals('RC-REPO-001'));

      final allLocal = await referralRepository.getAllReferrals();
      expect(allLocal.length, equals(1));
      expect(allLocal.first.patient?.fullName, equals('Repo Patient'));
    });

    // 16. Ambiguous phone matching returns null
    test('16. Ambiguous phone match returns null and does not blindly select first row', () async {
      await db.patientDao.insertPatient(
        PatientsCompanion.insert(
          name: 'Patient One',
          age: 30,
          gender: 'Male',
          phone: const Value('+91 9999911111'),
        ),
      );
      await db.patientDao.insertPatient(
        PatientsCompanion.insert(
          name: 'Patient Two',
          age: 40,
          gender: 'Female',
          phone: const Value('9999911111'), // Same normalized phone
        ),
      );

      final match = await db.patientDao.findPatientByPhone('+91 99999 11111');
      expect(match, isNull); // Must return null due to ambiguity
    });

    // 17. Ambiguous demographic matching returns null
    test('17. Ambiguous demographic match returns null when location is missing or identical', () async {
      await db.patientDao.insertPatient(
        PatientsCompanion.insert(
          name: 'Same Name',
          age: 25,
          gender: 'Male',
        ),
      );
      await db.patientDao.insertPatient(
        PatientsCompanion.insert(
          name: 'Same Name',
          age: 25,
          gender: 'Male',
        ),
      );

      final match = await db.patientDao.findPatientByDemographics(
        name: 'Same Name',
        age: 25,
        gender: 'Male',
      );
      expect(match, isNull); // Ambiguous demographics return null
    });

    // 18. Unique demographic matching returns single candidate
    test('18. Unique demographic match correctly returns the single candidate', () async {
      final p1Id = await db.patientDao.insertPatient(
        PatientsCompanion.insert(
          name: 'Unique Person',
          age: 50,
          gender: 'Female',
          location: const Value('Sector 5'),
        ),
      );

      final match = await db.patientDao.findPatientByDemographics(
        name: 'Unique Person',
        age: 50,
        gender: 'Female',
        location: 'Sector 5',
      );
      expect(match, isNotNull);
      expect(match!.id, equals(p1Id));
    });

    // 19. Pending local referral + pull-sync does NOT create an extra patient
    test('19. Existing PENDING referral does not create orphan patient on server pull', () async {
      // 1. Create a local offline referral (PENDING)
      await referralRepository.createReferralOffline(
        patientName: 'Pending Patient',
        patientAge: 29,
        patientGender: 'Male',
        patientPhone: '+91 8888877777',
        sourceFacility: 'PHC-01',
        destinationFacility: 'DH-01',
        reason: 'Local unpushed reason',
        customReferralId: 'RC-PENDING-001',
        autoSync: false,
      );

      final patientCountBefore = (await db.select(db.patients).get()).length;


      // 2. Server sends an update for the same referral token
      final serverRef = Referral(
        id: 'RC-PENDING-001',
        referralToken: 'RC-PENDING-001',
        patientId: '',
        patient: Patient(
          id: '',
          fullName: 'Stale Server Demographics',
          age: 35,
          gender: 'Other',
          contactNumber: '+91 1111122222',
          villageOrLocation: 'Server City',
          createdAt: DateTime.now(),
        ),
        sourceFacilityId: 'PHC-01',
        destinationFacilityId: 'DH-01',
        referralReason: 'Stale server reason',
        urgency: ReferralUrgency.routine,
        status: ReferralStatus.created,
        syncState: SyncState.synced,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      apiService.serverReferrals = [serverRef];

      // 3. Execute Pull-Sync
      final pulled = await syncService.pullReferralsFromServer();
      expect(pulled.length, equals(1));
      expect(pulled.first.referralReason, equals('Local unpushed reason'));

      // 4. Verify no new patient was created
      final patientCountAfter = (await db.select(db.patients).get()).length;
      expect(patientCountAfter, equals(patientCountBefore));
    });

    // 20. 409 Duplicate on Push is reconciled via getReferral
    test('20. DuplicateReferralException (409) is reconciled as SUCCESS if server has referral', () async {
      // Create local offline referral
      await referralRepository.createReferralOffline(
        patientName: 'Dup Check Patient',
        patientAge: 32,
        patientGender: 'Female',
        sourceFacility: 'PHC-01',
        destinationFacility: 'DH-01',
        reason: 'Reconciliation test',
        customReferralId: 'RC-DUP-001',
        autoSync: false,
      );


      // Server already has this referral
      apiService.serverReferrals = [
        Referral(
          id: 'RC-DUP-001',
          referralToken: 'RC-DUP-001',
          patientId: '',
          sourceFacilityId: 'PHC-01',
          destinationFacilityId: 'DH-01',
          referralReason: 'Reconciliation test',
          urgency: ReferralUrgency.routine,
          status: ReferralStatus.created,
          syncState: SyncState.synced,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        )
      ];
      // When POST is called, backend throws 409
      apiService.shouldThrowDuplicateOnCreate = true;

      // Execute push sync
      final synced = await syncService.syncPendingReferrals();
      expect(synced, equals(1));

      // Local referral should be marked SYNCED
      final localRef = await localStorage.getDomainReferralById('RC-DUP-001');
      expect(localRef!.syncState, equals(SyncState.synced));

      // Queue item should be marked SUCCESS
      final queueItems = await (db.select(db.syncQueue)).get();
      expect(queueItems.first.status, equals('SUCCESS'));
      expect(queueItems.first.retryCount, equals(0));
    });

    // 21. 409 Duplicate on Push marks FAILED if getReferral fails
    test('21. DuplicateReferralException (409) marks FAILED if getReferral fails', () async {
      await referralRepository.createReferralOffline(
        patientName: 'Dup Fail Patient',
        patientAge: 32,
        patientGender: 'Female',
        sourceFacility: 'PHC-01',
        destinationFacility: 'DH-01',
        reason: 'Reconciliation fail test',
        customReferralId: 'RC-DUP-FAIL-001',
        autoSync: false,
      );

      apiService.shouldThrowDuplicateOnCreate = true;
      apiService.shouldThrowGetError = true;

      final synced = await syncService.syncPendingReferrals();
      expect(synced, equals(0));

      final localRef = await localStorage.getDomainReferralById('RC-DUP-FAIL-001');
      expect(localRef!.syncState, equals(SyncState.pendingSync));

      final queueItems = await (db.select(db.syncQueue)).get();
      expect(queueItems.first.status, equals('FAILED'));
      expect(queueItems.first.retryCount, equals(1));
    });

    // 22. Shared SyncService concurrency lock across ReferralRepository and SyncRepository
    test('22. ReferralRepository and SyncRepository share the same concurrency lock', () async {
      apiService.simulatedDelay = const Duration(milliseconds: 100);
      apiService.serverReferrals = [
        Referral(
          id: 'RC-LOCK-001',
          referralToken: 'RC-LOCK-001',
          patientId: '',
          sourceFacilityId: 'PHC-01',
          destinationFacilityId: 'DH-01',
          referralReason: 'Lock test',
          urgency: ReferralUrgency.routine,
          status: ReferralStatus.created,
          syncState: SyncState.synced,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        )
      ];

      // Launch pull via syncRepository and referralRepository concurrently
      final fut1 = syncRepository.pullReferrals();
      final fut2 = referralRepository.pullReferralsFromServer();

      final r1 = await fut1;
      final r2 = await fut2;

      // One succeeds, one is rejected by concurrency lock
      expect(r1.length + r2.length, equals(1));
    });
  });
}
