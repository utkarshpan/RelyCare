import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:relycare/app/app.dart';

import 'package:relycare/app/app_dependencies.dart';
import 'package:relycare/models/identity_match.dart';
import 'package:relycare/models/patient.dart';
import 'package:relycare/models/referral.dart';
import 'package:relycare/models/user_model.dart';
import 'package:relycare/providers/auth_provider.dart';

import 'package:relycare/providers/connectivity_provider.dart';
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

/// Deterministic mock API service for offline/online test flows.
class FakeApiService implements ApiService {
  final List<Referral> createdReferrals = [];

  @override
  void setAuthToken(String? token) {}

  @override
  Future<Map<String, dynamic>> login(String username, String password) async {
    final isHospital = username.contains('hospital') || username.contains('verma') || username == 'hosp';
    final isPatient = username.contains('patient');
    final role = isPatient ? 'PATIENT' : (isHospital ? 'HOSPITAL_STAFF' : 'PHC_STAFF');
    return {
      'access_token': 'test_mock_jwt_token',
      'token_type': 'bearer',
      'user': {
        'id': 1,
        'username': username,
        'role': role,
        'facility_id': isHospital ? 'DH-TEST' : 'PHC-TEST',
        'is_active': true,
      },
    };
  }

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
  Future<List<Referral>> syncBatch(List<Referral> queuedReferrals) async => queuedReferrals;

  @override
  Future<List<IdentityMatch>> requestIdentityMatches(Patient incomingPatient) async => [];
}

/// Fake connectivity service to isolate widget tests from platform channels.
class FakeConnectivityService implements ConnectivityService {
  ConnectivityStatus _status;
  final StreamController<ConnectivityStatus> _controller =
      StreamController<ConnectivityStatus>.broadcast();

  FakeConnectivityService({ConnectivityStatus initialStatus = ConnectivityStatus.offline})
      : _status = initialStatus;

  @override
  Future<ConnectivityStatus> checkConnectivityStatus() async => _status;

  @override
  Future<bool> checkConnectivity() async => _status.isOnline;

  @override
  Stream<ConnectivityStatus> get onStatusChanged => _controller.stream;

  @override
  Stream<bool> get onConnectivityChanged =>
      _controller.stream.map((s) => s.isOnline);

  @override
  ConnectivityStatus get currentStatus => _status;

  void setStatus(ConnectivityStatus status) {
    _status = status;
    _controller.add(status);
  }

  @override
  void dispose() {
    _controller.close();
  }
}

