import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:relycare/core/errors/app_exceptions.dart';
import 'package:relycare/models/identity_match.dart';
import 'package:relycare/models/patient.dart';
import 'package:relycare/models/referral.dart';
import 'package:relycare/models/user_model.dart';
import 'package:relycare/providers/referral_provider.dart';
import 'package:relycare/providers/sync_provider.dart';
import 'package:relycare/repositories/referral_repository.dart';
import 'package:relycare/repositories/sync_repository.dart';
import 'package:relycare/screens/referral_details/referral_details_screen.dart';
import 'package:relycare/services/api/api_service.dart';
import 'package:relycare/services/connectivity/connectivity_service.dart';
import 'package:relycare/services/local_storage/app_database.dart';
import 'package:relycare/services/local_storage/local_storage_service.dart';
import 'package:relycare/services/sms/sms_service.dart';

class _FakeApiStub implements ApiService {
  final List<Referral> syncedReferrals = [];
  bool shouldFail = false;

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
    if (shouldFail) {
      throw const NetworkException('Server temporarily unavailable (500)', statusCode: 500);
    }
    syncedReferrals.add(referral);
    return referral;
  }

  @override
  Future<Referral> getReferral(String referralId) async => throw UnimplementedError();

  @override
  Future<List<Referral>> fetchReferrals({int skip = 0, int limit = 100, String? status}) async => [];

  @override
  Future<void> updateReferralStatus(String referralId, String status) async {}

  @override
  Future<List<Referral>> syncBatch(List<Referral> queuedReferrals) async => queuedReferrals;

  @override
  Future<List<IdentityMatch>> requestIdentityMatches(Patient incomingPatient) async => [];
}

class _FakeTestConnectivityService implements ConnectivityService {
  bool _isOnline;
  final StreamController<ConnectivityStatus> _statusController =
      StreamController<ConnectivityStatus>.broadcast();

  _FakeTestConnectivityService({bool initialOnline = false}) : _isOnline = initialOnline;

  bool get isOnline => _isOnline;

  @override
  ConnectivityStatus get currentStatus =>
      _isOnline ? ConnectivityStatus.online : ConnectivityStatus.offline;

  @override
  Future<bool> checkConnectivity() async => _isOnline;

  @override
  Future<ConnectivityStatus> checkConnectivityStatus() async => currentStatus;

  @override
  Stream<bool> get onConnectivityChanged =>
      _statusController.stream.map((s) => s == ConnectivityStatus.online);

  @override
  Stream<ConnectivityStatus> get onStatusChanged => _statusController.stream;

  void toggleSimulation() {
    _isOnline = !_isOnline;
    _statusController.add(currentStatus);
  }

  void setOnline(bool online) {
    _isOnline = online;
    _statusController.add(currentStatus);
  }

