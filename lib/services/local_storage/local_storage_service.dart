import 'dart:convert';
import 'package:drift/drift.dart';
import 'app_database.dart';
import '../../core/utils/logger.dart';
import '../../core/errors/app_exceptions.dart';
import '../../models/patient.dart';
import '../../models/referral.dart';
import '../../models/referral_status.dart';
import '../sms/sms_service.dart';

/// Abstract service contract for local SQLite / Drift storage operations.
abstract class LocalStorageService {
  /// Underlying Drift database instance.
  AppDatabase get db;

  // Patient Operations (Drift Table Level)
  Future<PatientData> createPatient({
    required String name,
    required int age,
    required String gender,
    String? phone,
    String? location,
  });
  Future<PatientData?> getPatientById(int id);
  Future<List<PatientData>> getAllPatients();
  Future<bool> updatePatient(PatientsCompanion patient);
  Future<int> deletePatient(int id);

  // Patient Operations (Domain Model Level)
  Future<void> savePatient(Patient patient);
  Future<Patient?> getDomainPatientById(String id);
  Future<List<Patient>> getAllDomainPatients();

  // Referral Operations (Drift Table Level)
  Future<ReferralData> createReferral({
    required int patientId,
    required String sourceFacility,
    required String destinationFacility,
    required String reason,
    String? clinicalNotes,
    String urgency = 'ROUTINE',
    String? customReferralId,
    String status = 'CREATED',
    String syncStatus = 'PENDING',
  });
  Future<ReferralData?> getReferral(String referralId);
  Future<ReferralData?> getReferralById(int id);
  Future<List<ReferralData>> getAllReferrals();
  Future<void> updateReferralStatus(String referralId, String status);
  Future<void> updateReferralSyncStatus(String referralId, String syncStatus);
  Future<int> deleteReferral(int id);

  // Referral Operations (Domain Model Level)
  Future<void> saveReferral(Referral referral);
  Future<Referral> upsertReferralFromSync(Referral referral);
  Future<Referral?> getDomainReferralById(String id);
  Future<List<Referral>> getAllDomainReferrals();
  Future<List<Referral>> getPendingSyncReferrals();
  Future<void> updateReferralSyncState(String referralId, SyncState syncState);

  // Referral Events / Timeline Operations
  Future<ReferralEventData> addReferralEvent({
    required String referralId,
    required String eventType,
    String? facility,
    String? performedBy,
    String? metadata,
    DateTime? timestamp,
  });
  Future<List<ReferralEventData>> getReferralEvents(String referralId);
  Future<SmsDeliveryStatus> getSmsDeliveryStatus(String referralId);

  // Offline Sync Queue Operations
  Future<SyncQueueData> queueForSync({
    required String entityType,
    required String entityId,
    required String operation,
    required String payload,
  });
  Future<List<SyncQueueData>> getPendingSyncItems();
  Future<List<SyncQueueData>> getEligibleSyncItems(int maxRetries);
  Future<List<SyncQueueData>> getRetryableFailedItems(int maxRetries);
  Future<List<SyncQueueData>> getFailedSyncItems();
  Future<void> markSyncing(int queueId);
  Future<void> markSyncSuccess(int queueId);
  Future<void> markSyncFailed(int queueId, {bool resetToPending = true});
  Future<void> resetSyncToPending(int queueId);
  Future<void> resetAllFailedSyncItems();

  // Atomic Referral Creation Transaction (Step 8)
  Future<ReferralData> createReferralTransaction({
    required String patientName,
    required int patientAge,
    required String patientGender,
    String? patientPhone,
    String? patientLocation,
    required String sourceFacility,
    required String destinationFacility,
    required String reason,
    String? clinicalNotes,
    ReferralUrgency urgency = ReferralUrgency.routine,
    String? customReferralId,
    String? createdByStaff,
  });

  /// Closes database connection safely.
  Future<void> close();
}

/// Concrete Drift implementation of [LocalStorageService].
class LocalStorageServiceImpl implements LocalStorageService {
  final AppDatabase _db;

  LocalStorageServiceImpl([AppDatabase? db]) : _db = db ?? AppDatabase();

  @override
  AppDatabase get db => _db;

