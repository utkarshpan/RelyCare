// ignore_for_file: prefer_initializing_formals
import 'package:flutter/material.dart';
import '../models/referral.dart';
import '../models/referral_status.dart';
import '../repositories/referral_repository.dart';
import '../services/local_storage/app_database.dart';
import '../services/sms/sms_service.dart';

/// State management for referral lists, detail views, offline creation, and SMS fallback.
class ReferralProvider extends ChangeNotifier {
  final ReferralRepository referralRepository;

  List<Referral> _referrals = [];
  bool _isLoading = false;
  bool _isCreating = false;
  bool _isSendingSms = false;
  String? _errorMessage;
  Referral? _selectedReferral;
  Referral? _lastCreatedReferral;
  bool _isDisposed = false;

  ReferralProvider({required this.referralRepository});

  List<Referral> get referrals => _referrals;
  bool get isLoading => _isLoading;
  bool get isCreating => _isCreating;
  bool get isSendingSms => _isSendingSms;
  String? get errorMessage => _errorMessage;
  Referral? get selectedReferral => _selectedReferral;
  Referral? get lastCreatedReferral => _lastCreatedReferral;

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  /// Loads all referrals from local SQLite storage.
  Future<void> loadReferrals() async {
    if (_isDisposed) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final list = await referralRepository.getAllReferrals();
      if (!_isDisposed) {
        _referrals = list;
      }
    } catch (e) {
      if (!_isDisposed) {
        _errorMessage = 'Failed to load referrals: $e';
      }
    } finally {
      if (!_isDisposed) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Pulls latest referrals from server into local SQLite and refreshes state.
  Future<List<Referral>> pullReferrals({int skip = 0, int limit = 100, String? status}) async {
    if (_isLoading || _isDisposed) return _referrals;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final list = await referralRepository.pullReferralsFromServer(skip: skip, limit: limit, status: status);
      await loadReferrals();
      return list;
    } catch (e) {
      if (!_isDisposed) {
        _errorMessage = 'Failed to pull referrals: $e';
      }
      rethrow;
    } finally {
      if (!_isDisposed) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Creates a new referral offline with duplicate submission protection.
  Future<Referral?> createReferral({
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
    String recipientPhoneNumber = '+91 9988776655',
    bool autoSync = true,
  }) async {
    // Prevent duplicate simultaneous submissions
    if (_isCreating || _isDisposed) {
      return null;
    }

    _isCreating = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final newReferral = await referralRepository.createReferralOffline(
        patientName: patientName,
        patientAge: patientAge,
        patientGender: patientGender,
        patientPhone: patientPhone,
        patientLocation: patientLocation,
        sourceFacility: sourceFacility,
        destinationFacility: destinationFacility,
        reason: reason,
        clinicalNotes: clinicalNotes,
        urgency: urgency,
        customReferralId: customReferralId,
        createdByStaff: createdByStaff,
        recipientPhoneNumber: recipientPhoneNumber,
        autoSync: autoSync,
      );

      if (!_isDisposed) {
        _referrals.removeWhere((r) => r.referralToken == newReferral.referralToken);
        _referrals.insert(0, newReferral);
        _lastCreatedReferral = newReferral;
      }
      return newReferral;
    } catch (e) {
      if (!_isDisposed) {
        _errorMessage = 'Failed to create referral: $e';
      }
      return null;
    } finally {
      if (!_isDisposed) {
        _isCreating = false;
        notifyListeners();
      }
    }
  }

  /// Dispatches an SMS fallback message for a locally stored referral.
  Future<SmsResult?> sendSmsFallback(
    String referralToken, {
    String recipientPhoneNumber = '+91 9988776655',
    bool forceRetry = false,
  }) async {
    if (_isSendingSms || _isDisposed) return null;

    _isSendingSms = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await referralRepository.sendSmsFallback(
        referralToken,
        recipientPhoneNumber: recipientPhoneNumber,
        forceRetry: forceRetry,
      );
      return result;
    } catch (e) {
      if (!_isDisposed) {
        _errorMessage = 'SMS fallback failed: $e';
      }
      return null;
    } finally {
      if (!_isDisposed) {
        _isSendingSms = false;
        notifyListeners();
      }
    }
  }

  /// Retrieves the SMS delivery status of a referral.
  Future<SmsDeliveryStatus> getSmsDeliveryStatus(String referralToken) async {
    return await referralRepository.getSmsStatus(referralToken);
  }

  /// Retrieves events timeline for a referral.
  Future<List<ReferralEventData>> getReferralEvents(String referralId) async {
    return await referralRepository.getReferralEvents(referralId);
  }

  /// Updates status of an existing referral.
  Future<void> updateReferralStatus(String id, ReferralStatus newStatus) async {
    if (_isDisposed) return;
    try {
      await referralRepository.updateStatus(id, newStatus);
      await loadReferrals();
    } catch (e) {
      if (!_isDisposed) {
        _errorMessage = 'Failed to update status: $e';
        notifyListeners();
      }
    }
  }

  void selectReferral(Referral referral) {
    if (_isDisposed) return;
    _selectedReferral = referral;
    notifyListeners();
  }
}