  @override
  void dispose() {
    _statusController.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late LocalStorageService localStorage;
  late MockSmsService mockSmsService;
  late _FakeApiStub fakeApi;
  late _FakeTestConnectivityService connectivityService;
  late ReferralRepository referralRepository;
  late ReferralProvider referralProvider;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    localStorage = LocalStorageServiceImpl(db);
    mockSmsService = MockSmsService();
    fakeApi = _FakeApiStub();
    connectivityService = _FakeTestConnectivityService(initialOnline: false);
    referralRepository = ReferralRepository(
      localStorage: localStorage,
      apiService: fakeApi,
      connectivityService: connectivityService,
      smsService: mockSmsService,
    );
    referralProvider = ReferralProvider(
      referralRepository: referralRepository,
    );
  });

  tearDown(() async {
    referralProvider.dispose();
    connectivityService.dispose();
    await localStorage.close();
  });

  Widget createWidgetUnderTest(Referral referral) {
    return ChangeNotifierProvider<ReferralProvider>.value(
      value: referralProvider,
      child: MaterialApp(
        home: ReferralDetailsScreen(referral: referral),
      ),
    );
  }

  testWidgets('1. Online referral -> API sync path -> no SMS_SENT event, timeline shows "Synced to Server"', (tester) async {
    // Set network to ONLINE
    connectivityService.setOnline(true);

    final created = await referralProvider.createReferral(
      patientName: 'Gaurav Sharma',
      patientAge: 34,
      patientGender: 'Male',
      patientPhone: '+91 9876543210',
      sourceFacility: 'PHC Palghar',
      destinationFacility: 'District Hospital',
      reason: 'Chest Pain',
    );
    expect(created, isNotNull);

    // Verify referral was synced via HTTP
    expect(created!.syncState, equals(SyncState.synced));
    expect(fakeApi.syncedReferrals.length, equals(1));
    expect(fakeApi.syncedReferrals.first.referralToken, equals(created.referralToken));

    // Verify NO SMS was dispatched
    expect(mockSmsService.sentPayloads.isEmpty, isTrue);
    final events = await referralProvider.getReferralEvents(created.id);
    expect(events.any((e) => e.eventType == 'SMS_SENT'), isFalse);
    expect(await referralProvider.getSmsDeliveryStatus(created.referralToken), equals(SmsDeliveryStatus.notSent));

    // Render Referral Details Screen
    await tester.pumpWidget(createWidgetUnderTest(created));
    await tester.pumpAndSettle();

    // Verify Timeline Node 3 displays "Synced to Server" and completed
    expect(find.text('Synced to Server'), findsOneWidget);
    expect(find.text('Payload uploaded to central registry'), findsOneWidget);
    expect(find.text('SMS Fallback Sent'), findsNothing);
  });

  testWidgets('2. Offline referral -> SMS fallback path -> SMS_SENT event exists, timeline shows "SMS Fallback Sent"', (tester) async {
    // Set network to OFFLINE
    connectivityService.setOnline(false);

    final created = await referralProvider.createReferral(
      patientName: 'Karan Choudhary',
      patientAge: 28,
      patientGender: 'Male',
      patientPhone: '+91 9876543211',
      sourceFacility: 'PHC Palghar',
      destinationFacility: 'District Hospital',
      reason: 'Fracture',
    );
    expect(created, isNotNull);

    // Verify referral is stored locally with PENDING syncState
    expect(created!.syncState, equals(SyncState.pendingSync));
    expect(fakeApi.syncedReferrals.isEmpty, isTrue);

    // Verify SMS fallback was automatically dispatched and recorded
    expect(mockSmsService.sentPayloads.length, equals(1));
    final smsStatus = await referralProvider.getSmsDeliveryStatus(created.referralToken);
    expect(smsStatus, equals(SmsDeliveryStatus.sent));

    final events = await referralProvider.getReferralEvents(created.id);
    expect(events.any((e) => e.eventType == 'SMS_SENT'), isTrue);

    // Render Referral Details Screen
    await tester.pumpWidget(createWidgetUnderTest(created));
    await tester.pumpAndSettle();

    // Verify Timeline Node 3 displays "SMS Fallback Sent" and completed
    expect(find.text('SMS Fallback Sent'), findsOneWidget);
    expect(find.text('Encrypted data packet dispatched via GSM'), findsOneWidget);
  });

  testWidgets('3. Offline referral later synced online -> no duplicate SMS_SENT event or duplicate referral', (tester) async {
    // Start OFFLINE
    connectivityService.setOnline(false);

    final created = await referralProvider.createReferral(
      patientName: 'Asha Patel',
      patientAge: 45,
      patientGender: 'Female',
      patientPhone: '+91 9876543212',
      sourceFacility: 'PHC Palghar',
      destinationFacility: 'District Hospital',
      reason: 'Fever',
    );
    expect(created, isNotNull);
    expect(mockSmsService.sentPayloads.length, equals(1));

    // Later: Internet comes back ONLINE
    connectivityService.setOnline(true);

    // Process sync queue
    final syncedCount = await referralRepository.syncService.syncPendingReferrals();
    expect(syncedCount, equals(1));
    expect(fakeApi.syncedReferrals.length, equals(1));
    expect(fakeApi.syncedReferrals.first.referralToken, equals(created!.referralToken));

    // Verify SMS payloads count remains 1 (no duplicate SMS dispatch)
    expect(mockSmsService.sentPayloads.length, equals(1));

    final events = await referralProvider.getReferralEvents(created.id);
    final smsEvents = events.where((e) => e.eventType == 'SMS_SENT').toList();
    expect(smsEvents.length, equals(1), reason: 'Must not duplicate SMS_SENT event on online sync');

    // Retrieve updated referral
    final updated = await localStorage.getDomainReferralById(created.referralToken);
    expect(updated, isNotNull);
    expect(updated!.syncState, equals(SyncState.synced));

    // Render Referral Details Screen
    await tester.pumpWidget(createWidgetUnderTest(updated));
    await tester.pumpAndSettle();

    // Timeline Node 3 shows "SMS Fallback Sent" because SMS fallback was actually used
    expect(find.text('SMS Fallback Sent'), findsOneWidget);
  });

  testWidgets('4. Offline referral with SMS failure records SMS_FAILED and shows pending Synced to Server', (tester) async {
    connectivityService.setOnline(false);
    mockSmsService.shouldFail = true;

    final created = await referralProvider.createReferral(
      patientName: 'Devendra Patel',
      patientAge: 52,
      patientGender: 'Male',
      sourceFacility: 'PHC Palghar',
      destinationFacility: 'District Hospital',
      reason: 'Severe fever',
    );
    expect(created, isNotNull);

    // Verify SMS status is failed
    final smsStatus = await referralProvider.getSmsDeliveryStatus(created!.referralToken);
    expect(smsStatus, equals(SmsDeliveryStatus.failed));

    final events = await referralProvider.getReferralEvents(created.id);
    expect(events.any((e) => e.eventType == 'SMS_FAILED'), isTrue);
    expect(events.any((e) => e.eventType == 'SMS_SENT'), isFalse);

    // Render Referral Details Screen
    await tester.pumpWidget(createWidgetUnderTest(created));
    await tester.pumpAndSettle();

    // Timeline shows pending 'Synced to Server'
    expect(find.text('Synced to Server'), findsOneWidget);
    expect(find.text('Waiting for network connection to sync'), findsOneWidget);
    expect(find.text('(Pending)'), findsWidgets);
    expect(find.text('SMS Fallback Sent'), findsNothing);
  });

  testWidgets('5. Failed sync remains retryable and successfully syncs upon manual retry when network is restored', (tester) async {
    // Start ONLINE but server fails
    connectivityService.setOnline(true);
    fakeApi.shouldFail = true;

    final created = await referralProvider.createReferral(
      patientName: 'Yogesh Kumar',
      patientAge: 38,
      patientGender: 'Male',
      sourceFacility: 'PHC-TEST',
      destinationFacility: 'DH-TEST',
      reason: 'Chest discomfort',
    );
    expect(created, isNotNull);

    // Initial state: sync failed on server -> referral remains pendingSync
    final initialLocal = await localStorage.getDomainReferralById(created!.referralToken);
    expect(initialLocal!.syncState, equals(SyncState.pendingSync));

    // Verify queue item is marked FAILED and eligible for retry
    final failedItems = await localStorage.getFailedSyncItems();
    expect(failedItems.length, equals(1));
    expect(failedItems.first.entityId, equals(created.referralToken));

    // Server recovers
    fakeApi.shouldFail = false;

    // Trigger sync with resetFailed = true (as done by "Sync Now" button)
    final syncProvider = SyncProvider(
      syncRepository: SyncRepository(
        localStorage: localStorage,
        syncService: referralRepository.syncService,
      ),
    );
    final syncedCount = await syncProvider.syncPending(resetFailed: true);
    expect(syncedCount, equals(1));

    // Referral is now SYNCED
    final syncedLocal = await localStorage.getDomainReferralById(created.referralToken);
    expect(syncedLocal!.syncState, equals(SyncState.synced));
    expect(fakeApi.syncedReferrals.any((r) => r.referralToken == created.referralToken), isTrue);

    // No failed items remain
    final remainingFailed = await localStorage.getFailedSyncItems();
    expect(remainingFailed.isEmpty, isTrue);
  });

  testWidgets('6. Offline referral with SMS fallback then syncing online does NOT create duplicate referral or duplicate SMS_SENT event', (tester) async {
    // 1. Created offline -> SMS sent
    connectivityService.setOnline(false);

    final created = await referralProvider.createReferral(
      patientName: 'Umesh Gupta',
      patientAge: 44,
      patientGender: 'Male',
      sourceFacility: 'PHC-TEST',
      destinationFacility: 'DH-TEST',
      reason: 'Abdominal pain',
    );
    expect(created, isNotNull);
    expect(mockSmsService.sentPayloads.length, equals(1));

    // Verify SMS_SENT event exists in local timeline
    final eventsBefore = await referralProvider.getReferralEvents(created!.id);
    expect(eventsBefore.where((e) => e.eventType == 'SMS_SENT').length, equals(1));

    // 2. Internet returns -> sync to server
    connectivityService.setOnline(true);
    final syncedCount = await referralRepository.syncService.syncPendingReferrals();
    expect(syncedCount, equals(1));

    // 3. Verify server received full referral
    expect(fakeApi.syncedReferrals.where((r) => r.referralToken == created.referralToken).length, equals(1));

    // 4. Verify no second SMS or duplicate SMS_SENT event was recorded
    expect(mockSmsService.sentPayloads.length, equals(1));
    final eventsAfter = await referralProvider.getReferralEvents(created.id);
    expect(eventsAfter.where((e) => e.eventType == 'SMS_SENT').length, equals(1));
  });

  testWidgets('7. Automatic sync with resetFailed: false does not reset exhausted FAILED items, while manual sync with resetFailed: true retries them', (tester) async {
    connectivityService.setOnline(true);
    fakeApi.shouldFail = true;

    final created = await referralProvider.createReferral(
      patientName: 'Ramesh Verma',
      patientAge: 40,
      patientGender: 'Male',
      sourceFacility: 'PHC-TEST',
      destinationFacility: 'DH-TEST',
      reason: 'Hypertension',
    );
    expect(created, isNotNull);

    // Fail sync 3 times to exhaust maxSyncRetries (3)
    await referralRepository.syncService.syncPendingReferrals();
    await referralRepository.syncService.syncPendingReferrals();
    await referralRepository.syncService.syncPendingReferrals();

    final syncProvider = SyncProvider(
      syncRepository: SyncRepository(
        localStorage: localStorage,
        syncService: referralRepository.syncService,
      ),
    );

    // Automatic/background sync with default resetFailed: false
    fakeApi.shouldFail = false;
    final autoSyncedCount = await syncProvider.syncPending(resetFailed: false);
    expect(autoSyncedCount, equals(0), reason: 'Automatic sync must respect maxSyncRetries and not reset exhausted items');

    // Manual "Sync Now" action with resetFailed: true
    final manualSyncedCount = await syncProvider.syncPending(resetFailed: true);
    expect(manualSyncedCount, equals(1), reason: 'Manual Sync Now action resets failed items and successfully retries');
  });

  testWidgets('8. Online referral creation with API server failure automatically triggers SMS fallback and later server sync preserves timeline', (tester) async {
    // Device is ONLINE but backend API returns 500 error
    connectivityService.setOnline(true);
    fakeApi.shouldFail = true;

    final created = await referralProvider.createReferral(
      patientName: 'Suresh Raina',
      patientAge: 32,
      patientGender: 'Male',
      sourceFacility: 'PHC-TEST',
      destinationFacility: 'DH-TEST',
      reason: 'Severe migraine',
    );
    expect(created, isNotNull);

    // Because API sync failed, SMS fallback was automatically dispatched
    expect(mockSmsService.sentPayloads.length, equals(1));
    final smsStatus = await referralProvider.getSmsDeliveryStatus(created!.referralToken);
    expect(smsStatus, equals(SmsDeliveryStatus.sent));

    final eventsBefore = await referralProvider.getReferralEvents(created.id);
    expect(eventsBefore.any((e) => e.eventType == 'SMS_SENT'), isTrue);

    // Later: Server recovers and manual sync succeeds
    fakeApi.shouldFail = false;
    final syncProvider = SyncProvider(
      syncRepository: SyncRepository(
        localStorage: localStorage,
        syncService: referralRepository.syncService,
      ),
    );
    final syncedCount = await syncProvider.syncPending(resetFailed: true);
    expect(syncedCount, equals(1));

    // Timeline still reflects SMS was sent and server received full referral without duplicates
    final updated = await localStorage.getDomainReferralById(created.referralToken);
    expect(updated!.syncState, equals(SyncState.synced));
    expect(mockSmsService.sentPayloads.length, equals(1));
    final eventsAfter = await referralProvider.getReferralEvents(created.id);
    expect(eventsAfter.where((e) => e.eventType == 'SMS_SENT').length, equals(1));
  });
}