  // ==========================================
  // PATIENT OPERATIONS (TABLE LEVEL)
  // ==========================================

  @override
  Future<PatientData> createPatient({
    required String name,
    required int age,
    required String gender,
    String? phone,
    String? location,
  }) async {
    if (name.trim().isEmpty) {
      throw const StorageException('Patient name cannot be empty');
    }
    if (age < 0 || age > 130) {
      throw const StorageException('Invalid patient age');
    }

    final companion = PatientsCompanion.insert(
      name: name.trim(),
      age: age,
      gender: gender.trim(),
      phone: Value(phone?.trim()),
      location: Value(location?.trim()),
    );

    final id = await _db.patientDao.insertPatient(companion);
    final patient = await _db.patientDao.getPatientById(id);
    if (patient == null) {
      throw StorageException('Failed to retrieve newly created patient with id $id');
    }
    return patient;
  }

  @override
  Future<PatientData?> getPatientById(int id) => _db.patientDao.getPatientById(id);

  @override
  Future<List<PatientData>> getAllPatients() => _db.patientDao.getAllPatients();

  @override
  Future<bool> updatePatient(PatientsCompanion patient) => _db.patientDao.updatePatient(patient);

  @override
  Future<int> deletePatient(int id) => _db.patientDao.deletePatient(id);

  // ==========================================
  // PATIENT OPERATIONS (DOMAIN MODEL LEVEL)
  // ==========================================

  @override
  Future<void> savePatient(Patient patient) async {
    final intId = int.tryParse(patient.id);
    if (intId != null) {
      final existing = await _db.patientDao.getPatientById(intId);
      if (existing != null) {
        await _db.patientDao.updatePatient(PatientsCompanion(
          id: Value(intId),
          name: Value(patient.fullName),
          age: Value(patient.age),
          gender: Value(patient.gender),
          phone: Value(patient.contactNumber),
          location: Value(patient.villageOrLocation),
          updatedAt: Value(DateTime.now()),
        ));
        return;
      }
    }
    await createPatient(
      name: patient.fullName,
      age: patient.age,
      gender: patient.gender,
      phone: patient.contactNumber,
      location: patient.villageOrLocation,
    );
  }

  @override
  Future<Patient?> getDomainPatientById(String id) async {
    final intId = int.tryParse(id);
    if (intId == null) return null;
    final row = await _db.patientDao.getPatientById(intId);
    if (row == null) return null;
    return _mapPatientDataToDomain(row);
  }

  @override
  Future<List<Patient>> getAllDomainPatients() async {
    final rows = await _db.patientDao.getAllPatients();
    return rows.map(_mapPatientDataToDomain).toList();
  }

  Patient _mapPatientDataToDomain(PatientData row) {
    return Patient(
      id: row.id.toString(),
      fullName: row.name,
      age: row.age,
      gender: row.gender,
      villageOrLocation: row.location ?? '',
      contactNumber: row.phone,
      createdAt: row.createdAt,
    );
  }

  // ==========================================
  // REFERRAL OPERATIONS (TABLE LEVEL)
  // ==========================================

  @override
  Future<ReferralData> createReferral({
    required int patientId,
    required String sourceFacility,
    required String destinationFacility,
    required String reason,
    String? clinicalNotes,
    String urgency = 'ROUTINE',
    String? customReferralId,
    String status = 'CREATED',
    String syncStatus = 'PENDING',
  }) async {
    final refId = customReferralId ?? _generateReferralToken();

    final companion = ReferralsCompanion.insert(
      referralId: refId,
      patientId: patientId,
      sourceFacility: sourceFacility.trim(),
      destinationFacility: destinationFacility.trim(),
      reason: reason.trim(),
      clinicalNotes: Value(clinicalNotes?.trim()),
      urgency: Value(urgency.toUpperCase()),
      status: Value(status),
      syncStatus: Value(syncStatus),
    );

    final rowId = await _db.referralDao.insertReferral(companion);
    final referral = await _db.referralDao.getReferralById(rowId);
    if (referral == null) {
      throw StorageException('Failed to retrieve newly created referral with row id $rowId');
    }
    return referral;
  }

