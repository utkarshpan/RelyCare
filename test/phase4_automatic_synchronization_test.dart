import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relycare/models/identity_match.dart';
import 'package:relycare/models/patient.dart';
import 'package:relycare/models/referral.dart';
import 'package:relycare/models/referral_status.dart';
import 'package:relycare/models/user_model.dart';
import 'package:relycare/providers/connectivity_provider.dart';
import 'package:relycare/providers/referral_provider.dart';
import 'package:relycare/providers/sync_provider.dart';
import 'package:relycare/repositories/patient_repository.dart';
import 'package:relycare/repositories/referral_repository.dart';
import 'package:relycare/repositories/sync_repository.dart';
import 'package:relycare/services/api/api_service.dart';
import 'package:relycare/services/connectivity/connectivity_service.dart';
import 'package:relycare/services/local_storage/app_database.dart';
import 'package:relycare/services/local_storage/local_storage_service.dart';
import 'package:relycare/services/sms/sms_service.dart';
import 'package:relycare/services/sync/sync_service.dart';

/// Fake API service for deterministic testing of sync scenarios.
class FakeApiService implements ApiService {
  final List<Referral> createdReferrals = [];
  bool shouldThrowError = false;
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
  Future<Referral> createReferral(Referral referral) async {

    if (simulatedDelay > Duration.zero) {
      await Future<void>.delayed(simulatedDelay);
    }
    if (shouldThrowError) {
      throw Exception('500 Internal Server Error: Remote database unavailable');
    }
    createdReferrals.add(referral);
    return referral;
  }

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

/// Fake connectivity service for simulating network changes.
class FakeConnectivityService implements ConnectivityService {
  ConnectivityStatus _status;
  final _controller = StreamController<ConnectivityStatus>.broadcast();