void main() {
  late AppDatabase db;
  late LocalStorageService storage;
  late FakeApiService api;
  late FakeConnectivityService connectivity;
  late SmsService sms;
  late MatchingService matching;
  late PatientRepository patientRepo;
  late ReferralRepository referralRepo;
  late SyncRepository syncRepo;
  late ReferralProvider referralProvider;
  late ConnectivityProvider connectivityProvider;
  late SyncProvider syncProvider;
  late IdentityMatchingProvider matchingProvider;
  late AppDependencies dependencies;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    storage = LocalStorageServiceImpl(db);
    api = FakeApiService();

    connectivity = FakeConnectivityService(initialStatus: ConnectivityStatus.offline);
    sms = MockSmsService();
    matching = MatchingService();

    patientRepo = PatientRepository(
      localStorage: storage,
      apiService: api,
      connectivityService: connectivity,
    );

    referralRepo = ReferralRepository(
      localStorage: storage,
      apiService: api,
      connectivityService: connectivity,
      smsService: sms,
    );

    syncRepo = SyncRepository(
      localStorage: storage,
      syncService: SyncService(
        localStorage: storage,
        apiService: api,
        connectivityService: connectivity,
      ),
    );

    referralProvider = ReferralProvider(referralRepository: referralRepo);
    connectivityProvider = ConnectivityProvider(connectivityService: connectivity);
    syncProvider = SyncProvider(syncRepository: syncRepo, connectivityProvider: connectivityProvider);
    matchingProvider = IdentityMatchingProvider(matchingService: matching);

    dependencies = AppDependencies(
      localStorage: storage,
      apiService: api,
      connectivityService: connectivity,
      smsService: sms,
      matchingService: matching,
      patientRepository: patientRepo,
      referralRepository: referralRepo,
      syncRepository: syncRepo,
      referralProvider: referralProvider,
      connectivityProvider: connectivityProvider,
      syncProvider: syncProvider,
      identityMatchingProvider: matchingProvider,
    );
  });

  tearDown(() async {
    referralProvider.dispose();
    connectivityProvider.dispose();
    syncProvider.dispose();
    matchingProvider.dispose();
    connectivity.dispose();
    await db.close();
  });

  testWidgets('TEST 1: Provider Singleton & Tree Verification', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(RelyCareApp(dependencies: dependencies));
    await tester.pumpAndSettle();

    final BuildContext context = tester.element(find.byType(MaterialApp));

    // Verify exactly one instance of each provider is accessible via both Provider and RelyCareScope
    expect(Provider.of<ReferralProvider>(context, listen: false), equals(dependencies.referralProvider));
    expect(Provider.of<ConnectivityProvider>(context, listen: false), equals(dependencies.connectivityProvider));
    expect(Provider.of<SyncProvider>(context, listen: false), equals(dependencies.syncProvider));
    expect(Provider.of<IdentityMatchingProvider>(context, listen: false), equals(dependencies.identityMatchingProvider));
    expect(Provider.of<AuthProvider>(context, listen: false), isNotNull);

    expect(context.referralProvider, equals(dependencies.referralProvider));
    expect(context.connectivityProvider, equals(dependencies.connectivityProvider));
    expect(context.syncProvider, equals(dependencies.syncProvider));
    expect(context.identityMatchingProvider, equals(dependencies.identityMatchingProvider));
  });

  testWidgets('TEST 2: Complete PHC Staff Workflow (Login, Dash, Nav, Create Referral, SQLite Verification)', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(RelyCareApp(dependencies: dependencies));
    await tester.pumpAndSettle();

    // 1. Login as PHC Staff
    expect(find.text('Welcome Back'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'dr.sharma@phc.org');
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.pumpAndSettle();

    final loginBtn = find.widgetWithText(ElevatedButton, 'Login');
    await tester.tap(loginBtn);
    await tester.pumpAndSettle();

    // 2. PHC Dashboard renders
    expect(find.text('Good Morning, Dr. Sharma'), findsOneWidget);
    expect(find.text('Recent Referrals'), findsOneWidget);

    // 3. Test Bottom Navigation: Referrals tab
    await tester.tap(find.text('Referrals'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pumpAndSettle();
    expect(find.text('Local Referrals'), findsOneWidget);

    // Back to Dashboard
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Good Morning, Dr. Sharma'), findsOneWidget);

    // 4. Test Bottom Navigation: Sync tab
    await tester.tap(find.text('Sync'));
    await tester.pumpAndSettle();
    expect(find.text('Sync & Connectivity'), findsOneWidget);

    // Back to Dashboard
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Good Morning, Dr. Sharma'), findsOneWidget);

    // 5. Test Bottom Navigation: Profile tab
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Facility & Staff Profile'), findsOneWidget);

    // Back to Dashboard
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Good Morning, Dr. Sharma'), findsOneWidget);

    // 6. Test Create Referral Flow (Step 1 -> Next -> Step 2 -> Back -> Step 2 -> Create)
    await tester.tap(find.text('Create Referral'));
    await tester.pumpAndSettle();
    expect(find.text('Step 1 of 3: Patient Info'), findsOneWidget);

    // Fill Step 1
    final formFields = find.byType(TextFormField);
    await tester.enterText(formFields.at(0), 'Sita Devi');
    await tester.enterText(formFields.at(1), '32');
    
    // Select Gender
    await tester.tap(find.text('Select Gender'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Female').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(2), '9876543210');
    await tester.enterText(find.byType(TextFormField).at(3), 'Village Rampur');
    await tester.pumpAndSettle();

    // Step 1 -> Next
    await tester.tap(find.text('Next: Referral Details'));
    await tester.pumpAndSettle();

    // Step 2 Screen
    expect(find.text('Step 2 of 3: Referral Details'), findsOneWidget);

    // Test Step 2 Back button
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Step 1 of 3: Patient Info'), findsOneWidget);

    // Return to Step 2
    await tester.tap(find.text('Next: Referral Details'));
    await tester.pumpAndSettle();
    expect(find.text('Step 2 of 3: Referral Details'), findsOneWidget);

    // Fill Step 2 fields
    await tester.enterText(find.byType(TextFormField).first, 'Severe abdominal pain');
    await tester.pumpAndSettle();

    // Select Destination Hospital dropdown
    await tester.ensureVisible(find.text('Select Hospital'));
    await tester.tap(find.text('Select Hospital'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('District Hospital').last);
    await tester.pumpAndSettle();

    // Select Urgency dropdown
    await tester.ensureVisible(find.text('Select Urgency'));
    await tester.tap(find.text('Select Urgency'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Urgent').last);
    await tester.pumpAndSettle();

    // Tap Next / Save button
    await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Next'));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Next'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();

    // Verify redirected to dashboard with saved message
    expect(find.text('Good Morning, Dr. Sharma'), findsOneWidget);

    // Verify Referral in SQLite database
    final localReferrals = await storage.getAllReferrals();
    expect(localReferrals.length, equals(1));
    expect(localReferrals.first.reason, equals('Severe abdominal pain'));
    expect(localReferrals.first.status, equals('CREATED'));
    expect(localReferrals.first.syncStatus, equals('PENDING'));

    // Verify Sync Queue item created
    final queueItems = await syncRepo.getPendingQueueCount();
    expect(queueItems, equals(1));

    // 7. Test Local Referrals -> Referral Details for created patient
    await tester.tap(find.text('Referrals'));
    await tester.pumpAndSettle();
    expect(find.text('Local Referrals'), findsOneWidget);
    expect(find.text('Sita Devi'), findsOneWidget);

    // Tap referral card for Sita Devi
    await tester.tap(find.text('Sita Devi'));
    await tester.pumpAndSettle();

    // Verify Referral Details shows Sita Devi (NOT Rahul Sharma)
    expect(find.text('Referral Details'), findsOneWidget);
    expect(find.text('Sita Devi'), findsOneWidget);
    expect(find.text('Severe abdominal pain'), findsOneWidget);
    expect(find.text('Rahul Sharma'), findsNothing);

    // Back to Local Referrals
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Local Referrals'), findsOneWidget);

    // Back to PHC Dashboard
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Good Morning, Dr. Sharma'), findsOneWidget);
  });

  testWidgets('TEST 3: Hospital Staff Workflow (Login, Dash, Identity Matching, Details, Logout)', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(RelyCareApp(dependencies: dependencies));
    await tester.pumpAndSettle();

    // 1. Enter hospital staff credentials (role is assigned by backend database)
    expect(find.text('Welcome Back'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'dr.verma@hospital.org');
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.pumpAndSettle();

    final loginBtn = find.widgetWithText(ElevatedButton, 'Login');

    await tester.tap(loginBtn);
    await tester.pumpAndSettle();

    // 2. Hospital Dashboard renders
    expect(find.text('Good Morning, Dr. Verma'), findsOneWidget);
    expect(find.text('New Referrals'), findsOneWidget);

    // 3. Test Identity Matching navigation
    await tester.tap(find.text('Incoming'));
    await tester.pumpAndSettle();
    expect(find.text('High Confidence Match — 94%'), findsOneWidget);

    // Test Confirm Match action
    await tester.tap(find.text('Confirm Match'));
    await tester.pumpAndSettle();
    expect(find.text('Identity Match Confirmed: Patient records linked successfully.'), findsOneWidget);

    // Back to Hospital Dashboard
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Good Morning, Dr. Verma'), findsOneWidget);

    // 4. Test Review Details
    await tester.tap(find.text('Review Details').first);
    await tester.pumpAndSettle();
    expect(find.text('Referral Details'), findsOneWidget);

    // Back to Hospital Dashboard
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Good Morning, Dr. Verma'), findsOneWidget);

    // 5. Test Profile & Logout
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Hospital Staff Profile'), findsOneWidget);

    await tester.tap(find.text('Switch Facility / Log Out'));
    await tester.pumpAndSettle();

    // Verify returned to Login Screen
    expect(find.text('Welcome Back'), findsOneWidget);
  });

  testWidgets('TEST 4: Patient Login, Dashboard & Top-Left Back Button Session Exit', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(RelyCareApp(dependencies: dependencies));
    await tester.pumpAndSettle();

    // 1. Enter Patient credentials
    expect(find.text('Welcome Back'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'patient');
    await tester.enterText(find.byType(TextFormField).at(1), '12345678');
    await tester.pumpAndSettle();

    final loginBtn = find.widgetWithText(ElevatedButton, 'Login');
    await tester.tap(loginBtn);
    await tester.pumpAndSettle();

    // 2. Patient Tracking Dashboard renders
    expect(find.text('Track Your Referral'), findsOneWidget);
    expect(find.text('Enter your ID to see live status'), findsOneWidget);

    // 3. Tap top-left back button to exit session/logout
    final backBtn = find.byIcon(Icons.arrow_back_rounded);
    expect(backBtn, findsOneWidget);
    await tester.tap(backBtn);
    await tester.pumpAndSettle();

    // 4. Verify returned to Login Screen and session cleared
    expect(find.text('Welcome Back'), findsOneWidget);
    expect(dependencies.authProvider.isAuthenticated, false);
  });

  testWidgets('TEST 5: Hospital Dashboard Bottom Navigation Direct Tab Switching From Incoming & Details', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(RelyCareApp(dependencies: dependencies));
    await tester.pumpAndSettle();

    // 1. Enter Hospital Staff credentials
    expect(find.text('Welcome Back'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'hosp');
    await tester.enterText(find.byType(TextFormField).at(1), '12345678');
    await tester.pumpAndSettle();

    final loginBtn = find.widgetWithText(ElevatedButton, 'Login');
    await tester.tap(loginBtn);
    await tester.pumpAndSettle();

    expect(find.text('Good Morning, Dr. Verma'), findsOneWidget);

    // 2. Navigate to Incoming / Identity Matching screen via bottom nav
    final incomingNav = find.text('Incoming');
    await tester.tap(incomingNav.first);
    await tester.pumpAndSettle();
    expect(find.text('High Confidence Match — 94%'), findsOneWidget);

    // 3. Directly tap Sync in bottom navigation from Identity Matching
    final syncNav = find.text('Sync');
    await tester.tap(syncNav.first);
    await tester.pumpAndSettle();
    expect(find.text('Sync & Connectivity'), findsOneWidget);

    // 4. Return to Hospital Dashboard
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Good Morning, Dr. Verma'), findsOneWidget);

    // 5. Navigate to Incoming screen again
    await tester.tap(find.text('Incoming').first);
    await tester.pumpAndSettle();
    expect(find.text('High Confidence Match — 94%'), findsOneWidget);

    // 6. Directly tap Profile in bottom navigation from Identity Matching
    final profileNav = find.text('Profile');
    await tester.tap(profileNav.first);
    await tester.pumpAndSettle();
    expect(find.text('Hospital Staff Profile'), findsOneWidget);

    // 7. Return to Hospital Dashboard
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Good Morning, Dr. Verma'), findsOneWidget);

    // 8. Directly tap Home from Identity Matching
    await tester.tap(find.text('Incoming').first);
    await tester.pumpAndSettle();
    expect(find.text('High Confidence Match — 94%'), findsOneWidget);
    await tester.tap(find.text('Home').first);
    await tester.pumpAndSettle();
    expect(find.text('Good Morning, Dr. Verma'), findsOneWidget);

    // 9. Navigate to Profile and Logout
    await tester.tap(find.text('Profile').first);
    await tester.pumpAndSettle();
    expect(find.text('Hospital Staff Profile'), findsOneWidget);

    await tester.tap(find.text('Switch Facility / Log Out'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome Back'), findsOneWidget);
    expect(dependencies.authProvider.isAuthenticated, false);
  });
}