  @override
  Future<ReferralData?> getReferral(String referralId) =>
      _db.referralDao.getReferralByReferralId(referralId);

  @override
  Future<ReferralData?> getReferralById(int id) => _db.referralDao.getReferralById(id);

  @override
  Future<List<ReferralData>> getAllReferrals() => _db.referralDao.getAllReferrals();

  @override
  Future<void> updateReferralStatus(String referralId, String status) async {
    await _db.referralDao.updateReferralStatus(referralId, status);
  }

  @override
  Future<void> updateReferralSyncStatus(String referralId, String syncStatus) async {
    await _db.referralDao.updateReferralSyncStatus(referralId, syncStatus);
  }

  @override
  Future<int> deleteReferral(int id) => _db.referralDao.deleteReferral(id);

  // ==========================================
  // REFERRAL OPERATIONS (DOMAIN MODEL LEVEL)
  // ==========================================

  @override
  Future<void> saveReferral(Referral referral) async {
    await upsertReferralFromSync(referral);
  }

  @override
  Future<Referral> upsertReferralFromSync(Referral referral) async {
    return await _db.transaction(() async {
      // Step 1: Guard against overwriting local pending unsynced changes
      // Checked before patient resolution to avoid creating unnecessary local patient records
      final existingReferral = await _db.referralDao.getReferralByReferralId(referral.referralToken);
      if (existingReferral != null) {
        if (existingReferral.syncStatus == 'PENDING' || existingReferral.syncStatus == 'SYNCING') {
          AppLogger.warning(
            'Referral ${referral.referralToken} has pending local changes; skipping sync overwrite',
            'LocalStorage',
          );
          return await _mapReferralDataToDomain(existingReferral);
        }
      }

      // Step 2: Patient Resolution (only for non-pending existing or new server referrals)
      int resolvedPatientId;
      final incomingPatient = referral.patient;

      if (incomingPatient != null) {
        PatientData? matchedPatient;

        // Try exact/normalized phone match first
        final phone = incomingPatient.contactNumber?.trim();
        if (phone != null && phone.isNotEmpty) {
          matchedPatient = await _db.patientDao.findPatientByPhone(phone);
        }

        // Try deterministic demographic match if no phone match
        matchedPatient ??= await _db.patientDao.findPatientByDemographics(
          name: incomingPatient.fullName,
          age: incomingPatient.age,
          gender: incomingPatient.gender,
          location: incomingPatient.villageOrLocation,
        );

        if (matchedPatient != null) {
          resolvedPatientId = matchedPatient.id;
        } else {
          // Create new local patient
          final newPatientCompanion = PatientsCompanion.insert(
            name: incomingPatient.fullName.trim().isNotEmpty ? incomingPatient.fullName.trim() : 'Unknown Patient',
            age: incomingPatient.age >= 0 ? incomingPatient.age : 0,
            gender: incomingPatient.gender.trim().isNotEmpty ? incomingPatient.gender.trim() : 'Other',
            phone: Value(incomingPatient.contactNumber?.trim()),
            location: Value(incomingPatient.villageOrLocation.trim()),
          );
          resolvedPatientId = await _db.patientDao.insertPatient(newPatientCompanion);
        }
      } else {
        // Fallback if referral has no attached patient entity
        final parsedId = int.tryParse(referral.patientId);
        if (parsedId != null) {
          final existing = await _db.patientDao.getPatientById(parsedId);
          if (existing != null) {
            resolvedPatientId = existing.id;
          } else {
            final newPatientCompanion = PatientsCompanion.insert(
              name: 'Unknown Patient',
              age: 0,
              gender: 'Other',
            );
            resolvedPatientId = await _db.patientDao.insertPatient(newPatientCompanion);
          }
        } else {
          final newPatientCompanion = PatientsCompanion.insert(
            name: 'Unknown Patient',
            age: 0,
            gender: 'Other',
          );
          resolvedPatientId = await _db.patientDao.insertPatient(newPatientCompanion);
        }
      }

      // Step 3: Referral Upsert
      if (existingReferral != null) {
        // Update server-sourced fields and set syncStatus to SYNCED
        await (_db.update(_db.referrals)..where((t) => t.referralId.equals(referral.referralToken))).write(
          ReferralsCompanion(
            patientId: Value(resolvedPatientId),
            sourceFacility: Value(referral.sourceFacilityId),
            destinationFacility: Value(referral.destinationFacilityId),
            reason: Value(referral.referralReason),
            clinicalNotes: Value(referral.clinicalNotesSummary),
            urgency: Value(referral.urgency.code),
            status: Value(referral.status.code),
            syncStatus: const Value('SYNCED'),
            updatedAt: Value(referral.updatedAt),
          ),
        );

        final updatedRow = await _db.referralDao.getReferralByReferralId(referral.referralToken);
        return await _mapReferralDataToDomain(updatedRow!);
      } else {
        // Insert new referral from server

        final newReferralCompanion = ReferralsCompanion.insert(
          referralId: referral.referralToken,
          patientId: resolvedPatientId,
          sourceFacility: referral.sourceFacilityId.trim(),
          destinationFacility: referral.destinationFacilityId.trim(),
          reason: referral.referralReason.trim(),
          clinicalNotes: Value(referral.clinicalNotesSummary?.trim()),
          urgency: Value(referral.urgency.code),
          status: Value(referral.status.code),
          syncStatus: const Value('SYNCED'),
          createdAt: Value(referral.createdAt),
          updatedAt: Value(referral.updatedAt),
        );

        final rowId = await _db.referralDao.insertReferral(newReferralCompanion);
        final insertedRow = await _db.referralDao.getReferralById(rowId);
        return await _mapReferralDataToDomain(insertedRow!);
      }
    });
  }

