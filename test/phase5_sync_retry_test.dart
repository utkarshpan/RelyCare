import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relycare/core/constants/app_constants.dart';
import 'package:relycare/core/errors/app_exceptions.dart';
import 'package:relycare/models/identity_match.dart';
import 'package:relycare/models/patient.dart';
import 'package:relycare/models/referral.dart';
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

/// Fake API service for deterministic testing of failure and retry workflows.
class FakeRetryApiService implements ApiService {
  int callCount = 0;
  final List<String> submittedTokens = [];
  bool shouldFail = false;
  final Set<String> failingTokens = {};
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

    callCount++;
    if (simulatedDelay > Duration.zero) {
      await Future<void>.delayed(simulatedDelay);
    }
    if (shouldFail || failingTokens.contains(referral.referralToken)) {
      throw Exception('503 Service Unavailable: Gateway timeout');
    }
    submittedTokens.add(referral.referralToken);
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
class FakeRetryConnectivityService implements ConnectivityService {
  ConnectivityStatus _status;
  final _controller = StreamController<ConnectivityStatus>.broadcast();

  FakeRetryConnectivityService({ConnectivityStatus initialStatus = ConnectivityStatus.online})
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

  group('Phase 5: Sync Failure and Retry Mechanism Tests', () {
    late AppDatabase db;
    late LocalStorageService localStorage;
    late FakeRetryApiService fakeApi;
    late FakeRetryConnectivityService fakeConnectivity;
    late SyncService syncService;
    late SyncRepository syncRepository;
    late ReferralRepository referralRepository;
    late PatientRepository patientRepository;
    late ReferralProvider referralProvider;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      localStorage = LocalStorageServiceImpl(db);
      fakeApi = FakeRetryApiService();
      fakeConnectivity = FakeRetryConnectivityService(initialStatus: ConnectivityStatus.online);
      syncService = SyncService(
        localStorage: localStorage,
        apiService: fakeApi,
        connectivityService: fakeConnectivity,
        maxRetries: AppConstants.maxSyncRetries, // 3
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

    test('TEST A: First synchronization attempt fails -> FAILED, retryCount=1, lastAttempt updated, referral remains PENDING, data preserved', () async {
      fakeApi.shouldFail = true;

      final created = await referralProvider.createReferral(
        patientName: 'Anjali Verma',
        patientAge: 27,
        patientGender: 'Female',
        sourceFacility: 'PHC Kalyanpur',
        destinationFacility: 'DH Gorakhpur',
        reason: 'Eclampsia',
        autoSync: false,
      );
      expect(created, isNotNull);

      final syncedCount = await syncService.syncPendingReferrals();
      expect(syncedCount, equals(0));
      expect(fakeApi.callCount, equals(1));

      // Verify SQLite queue item
      final queueItems = await db.select(db.syncQueue).get();
      expect(queueItems.length, equals(1));
      expect(queueItems.first.status, equals('FAILED'));
      expect(queueItems.first.retryCount, equals(1));
      expect(queueItems.first.lastAttempt, isNotNull);

      // Verify referral remains unsynced in SQLite
      final ref = await referralRepository.getReferralById(created!.id);
      expect(ref!.syncState, equals(SyncState.pendingSync));

      // Verify patient record remains intact in SQLite
      final patient = await patientRepository.getPatientById(created.patientId);
      expect(patient, isNotNull);
      expect(patient!.fullName, equals('Anjali Verma'));
    });

    test('TEST B: Failed item is retried and succeeds -> FAILED -> SYNCING -> SUCCESS, referral PENDING -> SYNCED, no data deleted', () async {
      fakeApi.shouldFail = true;

      final created = await referralProvider.createReferral(
        patientName: 'Rohan Sharma',
        patientAge: 32,
        patientGender: 'Male',
        sourceFacility: 'PHC North',
        destinationFacility: 'DH Central',
        reason: 'Multiple trauma',
        autoSync: false,
      );

      // 1st attempt fails
      await syncService.syncPendingReferrals();
      var queue = await db.select(db.syncQueue).get();
      expect(queue.first.status, equals('FAILED'));
      expect(queue.first.retryCount, equals(1));

      // Network / backend recovered
      fakeApi.shouldFail = false;

      // 2nd attempt (retry) succeeds
      final syncedCount = await syncService.retryFailedItems();
      expect(syncedCount, equals(1));

      queue = await db.select(db.syncQueue).get();
      expect(queue.first.status, equals('SUCCESS'));
      expect(queue.first.retryCount, equals(1)); // Preserves attempt count

      // Verify referral updated to SYNCED
      final ref = await referralRepository.getReferralById(created!.id);
      expect(ref!.syncState, equals(SyncState.synced));

      // Verify local referral and patient data still exist in SQLite
      expect(ref.patient?.fullName, equals('Rohan Sharma'));
    });

    test('TEST C: Retry count increments correctly across multiple failures (0 -> 1 -> 2 -> 3)', () async {
      fakeApi.shouldFail = true;

      await referralProvider.createReferral(
        patientName: 'Kishore Kumar',
        patientAge: 55,
        patientGender: 'Male',
        sourceFacility: 'PHC East',
        destinationFacility: 'DH East',
        reason: 'Cardiac emergency',
        autoSync: false,
      );

      // Attempt 1
      await syncService.syncPendingReferrals();
      var queue = await db.select(db.syncQueue).get();
      expect(queue.first.retryCount, equals(1));

      // Attempt 2
      await syncService.retryFailedItems();
      queue = await db.select(db.syncQueue).get();
      expect(queue.first.retryCount, equals(2));

      // Attempt 3
      await syncService.retryFailedItems();
      queue = await db.select(db.syncQueue).get();
      expect(queue.first.retryCount, equals(3));
      expect(queue.first.status, equals('FAILED'));
      expect(fakeApi.callCount, equals(3));
    });

    test('TEST D: MAX_SYNC_RETRIES prevents automatic infinite retry after reaching limit', () async {
      fakeApi.shouldFail = true;

      final created = await referralProvider.createReferral(
        patientName: 'Meena Kumari',
        patientAge: 48,
        patientGender: 'Female',
        sourceFacility: 'PHC West',
        destinationFacility: 'DH West',
        reason: 'Diabetic ketoacidosis',
        autoSync: false,
      );

      // Exhaust 3 retries
      await syncService.syncPendingReferrals(); // Retry count -> 1
      await syncService.syncPendingReferrals(); // Retry count -> 2
      await syncService.syncPendingReferrals(); // Retry count -> 3
      expect(fakeApi.callCount, equals(3));

      // 4th attempt should NOT call API because retryCount (3) >= maxRetries (3)
      final syncedCount = await syncService.syncPendingReferrals();
      expect(syncedCount, equals(0));
      expect(fakeApi.callCount, equals(3), reason: 'API call count must not increase beyond max retries');

      // Verify item remains locally available in SQLite with status FAILED
      final queue = await db.select(db.syncQueue).get();
      expect(queue.first.status, equals('FAILED'));
      expect(queue.first.retryCount, equals(3));

      // Referral remains unsynced
      final ref = await referralRepository.getReferralById(created!.id);
      expect(ref!.syncState, equals(SyncState.pendingSync));
    });

    test('TEST E: OFFLINE failed item -> API not called, retryCount does not increase, item remains FAILED', () async {
      fakeApi.shouldFail = true;

      await referralProvider.createReferral(
        patientName: 'Sunil Das',
        patientAge: 41,
        patientGender: 'Male',
        sourceFacility: 'PHC Remote',
        destinationFacility: 'DH Main',
        reason: 'Severe infection',
        autoSync: false,
      );

      // First failed attempt while online
      await syncService.syncPendingReferrals();
      var queue = await db.select(db.syncQueue).get();
      expect(queue.first.retryCount, equals(1));
      expect(fakeApi.callCount, equals(1));

      // Device goes OFFLINE
      fakeConnectivity.setStatus(ConnectivityStatus.offline);

      // Attempt retry while OFFLINE
      final syncedCount = await syncService.retryFailedItems();
      expect(syncedCount, equals(0));
      expect(fakeApi.callCount, equals(1), reason: 'No API calls while offline');

      // Retry count must NOT increase while offline
      queue = await db.select(db.syncQueue).get();
      expect(queue.first.retryCount, equals(1));
      expect(queue.first.status, equals('FAILED'));
    });

    test('TEST F: Connectivity OFFLINE -> ONLINE retries eligible failed items and skips retry-limited items', () async {
      fakeConnectivity.setStatus(ConnectivityStatus.offline);
      final connectivityProvider = ConnectivityProvider(connectivityService: fakeConnectivity);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final syncProvider = SyncProvider(
        syncRepository: syncRepository,
        connectivityProvider: connectivityProvider,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // 1. Insert an eligible failed item (retryCount = 1)
      await localStorage.queueForSync(
        entityType: 'referral',
        entityId: 'RC-ELIGIBLE-1',
        operation: 'CREATE',
        payload: '{}',
      );
      final eligibleQueueItem = (await localStorage.getPendingSyncItems()).first;
      await localStorage.markSyncFailed(eligibleQueueItem.id, resetToPending: false); // retryCount=1, status=FAILED

      // Also create local referral for RC-ELIGIBLE-1
      await localStorage.createReferralTransaction(
        patientName: 'Eligible Patient',
        patientAge: 30,
        patientGender: 'Female',
        sourceFacility: 'PHC A',
        destinationFacility: 'DH A',
        reason: 'Fever',
        customReferralId: 'RC-ELIGIBLE-1',
      );

      // 2. Insert a retry-limited item (retryCount = 3)
      await localStorage.queueForSync(
        entityType: 'referral',
        entityId: 'RC-LIMITED-1',
        operation: 'CREATE',
        payload: '{}',
      );
      final allPending = await localStorage.getPendingSyncItems();
      final limitedQueueItem = allPending.firstWhere((i) => i.entityId == 'RC-LIMITED-1');
      await localStorage.markSyncFailed(limitedQueueItem.id, resetToPending: false); // 1
      await localStorage.markSyncFailed(limitedQueueItem.id, resetToPending: false); // 2
      await localStorage.markSyncFailed(limitedQueueItem.id, resetToPending: false); // 3

      expect(fakeApi.callCount, equals(0));

      // Transition OFFLINE -> ONLINE
      fakeConnectivity.setStatus(ConnectivityStatus.online);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Only RC-ELIGIBLE-1 should be retried and submitted
      expect(fakeApi.submittedTokens, contains('RC-ELIGIBLE-1'));
      expect(fakeApi.submittedTokens, isNot(contains('RC-LIMITED-1')));

      connectivityProvider.dispose();
      syncProvider.dispose();
    });

    test('TEST G: Concurrent retry/sync calls execute only once with no duplicate submissions', () async {
      fakeApi.simulatedDelay = const Duration(milliseconds: 50);

      await referralProvider.createReferral(
        patientName: 'Concurrent Retry Patient',
        patientAge: 36,
        patientGender: 'Male',
        sourceFacility: 'PHC Central',
        destinationFacility: 'DH East',
        reason: 'Head injury',
        autoSync: false,
      );

      // Fire sync and retry concurrently
      final f1 = syncService.syncPendingReferrals();
      final f2 = syncService.retryFailedItems();

      final results = await Future.wait([f1, f2]);
      expect(results, contains(1));
      expect(results, contains(0));
      expect(fakeApi.callCount, equals(1));
    });

    test('TEST H: Retry succeeds after previous failures and preserves retry history', () async {
      fakeApi.shouldFail = true;

      final created = await referralProvider.createReferral(
        patientName: 'Geeta Devi',
        patientAge: 50,
        patientGender: 'Female',
        sourceFacility: 'PHC 1',
        destinationFacility: 'DH 1',
        reason: 'Hypertensive crisis',
        autoSync: false,
      );

      // Fail twice
      await syncService.syncPendingReferrals(); // retryCount = 1
      await syncService.syncPendingReferrals(); // retryCount = 2
      expect(fakeApi.callCount, equals(2));

      // API back online
      fakeApi.shouldFail = false;
      final syncedCount = await syncService.retryFailedItems();
      expect(syncedCount, equals(1));

      final queue = await db.select(db.syncQueue).get();
      expect(queue.first.status, equals('SUCCESS'));
      expect(queue.first.retryCount, equals(2)); // Reflects previous failed attempts

      final ref = await referralRepository.getReferralById(created!.id);
      expect(ref!.syncState, equals(SyncState.synced));
    });

    test('TEST I: Retry failure preserves local patient and referral data in SQLite', () async {
      fakeApi.shouldFail = true;

      final created = await referralProvider.createReferral(
        patientName: 'Preserved Patient',
        patientAge: 62,
        patientGender: 'Male',
        sourceFacility: 'PHC South',
        destinationFacility: 'DH South',
        reason: 'Severe dehydration',
        clinicalNotes: 'IV fluids initiated',
        autoSync: false,
      );

      await syncService.syncPendingReferrals(); // 1st failure
      await syncService.retryFailedItems(); // 2nd failure

      // Check SQLite records
      final localRef = await referralRepository.getReferralById(created!.id);
      expect(localRef, isNotNull);
      expect(localRef!.patient?.fullName, equals('Preserved Patient'));
      expect(localRef.clinicalNotesSummary, equals('IV fluids initiated'));
      expect(localRef.syncState, equals(SyncState.pendingSync));

      final localPatient = await patientRepository.getPatientById(created.patientId);
      expect(localPatient, isNotNull);
      expect(localPatient!.fullName, equals('Preserved Patient'));
    });

    test('TEST J: Startup while ONLINE processes retryable failed items and skips retry-limited items', () async {
      // 1. Seed eligible failed item
      await localStorage.queueForSync(
        entityType: 'referral',
        entityId: 'RC-STARTUP-RETRY',
        operation: 'CREATE',
        payload: '{}',
      );
      final q1 = (await localStorage.getPendingSyncItems()).first;
      await localStorage.markSyncFailed(q1.id, resetToPending: false); // retryCount = 1

      await localStorage.createReferralTransaction(
        patientName: 'Startup Retry Patient',
        patientAge: 39,
        patientGender: 'Female',
        sourceFacility: 'PHC A',
        destinationFacility: 'DH A',
        reason: 'Appendicitis',
        customReferralId: 'RC-STARTUP-RETRY',
      );

      // 2. Seed retry-limited item
      await localStorage.queueForSync(
        entityType: 'referral',
        entityId: 'RC-STARTUP-LIMITED',
        operation: 'CREATE',
        payload: '{}',
      );
      final allPending = await localStorage.getPendingSyncItems();
      final q2 = allPending.firstWhere((i) => i.entityId == 'RC-STARTUP-LIMITED');
      await localStorage.markSyncFailed(q2.id, resetToPending: false);
      await localStorage.markSyncFailed(q2.id, resetToPending: false);
      await localStorage.markSyncFailed(q2.id, resetToPending: false); // retryCount = 3

      // Startup
      final connectivityProvider = ConnectivityProvider(connectivityService: fakeConnectivity);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final syncProvider = SyncProvider(
        syncRepository: syncRepository,
        connectivityProvider: connectivityProvider,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(fakeApi.submittedTokens, contains('RC-STARTUP-RETRY'));
      expect(fakeApi.submittedTokens, isNot(contains('RC-STARTUP-LIMITED')));

      connectivityProvider.dispose();
      syncProvider.dispose();
    });

    test('TEST K: Multiple failed items maintain individual retry counts without cross-item contamination', () async {
      final refA = await referralProvider.createReferral(
        patientName: 'Patient A',
        patientAge: 20,
        patientGender: 'Male',
        sourceFacility: 'PHC A',
        destinationFacility: 'DH A',
        reason: 'Reason A',
        autoSync: false,
      );

      final refB = await referralProvider.createReferral(
        patientName: 'Patient B',
        patientAge: 30,
        patientGender: 'Female',
        sourceFacility: 'PHC B',
        destinationFacility: 'DH B',
        reason: 'Reason B',
        autoSync: false,
      );

      // Fail ONLY referral A, allow referral B to succeed
      fakeApi.failingTokens.add(refA!.referralToken);

      final syncedCount = await syncService.syncPendingReferrals();
      expect(syncedCount, equals(1)); // B succeeded, A failed

      final allQueue = await db.select(db.syncQueue).get();
      final queueA = allQueue.firstWhere((q) => q.entityId == refA.referralToken);
      final queueB = allQueue.firstWhere((q) => q.entityId == refB!.referralToken);

      expect(queueA.status, equals('FAILED'));
      expect(queueA.retryCount, equals(1));

      expect(queueB.status, equals('SUCCESS'));
      expect(queueB.retryCount, equals(0));

      // Second attempt on A
      await syncService.retryFailedItems();
      final queueAUpdated = (await db.select(db.syncQueue).get()).firstWhere((q) => q.entityId == refA.referralToken);
      expect(queueAUpdated.retryCount, equals(2));
    });

    test('TEST L: Existing Phase 1-4 behavior still works seamlessly', () async {
      // 1. Offline creation
      final ref = await referralProvider.createReferral(
        patientName: 'Phase 4 Compatibility',
        patientAge: 33,
        patientGender: 'Female',
        sourceFacility: 'PHC Test',
        destinationFacility: 'DH Test',
        reason: 'Test Reason',
        autoSync: false,
      );
      expect(ref!.syncState, equals(SyncState.pendingSync));

      // 2. Online sync
      final synced = await syncService.syncPendingReferrals();
      expect(synced, equals(1));

      final updated = await referralRepository.getReferralById(ref.id);
      expect(updated!.syncState, equals(SyncState.synced));
    });

    test('TEST M: UnauthenticatedException resets item to PENDING without incrementing retryCount', () async {
      await referralProvider.createReferral(
        patientName: 'Token Expired Patient',
        patientAge: 29,
        patientGender: 'Male',
        sourceFacility: 'PHC North',
        destinationFacility: 'DH Central',
        reason: 'Emergency',
        autoSync: false,
      );

      // Make API throw UnauthenticatedException
      fakeApi.shouldFail = true;

      // Class to throw UnauthenticatedException
      final unauthService = _UnauthFakeApiService();
      final unauthSyncService = SyncService(
        localStorage: localStorage,
        apiService: unauthService,
        connectivityService: fakeConnectivity,
        maxRetries: 3,
      );

      // Run multiple sync passes with expired token
      await unauthSyncService.syncPendingReferrals();
      await unauthSyncService.syncPendingReferrals();
      await unauthSyncService.syncPendingReferrals();

      final queue = await db.select(db.syncQueue).get();
      expect(queue.first.status, equals('PENDING'));
      expect(queue.first.retryCount, equals(0), reason: 'retryCount must remain 0 on 401 UnauthenticatedException');
    });
  });
}

class _UnauthFakeApiService extends FakeRetryApiService {
  _UnauthFakeApiService();

  @override
  Future<Referral> createReferral(Referral referral) async {
    throw const UnauthenticatedException('JWT token expired');
  }
}

