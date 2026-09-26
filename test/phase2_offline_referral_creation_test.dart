import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:relycare/models/referral.dart';
import 'package:relycare/models/referral_status.dart';
import 'package:relycare/providers/referral_provider.dart';
import 'package:relycare/repositories/patient_repository.dart';
import 'package:relycare/repositories/referral_repository.dart';
import 'package:relycare/services/api/api_service.dart';
import 'package:relycare/services/connectivity/connectivity_service.dart';
import 'package:relycare/services/local_storage/app_database.dart';
import 'package:relycare/services/local_storage/local_storage_service.dart';
import 'package:relycare/services/sms/sms_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 2: Offline Referral Creation Tests', () {
    late AppDatabase db;
    late LocalStorageService localStorage;
    late ReferralRepository referralRepository;
    late PatientRepository patientRepository;
    late ReferralProvider referralProvider;
    late Directory tempDir;
    late File tempDbFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('relycare_phase2_test_');
      tempDbFile = File(p.join(tempDir.path, 'relycare_phase2.sqlite'));

      db = AppDatabase(NativeDatabase.memory());
      localStorage = LocalStorageServiceImpl(db);
      referralRepository = ReferralRepository(
        localStorage: localStorage,
        apiService: ApiServiceImpl(baseUrl: 'http://localhost:8000/api/v1'),
        connectivityService: ConnectivityServiceImpl(),
        smsService: MockSmsService(),
      );
      patientRepository = PatientRepository(
        localStorage: localStorage,
        apiService: ApiServiceImpl(baseUrl: 'http://localhost:8000/api/v1'),
        connectivityService: ConnectivityServiceImpl(),
      );
      referralProvider = ReferralProvider(
        referralRepository: referralRepository,
      );
    });

    tearDown(() async {
      await localStorage.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('A. Successful offline referral creation flow creates Patient, Referral, CREATED Event, and PENDING SyncQueue atomically', () async {
      // 1. Create offline referral through Provider
      final createdReferral = await referralProvider.createReferral(
        patientName: 'Sunita Sharma',
        patientAge: 28,
        patientGender: 'Female',
        patientPhone: '+91 9876543210',
        patientLocation: 'Gram Panchayat Kalyanpur',
        sourceFacility: 'PHC Kalyanpur',
        destinationFacility: 'Civil Hospital Gorakhpur',
        reason: 'High-risk pregnancy with severe anemia',
        clinicalNotes: 'Hb 6.8 g/dL, BP 140/90 mmHg',
      );

      expect(createdReferral, isNotNull);
      final ref = createdReferral!;

      // 2. Verify returned referral object
      expect(ref.referralToken, startsWith('RC-'));
      expect(ref.patient?.fullName, equals('Sunita Sharma'));
      expect(ref.patient?.age, equals(28));
      expect(ref.patient?.gender, equals('Female'));
      expect(ref.sourceFacilityId, equals('PHC Kalyanpur'));
      expect(ref.destinationFacilityId, equals('Civil Hospital Gorakhpur'));
      expect(ref.referralReason, equals('High-risk pregnancy with severe anemia'));
      expect(ref.status, equals(ReferralStatus.created));
      expect(ref.syncState, equals(SyncState.pendingSync));

      // 3. Verify Patient exists in SQLite
      final patient = await patientRepository.getPatientById(ref.patientId);
      expect(patient, isNotNull);
      expect(patient!.fullName, equals('Sunita Sharma'));
      expect(patient.age, equals(28));
      expect(patient.gender, equals('Female'));
      expect(patient.contactNumber, equals('+91 9876543210'));
      expect(patient.villageOrLocation, equals('Gram Panchayat Kalyanpur'));

      // 4. Verify Referral exists in SQLite with status CREATED
      final fetchedReferral = await referralRepository.getReferralById(ref.id);
      expect(fetchedReferral, isNotNull);
      expect(fetchedReferral!.status, equals(ReferralStatus.created));
      expect(fetchedReferral.syncState, equals(SyncState.pendingSync));
      expect(fetchedReferral.referralToken, equals(ref.referralToken));

      // 5. Verify CREATED ReferralEvent exists in SQLite
      final events = await referralProvider.getReferralEvents(ref.id);
      expect(events.any((e) => e.eventType == 'CREATED'), isTrue);
      expect(events.firstWhere((e) => e.eventType == 'CREATED').facility, equals('PHC Kalyanpur'));

      // 6. Verify SyncQueue record exists with status PENDING
      final pendingQueueItems = await localStorage.getPendingSyncItems();
      expect(pendingQueueItems.length, equals(1));
      final syncItem = pendingQueueItems.first;
      expect(syncItem.entityId, equals(ref.referralToken));
      expect(syncItem.entityType, equals('referral'));
      expect(syncItem.operation, equals('CREATE'));
      expect(syncItem.status, equals('PENDING'));
      expect(syncItem.retryCount, equals(0));

      // 7. Verify Referral is immediately available in local referral list
      await referralProvider.loadReferrals();
      expect(referralProvider.referrals.length, equals(1));
      expect(referralProvider.referrals.first.id, equals(ref.id));
    });

    test('B. Persistence: referral created in SQLite persists across database reconnect', () async {
      // Step 1: Open file-backed DB and create referral
      final fileDb1 = AppDatabase(NativeDatabase(tempDbFile));
      final fileStorage1 = LocalStorageServiceImpl(fileDb1);
      final fileReferralRepo1 = ReferralRepository(
        localStorage: fileStorage1,
        apiService: ApiServiceImpl(baseUrl: 'http://localhost:8000/api/v1'),
        connectivityService: ConnectivityServiceImpl(),
        smsService: MockSmsService(),
      );
      final fileProvider1 = ReferralProvider(
        referralRepository: fileReferralRepo1,
      );

      final created = await fileProvider1.createReferral(
        patientName: 'Devendra Patel',
        patientAge: 52,
        patientGender: 'Male',
        sourceFacility: 'PHC A',
        destinationFacility: 'DH B',
        reason: 'Uncontrolled diabetes',
      );

      expect(created, isNotNull);
      final createdToken = created!.referralToken;
      final createdId = created.id;

      // Step 2: Close database completely
      await fileStorage1.close();

      // Step 3: Re-open database from the exact same file
      final fileDb2 = AppDatabase(NativeDatabase(tempDbFile));
      final fileStorage2 = LocalStorageServiceImpl(fileDb2);
      final fileReferralRepo2 = ReferralRepository(
        localStorage: fileStorage2,
        apiService: ApiServiceImpl(baseUrl: 'http://localhost:8000/api/v1'),
        connectivityService: ConnectivityServiceImpl(),
        smsService: MockSmsService(),
      );
      final fileProvider2 = ReferralProvider(
        referralRepository: fileReferralRepo2,
      );

      await fileProvider2.loadReferrals();
      expect(fileProvider2.referrals.length, equals(1));
      expect(fileProvider2.referrals.first.id, equals(createdId));
      expect(fileProvider2.referrals.first.referralToken, equals(createdToken));
      expect(fileProvider2.referrals.first.patient?.fullName, equals('Devendra Patel'));
      expect(fileProvider2.referrals.first.status, equals(ReferralStatus.created));

      final persistedQueue = await fileStorage2.getPendingSyncItems();
      expect(persistedQueue.length, equals(1));
      expect(persistedQueue.first.entityId, equals(createdToken));
      expect(persistedQueue.first.status, equals('PENDING'));

      await fileStorage2.close();
    });

    test('C. Validation failures abort transaction and create NO partial data', () async {
      // 1. Missing patient name
      final res1 = await referralProvider.createReferral(
        patientName: '   ',
        patientAge: 30,
        patientGender: 'Male',
        sourceFacility: 'PHC A',
        destinationFacility: 'DH B',
        reason: 'Routine checkup',
      );
      expect(res1, isNull);
      expect(referralProvider.errorMessage?.toLowerCase(), contains('patient name'));

      // 2. Invalid age (< 0)
      final res2 = await referralProvider.createReferral(
        patientName: 'Valid Name',
        patientAge: -5,
        patientGender: 'Male',
        sourceFacility: 'PHC A',
        destinationFacility: 'DH B',
        reason: 'Routine checkup',
      );
      expect(res2, isNull);
      expect(referralProvider.errorMessage?.toLowerCase(), contains('age'));

      // 3. Missing destination facility
      final res3 = await referralProvider.createReferral(
        patientName: 'Valid Name',
        patientAge: 30,
        patientGender: 'Male',
        sourceFacility: 'PHC A',
        destinationFacility: '',
        reason: 'Routine checkup',
      );
      expect(res3, isNull);
      expect(referralProvider.errorMessage?.toLowerCase(), contains('destination facility'));

      // 4. Missing referral reason
      final res4 = await referralProvider.createReferral(
        patientName: 'Valid Name',
        patientAge: 30,
        patientGender: 'Male',
        sourceFacility: 'PHC A',
        destinationFacility: 'DH B',
        reason: '',
      );
      expect(res4, isNull);
      expect(referralProvider.errorMessage?.toLowerCase(), contains('reason'));

      // Verify that database is completely clean (zero partial records)
      final allPatients = await patientRepository.getAllPatients();
      expect(allPatients.isEmpty, isTrue);

      final allReferrals = await referralRepository.getAllReferrals();
      expect(allReferrals.isEmpty, isTrue);

      final allQueueItems = await localStorage.getPendingSyncItems();
      expect(allQueueItems.isEmpty, isTrue);
    });

    test('D. Duplicate submission protection prevents concurrent duplicate creations', () async {
      expect(referralProvider.isCreating, isFalse);

      // Trigger first referral creation
      final future1 = referralProvider.createReferral(
        patientName: 'Geeta Rani',
        patientAge: 40,
        patientGender: 'Female',
        sourceFacility: 'PHC North',
        destinationFacility: 'DH Central',
        reason: 'Severe fever',
      );

      // Trigger second duplicate submission while first is in flight
      final future2 = referralProvider.createReferral(
        patientName: 'Geeta Rani',
        patientAge: 40,
        patientGender: 'Female',
        sourceFacility: 'PHC North',
        destinationFacility: 'DH Central',
        reason: 'Severe fever',
      );

      final results = await Future.wait([future1, future2]);
      // One succeeds, second is rejected by duplicate guard
      expect(results.where((r) => r != null).length, equals(1));
      expect(referralProvider.isCreating, isFalse);

      // Exactly 1 referral created in SQLite
      await referralProvider.loadReferrals();
      expect(referralProvider.referrals.length, equals(1));
    });
  });
}