  FakeConnectivityService({ConnectivityStatus initialStatus = ConnectivityStatus.online})
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 4: Automatic Synchronization Engine Tests', () {
    late AppDatabase db;
    late LocalStorageService localStorage;
    late FakeApiService fakeApi;
    late FakeConnectivityService fakeConnectivity;
    late SyncService syncService;
    late SyncRepository syncRepository;
    late ReferralRepository referralRepository;
    late PatientRepository patientRepository;
    late ReferralProvider referralProvider;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      localStorage = LocalStorageServiceImpl(db);
      fakeApi = FakeApiService();
      fakeConnectivity = FakeConnectivityService(initialStatus: ConnectivityStatus.online);
      syncService = SyncService(
        localStorage: localStorage,
        apiService: fakeApi,
        connectivityService: fakeConnectivity,
      );
      syncRepository = SyncRepository(
        localStorage: localStorage,
        syncService: syncService,
      );
      referralRepository = ReferralRepository(
        localStorage: localStorage,
        apiService: fakeApi,
        connectivityService: fakeConnectivity,
        smsService: MockSmsService(),
      );
      patientRepository = PatientRepository(
        localStorage: localStorage,
        apiService: fakeApi,
        connectivityService: fakeConnectivity,
      );
      referralProvider = ReferralProvider(
        referralRepository: referralRepository,
      );
    });

    tearDown(() async {
      fakeConnectivity.dispose();
      await localStorage.close();
    });

    test('Test A: ONLINE + one PENDING queue item -> API called once, queue becomes SUCCESS, referral becomes SYNCED', () async {
      // 1. Create referral offline (stored in SQLite with status CREATED, syncStatus PENDING, queue item PENDING)
      final createdReferral = await referralProvider.createReferral(
        patientName: 'Radha Devi',
        patientAge: 29,
        patientGender: 'Female',
        sourceFacility: 'PHC Rampur',
        destinationFacility: 'District Hospital East',
        reason: 'Postpartum hemorrhage',
        autoSync: false,
      );
      expect(createdReferral, isNotNull);

      // Verify initial offline state
      var pendingItems = await localStorage.getPendingSyncItems();
      expect(pendingItems.length, equals(1));
      expect(pendingItems.first.status, equals('PENDING'));
      expect(fakeApi.createdReferrals.isEmpty, isTrue);

      // 2. Trigger sync while ONLINE
      final syncedCount = await syncService.syncPendingReferrals();

      // 3. Verify sync results
      expect(syncedCount, equals(1));
      expect(fakeApi.createdReferrals.length, equals(1));
      expect(fakeApi.createdReferrals.first.referralToken, equals(createdReferral!.referralToken));

      // 4. Verify queue item in SQLite became SUCCESS
      pendingItems = await localStorage.getPendingSyncItems();
      expect(pendingItems.isEmpty, isTrue); // No more pending items

      final allQueueRows = await db.select(db.syncQueue).get();
      expect(allQueueRows.length, equals(1));
      expect(allQueueRows.first.status, equals('SUCCESS'));

      // 5. Verify local referral syncStatus in SQLite updated to SYNCED
      final updatedReferral = await referralRepository.getReferralById(createdReferral.id);
      expect(updatedReferral, isNotNull);
      expect(updatedReferral!.syncState, equals(SyncState.synced));
      expect(updatedReferral.status, equals(ReferralStatus.created));
    });

    test('Test B: ONLINE + multiple PENDING queue items -> processed sequentially, all become SUCCESS and SYNCED', () async {
      // Create 3 referrals offline
      final ref1 = await referralProvider.createReferral(
        patientName: 'Patient 1',
        patientAge: 30,
        patientGender: 'Male',
        sourceFacility: 'PHC A',
        destinationFacility: 'DH A',
        reason: 'Reason 1',
        autoSync: false,
      );
      final ref2 = await referralProvider.createReferral(
        patientName: 'Patient 2',
        patientAge: 40,
        patientGender: 'Female',
        sourceFacility: 'PHC B',
        destinationFacility: 'DH B',
        reason: 'Reason 2',
        autoSync: false,
      );
      final ref3 = await referralProvider.createReferral(
        patientName: 'Patient 3',
        patientAge: 50,
        patientGender: 'Other',
        sourceFacility: 'PHC C',
        destinationFacility: 'DH C',
        reason: 'Reason 3',
        autoSync: false,
      );

      final initialPending = await localStorage.getPendingSyncItems();
      expect(initialPending.length, equals(3));

      // Trigger sync
      final syncedCount = await syncService.syncPendingReferrals();
      expect(syncedCount, equals(3));
      expect(fakeApi.createdReferrals.length, equals(3));

      // Verify FIFO ordering
      expect(fakeApi.createdReferrals[0].referralToken, equals(ref1!.referralToken));
      expect(fakeApi.createdReferrals[1].referralToken, equals(ref2!.referralToken));
      expect(fakeApi.createdReferrals[2].referralToken, equals(ref3!.referralToken));

      // Verify all queue items in SQLite became SUCCESS
      final pendingRemaining = await localStorage.getPendingSyncItems();
      expect(pendingRemaining.isEmpty, isTrue);

      final allQueue = await db.select(db.syncQueue).get();
      expect(allQueue.every((item) => item.status == 'SUCCESS'), isTrue);

      // Verify all local referrals are SYNCED
      final allRefs = await referralRepository.getAllReferrals();
      expect(allRefs.length, equals(3));
      expect(allRefs.every((r) => r.syncState == SyncState.synced), isTrue);
    });

    test('Test C: OFFLINE + PENDING queue item -> API is NOT called, queue remains PENDING', () async {
      fakeConnectivity.setStatus(ConnectivityStatus.offline);

      final ref = await referralProvider.createReferral(
        patientName: 'Offline Patient',
        patientAge: 25,
        patientGender: 'Female',
        sourceFacility: 'PHC Remote',
        destinationFacility: 'DH Central',
        reason: 'Severe malaria',
      );

      // Trigger sync while OFFLINE
      final syncedCount = await syncService.syncPendingReferrals();
      expect(syncedCount, equals(0));
      expect(fakeApi.createdReferrals.isEmpty, isTrue);

      // Queue item must remain PENDING
      final pending = await localStorage.getPendingSyncItems();
      expect(pending.length, equals(1));
      expect(pending.first.status, equals('PENDING'));

      // Referral remains unsynced
      final fetched = await referralRepository.getReferralById(ref!.id);
      expect(fetched!.syncState, equals(SyncState.pendingSync));
    });

    test('Test D: Calling syncPendingReferrals twice concurrently -> only one sync executes, no duplicate submissions', () async {
      fakeApi.simulatedDelay = const Duration(milliseconds: 50);

      await referralProvider.createReferral(
        patientName: 'Concurrent Patient',
        patientAge: 35,
        patientGender: 'Male',
        sourceFacility: 'PHC Alpha',
        destinationFacility: 'DH Beta',
        reason: 'Fracture',
        autoSync: false,
      );

      // Fire two sync calls at the same time
      final future1 = syncService.syncPendingReferrals();
      final future2 = syncService.syncPendingReferrals();

      final results = await Future.wait([future1, future2]);

      // One pass synced 1 item, the other returned 0 due to concurrency guard
      expect(results, contains(1));
      expect(results, contains(0));
      expect(fakeApi.createdReferrals.length, equals(1),
          reason: 'API must only be called once, no duplicates');
    });

    test('Test E: API failure -> referral is NOT marked SYNCED and queue item is marked FAILED without deleting data', () async {
      fakeApi.shouldThrowError = true;

      final ref = await referralProvider.createReferral(
        patientName: 'Error Case Patient',
        patientAge: 60,
        patientGender: 'Male',
        sourceFacility: 'PHC West',
        destinationFacility: 'DH West',
        reason: 'Stroke evaluation',
        autoSync: false,
      );

      final syncedCount = await syncService.syncPendingReferrals();
      expect(syncedCount, equals(0));

      // Queue item must be marked FAILED (not SUCCESS)
      final allQueueRows = await db.select(db.syncQueue).get();
      expect(allQueueRows.length, equals(1));
      expect(allQueueRows.first.status, equals('FAILED'));

      // Referral must NOT be marked SYNCED
      final fetched = await referralRepository.getReferralById(ref!.id);
      expect(fetched!.syncState, equals(SyncState.pendingSync));

      // Local patient and referral records must remain safely preserved in SQLite
      final allPatients = await patientRepository.getAllPatients();
      expect(allPatients.length, equals(1));
    });

    test('Test F: Connectivity transition OFFLINE -> ONLINE automatically triggers sync via SyncProvider', () async {
      fakeConnectivity.setStatus(ConnectivityStatus.offline);
      final connectivityProvider = ConnectivityProvider(connectivityService: fakeConnectivity);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final syncProvider = SyncProvider(
        syncRepository: syncRepository,
        connectivityProvider: connectivityProvider,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Create referral offline
      await referralProvider.createReferral(
        patientName: 'Auto Sync Patient',
        patientAge: 22,
        patientGender: 'Female',
        sourceFacility: 'PHC Subcenter',
        destinationFacility: 'District Hospital',
        reason: 'Labor onset',
      );

      expect(fakeApi.createdReferrals.isEmpty, isTrue);

      // Transition connectivity from OFFLINE to ONLINE
      fakeConnectivity.setStatus(ConnectivityStatus.online);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Automatic sync must have executed
      expect(fakeApi.createdReferrals.length, equals(1));
      expect(fakeApi.createdReferrals.first.patient?.fullName, equals('Auto Sync Patient'));

      connectivityProvider.dispose();
      syncProvider.dispose();
    });

    test('Test G: App starts ONLINE -> pending queue is automatically processed upon initialization', () async {
      // 1. Create a referral in SQLite beforehand
      await referralProvider.createReferral(
        patientName: 'Startup Sync Patient',
        patientAge: 44,
        patientGender: 'Male',
        sourceFacility: 'PHC Delta',
        destinationFacility: 'DH Delta',
        reason: 'Chest pain',
        autoSync: false,
      );

      expect(fakeApi.createdReferrals.isEmpty, isTrue);

      // 2. Start ConnectivityProvider (ONLINE) and SyncProvider
      final connectivityProvider = ConnectivityProvider(connectivityService: fakeConnectivity);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final syncProvider = SyncProvider(
        syncRepository: syncRepository,
        connectivityProvider: connectivityProvider,
      );

      // Wait for async startup sync
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(fakeApi.createdReferrals.length, equals(1));
      expect(fakeApi.createdReferrals.first.patient?.fullName, equals('Startup Sync Patient'));

      connectivityProvider.dispose();
      syncProvider.dispose();
    });

    test('Test H: Successful sync does NOT delete local referral data from SQLite', () async {
      final ref = await referralProvider.createReferral(
        patientName: 'Persistent Record Patient',
        patientAge: 38,
        patientGender: 'Female',
        sourceFacility: 'PHC South',
        destinationFacility: 'DH South',
        reason: 'Acute appendicitis',
        autoSync: false,
      );

      await syncService.syncPendingReferrals();
      expect(fakeApi.createdReferrals.length, equals(1));

      // Verify referral still exists in SQLite
      final localRef = await referralRepository.getReferralById(ref!.id);
      expect(localRef, isNotNull);
      expect(localRef!.patient?.fullName, equals('Persistent Record Patient'));
      expect(localRef.syncState, equals(SyncState.synced));

      // Verify patient still exists in SQLite
      final localPatient = await patientRepository.getPatientById(ref.patientId);
      expect(localPatient, isNotNull);
      expect(localPatient!.fullName, equals('Persistent Record Patient'));

      // Verify referral list returns the synced referral
      await referralProvider.loadReferrals();
      expect(referralProvider.referrals.length, equals(1));
      expect(referralProvider.referrals.first.id, equals(ref.id));
    });

    test('Test I: Empty queue -> no API calls and no errors', () async {
      final pending = await localStorage.getPendingSyncItems();
      expect(pending.isEmpty, isTrue);

      final syncedCount = await syncService.syncPendingReferrals();
      expect(syncedCount, equals(0));
      expect(fakeApi.createdReferrals.isEmpty, isTrue);
    });
  });
}