  @override
  Future<Referral?> getDomainReferralById(String id) async {
    ReferralData? row = await _db.referralDao.getReferralByReferralId(id);
    if (row == null) {
      final intId = int.tryParse(id);
      if (intId != null) {
        row = await _db.referralDao.getReferralById(intId);
      }
    }
    if (row == null) return null;
    return _mapReferralDataToDomain(row);
  }

  @override
  Future<List<Referral>> getAllDomainReferrals() async {
    final rows = await _db.referralDao.getAllReferrals();
    return Future.wait(rows.map(_mapReferralDataToDomain));
  }

  @override
  Future<List<Referral>> getPendingSyncReferrals() async {
    final allRows = await _db.referralDao.getAllReferrals();
    final pendingRows = allRows.where((r) => r.syncStatus == 'PENDING' || r.syncStatus == 'SYNC_FAILED');
    return Future.wait(pendingRows.map(_mapReferralDataToDomain));
  }

  @override
  Future<void> updateReferralSyncState(String referralId, SyncState syncState) async {
    await updateReferralSyncStatus(referralId, syncState.name.toUpperCase());
  }

  Future<Referral> _mapReferralDataToDomain(ReferralData row) async {
    final patientData = await _db.patientDao.getPatientById(row.patientId);
    final patient = patientData != null ? _mapPatientDataToDomain(patientData) : null;

    return Referral(
      id: row.id.toString(),
      referralToken: row.referralId,
      patientId: row.patientId.toString(),
      patient: patient,
      sourceFacilityId: row.sourceFacility,
      destinationFacilityId: row.destinationFacility,
      referralReason: row.reason,
      urgency: ReferralUrgencyExtension.fromString(row.urgency),
      clinicalNotesSummary: row.clinicalNotes,
      status: ReferralStatusExtension.fromString(row.status),
      syncState: row.syncStatus == 'SYNCED'
          ? SyncState.synced
          : row.syncStatus == 'FAILED'
              ? SyncState.syncFailed
              : SyncState.pendingSync,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  // ==========================================
  // REFERRAL EVENTS / TIMELINE OPERATIONS
  // ==========================================

  @override
  Future<ReferralEventData> addReferralEvent({
    required String referralId,
    required String eventType,
    String? facility,
    String? performedBy,
    String? metadata,
    DateTime? timestamp,
  }) async {
    final companion = ReferralEventsCompanion.insert(
      referralId: referralId,
      eventType: eventType,
      timestamp: Value(timestamp ?? DateTime.now()),
      facility: Value(facility),
      performedBy: Value(performedBy),
      metadata: Value(metadata),
    );

    final id = await _db.referralDao.insertReferralEvent(companion);
    return ReferralEventData(
      id: id,
      referralId: referralId,
      eventType: eventType,
      timestamp: timestamp ?? DateTime.now(),
      facility: facility,
      performedBy: performedBy,
      metadata: metadata,
    );
  }

  @override
  Future<List<ReferralEventData>> getReferralEvents(String referralId) async {
    final direct = await _db.referralDao.getEventsForReferral(referralId);
    if (direct.isNotEmpty) return direct;

    final intId = int.tryParse(referralId);
    if (intId != null) {
      final ref = await _db.referralDao.getReferralById(intId);
      if (ref != null) {
        return await _db.referralDao.getEventsForReferral(ref.referralId);
      }
    }
    return [];
  }

  @override
  Future<SmsDeliveryStatus> getSmsDeliveryStatus(String referralId) async {
    final events = await getReferralEvents(referralId);
    if (events.isEmpty) return SmsDeliveryStatus.notSent;

    // Check if any event records successful SMS dispatch
    final hasSent = events.any((e) => e.eventType == 'SMS_SENT');
    if (hasSent) return SmsDeliveryStatus.sent;

    // Check the latest SMS-specific event
    final smsEvents = events.where((e) => e.eventType == 'SMS_SENT' || e.eventType == 'SMS_FAILED' || e.eventType == 'SMS_PENDING').toList();
    if (smsEvents.isNotEmpty) {
      final latest = smsEvents.first; // events are ordered by timestamp descending or insertion
      if (latest.eventType == 'SMS_FAILED') return SmsDeliveryStatus.failed;
      if (latest.eventType == 'SMS_PENDING') return SmsDeliveryStatus.pending;
    }

    return SmsDeliveryStatus.notSent;
  }

  // ==========================================
  // OFFLINE SYNC QUEUE OPERATIONS
  // ==========================================

  @override
  Future<SyncQueueData> queueForSync({
    required String entityType,
    required String entityId,
    required String operation,
    required String payload,
  }) async {
    final companion = SyncQueueCompanion.insert(
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      payload: payload,
    );

    final id = await _db.syncQueueDao.addToQueue(companion);
    return SyncQueueData(
      id: id,
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      payload: payload,
      status: 'PENDING',
      retryCount: 0,
      createdAt: DateTime.now(),
      lastAttempt: null,
    );
  }

  @override
  Future<List<SyncQueueData>> getPendingSyncItems() => _db.syncQueueDao.getPendingItems();

  @override
  Future<List<SyncQueueData>> getEligibleSyncItems(int maxRetries) =>
      _db.syncQueueDao.getEligibleItems(maxRetries);

  @override
  Future<List<SyncQueueData>> getRetryableFailedItems(int maxRetries) =>
      _db.syncQueueDao.getRetryableFailedItems(maxRetries);

  @override
  Future<List<SyncQueueData>> getFailedSyncItems() => _db.syncQueueDao.getFailedItems();

  @override
  Future<void> markSyncing(int queueId) async {
    await _db.syncQueueDao.markSyncing(queueId);
  }

  @override
  Future<void> markSyncSuccess(int queueId) async {
    await _db.syncQueueDao.markSuccess(queueId);
  }

  @override
  Future<void> markSyncFailed(int queueId, {bool resetToPending = true}) async {
    await _db.syncQueueDao.markFailed(queueId, resetToPending: resetToPending);
    await _db.syncQueueDao.incrementRetryCount(queueId);
  }

  @override
  Future<void> resetSyncToPending(int queueId) async {
    await _db.syncQueueDao.markFailed(queueId, resetToPending: true);
  }

  @override
  Future<void> resetAllFailedSyncItems() async {
    await _db.syncQueueDao.resetFailedItemsToPending();
  }

  // ==========================================
  // ATOMIC REFERRAL TRANSACTION (STEP 8)
  // ==========================================

  @override
  Future<ReferralData> createReferralTransaction({
    required String patientName,
    required int patientAge,
    required String patientGender,
    String? patientPhone,
    String? patientLocation,
    required String sourceFacility,
    required String destinationFacility,
    required String reason,
    String? clinicalNotes,
    ReferralUrgency urgency = ReferralUrgency.routine,
    String? customReferralId,
    String? createdByStaff,
  }) async {
    // 1. Validate patient and referral input
    if (patientName.trim().isEmpty) {
      throw const StorageException('Patient name is required');
    }
    if (patientAge < 0 || patientAge > 130) {
      throw const StorageException('Valid patient age (0-130) is required');
    }
    if (patientGender.trim().isEmpty) {
      throw const StorageException('Patient gender is required');
    }
    if (sourceFacility.trim().isEmpty) {
      throw const StorageException('Source facility is required');
    }
    if (destinationFacility.trim().isEmpty) {
      throw const StorageException('Destination facility is required');
    }
    if (reason.trim().isEmpty) {
      throw const StorageException('Referral reason is required');
    }

    final referralToken = customReferralId ?? _generateReferralToken();

    // Execute within a single atomic Drift transaction
    return await _db.transaction(() async {
      // Step 2: Save Patient Locally
      final patientCompanion = PatientsCompanion.insert(
        name: patientName.trim(),
        age: patientAge,
        gender: patientGender.trim(),
        phone: Value(patientPhone?.trim()),
        location: Value(patientLocation?.trim()),
      );
      final patientId = await _db.patientDao.insertPatient(patientCompanion);

      // Step 3 & 4: Save Referral Record Locally
      final referralCompanion = ReferralsCompanion.insert(
        referralId: referralToken,
        patientId: patientId,
        sourceFacility: sourceFacility.trim(),
        destinationFacility: destinationFacility.trim(),
        reason: reason.trim(),
        clinicalNotes: Value(clinicalNotes?.trim()),
        urgency: Value(urgency.code),
        status: const Value('CREATED'),
        syncStatus: const Value('PENDING'),
      );
      final referralRowId = await _db.referralDao.insertReferral(referralCompanion);

      // Step 5: Create a CREATED Referral Event
      final eventCompanion = ReferralEventsCompanion.insert(
        referralId: referralToken,
        eventType: 'CREATED',
        facility: Value(sourceFacility.trim()),
        performedBy: Value(createdByStaff ?? 'PHC Clinician'),
        metadata: const Value('Referral initiated and stored locally'),
      );
      await _db.referralDao.insertReferralEvent(eventCompanion);

      // Step 6: Add to Sync Queue
      final syncPayload = jsonEncode({
        'referralId': referralToken,
        'patient': {
          'id': patientId,
          'name': patientName.trim(),
          'age': patientAge,
          'gender': patientGender.trim(),
          'phone': patientPhone?.trim(),
          'location': patientLocation?.trim(),
        },
        'sourceFacility': sourceFacility.trim(),
        'destinationFacility': destinationFacility.trim(),
        'reason': reason.trim(),
        'clinicalNotes': clinicalNotes?.trim(),
        'urgency': urgency.code,
        'status': 'CREATED',
        'createdAt': DateTime.now().toIso8601String(),
      });

      final syncCompanion = SyncQueueCompanion.insert(
        entityType: 'referral',
        entityId: referralToken,
        operation: 'CREATE',
        payload: syncPayload,
      );
      await _db.syncQueueDao.addToQueue(syncCompanion);

      // Retrieve full referral data to return
      final createdReferral = await _db.referralDao.getReferralById(referralRowId);
      if (createdReferral == null) {
        throw StorageException('Transaction error: Failed to retrieve referral $referralRowId');
      }

      AppLogger.info('Referral $referralToken successfully created in transaction', 'LocalStorage');
      return createdReferral;
    });
  }

  @override
  Future<void> close() async {
    await _db.close();
  }

  /// Generates a human-friendly unique referral token (e.g. "RC-9A4B2").
  String _generateReferralToken() {
    final now = DateTime.now();
    final millis = (now.millisecondsSinceEpoch % 1000000).toRadixString(36).toUpperCase();
    final randomSuffix = (now.microsecondsSinceEpoch % 1296).toRadixString(36).padLeft(2, '0').toUpperCase();
    return 'RC-$millis$randomSuffix';
  }
}
