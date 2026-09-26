import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:relycare/app/app.dart';
import 'package:relycare/app/app_dependencies.dart';
import 'package:relycare/models/identity_match.dart';
import 'package:relycare/models/patient.dart';
import 'package:relycare/models/referral.dart';
import 'package:relycare/models/user_model.dart';
import 'package:relycare/providers/auth_provider.dart';
import 'package:relycare/providers/connectivity_provider.dart';
import 'package:relycare/services/security/auth_storage_service.dart';
import 'package:relycare/providers/identity_matching_provider.dart';
import 'package:relycare/providers/referral_provider.dart';
import 'package:relycare/providers/sync_provider.dart';
import 'package:relycare/repositories/patient_repository.dart';
import 'package:relycare/repositories/referral_repository.dart';
import 'package:relycare/repositories/sync_repository.dart';
import 'package:relycare/services/api/api_service.dart';
import 'package:relycare/services/connectivity/connectivity_service.dart';
import 'package:relycare/services/local_storage/app_database.dart';
import 'package:relycare/services/local_storage/local_storage_service.dart';
import 'package:relycare/services/matching/matching_service.dart';
import 'package:relycare/services/sms/sms_service.dart';
import 'package:relycare/services/sync/sync_service.dart';

class MockApiService implements ApiService {
  UserModel? mockUser;

  MockApiService({this.mockUser});

  @override
  void setAuthToken(String? token) {}

  @override
  Future<Map<String, dynamic>> login(String username, String password) async {
    return {
      'access_token': 'mock_token',
      'token_type': 'bearer',
      'user': {
        'id': 1,
        'username': username,
        'role': 'PHC_STAFF',
        'facility_id': mockUser?.facilityId ?? 'PHC-TEST',
        'is_active': true,
      },
    };
  }

  @override
  Future<UserModel> getMe() async => mockUser ?? const UserModel(
        id: 1,
        username: 'test_user',
        role: 'PHC_STAFF',
        facilityId: 'PHC-TEST',
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
  Future<List<Referral>> syncBatch(List<Referral> queuedReferrals) async => queuedReferrals;

  @override
  Future<List<IdentityMatch>> requestIdentityMatches(Patient incomingPatient) async => [];
}

class MockConnectivityService implements ConnectivityService {
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
  late AppDatabase db;
  late LocalStorageService storage;
  late MockConnectivityService connectivity;
  late MockSmsService sms;
  late MatchingService matching;
  late PatientRepository patientRepo;
  late ReferralRepository referralRepo;
  late SyncRepository syncRepo;
  late ReferralProvider referralProvider;
  late ConnectivityProvider connectivityProvider;
  late SyncProvider syncProvider;
  late IdentityMatchingProvider matchingProvider;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    storage = LocalStorageServiceImpl(db);
    connectivity = MockConnectivityService();
    sms = MockSmsService();
    matching = MatchingService();

    patientRepo = PatientRepository(
      localStorage: storage,
      apiService: MockApiService(),
      connectivityService: connectivity,
    );

    referralRepo = ReferralRepository(
      localStorage: storage,
      apiService: MockApiService(),
      connectivityService: connectivity,
      smsService: sms,
    );

    syncRepo = SyncRepository(
      localStorage: storage,
      syncService: SyncService(
        localStorage: storage,
        apiService: MockApiService(),
        connectivityService: connectivity,
      ),
    );

    referralProvider = ReferralProvider(referralRepository: referralRepo);
    connectivityProvider = ConnectivityProvider(connectivityService: connectivity);
    syncProvider = SyncProvider(syncRepository: syncRepo, connectivityProvider: connectivityProvider);
    matchingProvider = IdentityMatchingProvider(matchingService: matching);
    await syncProvider.refreshCounts();
  });

  tearDown(() async {
    referralProvider.dispose();
    connectivityProvider.dispose();
    syncProvider.dispose();
    matchingProvider.dispose();
    await db.close();
  });

  testWidgets('Newly created referral uses authenticated user facilityId (PHC-ALPHA-999) and NOT PHC-001 or default fallback', (WidgetTester tester) async {
    final apiService = MockApiService(
      mockUser: const UserModel(
        id: 1,
        username: 'phc_user',
        role: 'PHC_STAFF',
        facilityId: 'PHC-ALPHA-999',
        isActive: true,
      ),
    );

    final authStorage = AuthStorageServiceImpl();
    await authStorage.clearSession();
    final authProvider = AuthProvider(apiService: apiService, authStorage: authStorage);

    final dependencies = AppDependencies(
      localStorage: storage,
      apiService: apiService,
      connectivityService: connectivity,
      smsService: sms,
      matchingService: matching,
      authStorageService: authStorage,
      authProvider: authProvider,
      patientRepository: patientRepo,
      referralRepository: referralRepo,
      syncRepository: syncRepo,
      referralProvider: referralProvider,
      connectivityProvider: connectivityProvider,
      syncProvider: syncProvider,
      identityMatchingProvider: matchingProvider,
    );

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      dependencies.authProvider.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(RelyCareApp(dependencies: dependencies));
    await tester.pumpAndSettle();

    // Login as PHC Staff
    await tester.enterText(find.byType(TextFormField).first, 'phc_user');
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pumpAndSettle();

    // Navigate to Create Referral
    await tester.tap(find.text('Create Referral'));
    await tester.pumpAndSettle();

    // Fill Step 1
    final formFields = find.byType(TextFormField);
    await tester.enterText(formFields.at(0), 'Rajesh Kumar');
    await tester.enterText(formFields.at(1), '45');
    await tester.enterText(formFields.at(2), '9876543210');
    await tester.enterText(formFields.at(3), 'Village Anandpur');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Select Gender'), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Male').last, warnIfMissed: false);
    await tester.pumpAndSettle();

    // Go to Step 2
    await tester.tap(find.text('Next: Referral Details'));
    await tester.pumpAndSettle();

    // Fill Step 2
    await tester.enterText(find.byType(TextFormField).first, 'Chest pain evaluation');
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Select Hospital'));
    await tester.tap(find.text('Select Hospital'), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('District Hospital').last, warnIfMissed: false);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Select Urgency'));
    await tester.tap(find.text('Select Urgency'), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Emergency').last, warnIfMissed: false);
    await tester.pumpAndSettle();

    // Submit referral
    await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Next'));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Next'), warnIfMissed: false);
    await tester.pumpAndSettle();

    // Verify stored referral uses PHC-ALPHA-999 and NOT PHC-001 or default PHC-TEST
    final localReferrals = await storage.getAllReferrals();
    expect(localReferrals.length, equals(1));
    expect(localReferrals.first.sourceFacility, equals('PHC-ALPHA-999'));
    expect(localReferrals.first.sourceFacility, isNot(equals('PHC-001')));
    expect(localReferrals.first.sourceFacility, isNot(equals('PHC-TEST')));
  });
}
