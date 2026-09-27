import '../../models/referral.dart';
import '../../core/utils/logger.dart';

/// SMS Delivery Status representing the local tracking state of an SMS fallback attempt.
enum SmsDeliveryStatus {
  notSent,
  pending,
  sent,
  failed,
}

extension SmsDeliveryStatusExtension on SmsDeliveryStatus {
  String get code {
    switch (this) {
      case SmsDeliveryStatus.notSent:
        return 'NOT_SENT';
      case SmsDeliveryStatus.pending:
        return 'PENDING';
      case SmsDeliveryStatus.sent:
        return 'SENT';
      case SmsDeliveryStatus.failed:
        return 'FAILED';
    }
  }

  bool get isSent => this == SmsDeliveryStatus.sent;
  bool get isFailed => this == SmsDeliveryStatus.failed;
}

/// Result object for SMS fallback transmissions.
class SmsResult {
  final bool isSuccess;
  final String? messageId;
  final String? errorMessage;
  final String payload;
  final DateTime timestamp;

  const SmsResult({
    required this.isSuccess,
    this.messageId,
    this.errorMessage,
    required this.payload,
    required this.timestamp,
  });

  factory SmsResult.success({
    required String payload,
    String? messageId,
  }) {
    return SmsResult(
      isSuccess: true,
      messageId: messageId ?? 'MOCK-SMS-${DateTime.now().millisecondsSinceEpoch}',
      payload: payload,
      timestamp: DateTime.now(),
    );
  }

  factory SmsResult.failure({
    required String payload,
    required String errorMessage,
  }) {
    return SmsResult(
      isSuccess: false,
      errorMessage: errorMessage,
      payload: payload,
      timestamp: DateTime.now(),
    );
  }
}

/// Abstract contract for SMS Fallback transmission.
abstract class SmsService {
  /// Whether this service represents an actual real SMS delivery channel (vs. mock/simulation).
  bool get isRealService;

  /// Generates a compact, privacy-safe SMS message payload with minimal necessary data.
  String generateSmsPayload(Referral referral);

  /// Dispatches the SMS fallback message to the designated facility / health worker.
  Future<SmsResult> sendReferralSms({
    required String recipientPhoneNumber,
    required Referral referral,
  });
}

/// Concrete mock implementation of [SmsService] for offline fallback simulation.
///
/// PRIVACY & DATA MINIMIZATION PRINCIPLES:
/// - Unencrypted plain SMS must NEVER include clinical diagnoses, medical history,
///   or full clinical notes.
/// - Patient name is sanitized to First Name + Last Initial (e.g. "Rahul S").
/// - Uses minimal routing identifiers (Token, Source Facility, Destination Facility, Age).
class MockSmsService implements SmsService {
  @override
  final bool isRealService;

  bool shouldFail = false;
  final List<String> sentPayloads = [];
  final List<String> sentRecipients = [];

  MockSmsService({
    this.isRealService = false,
    this.shouldFail = false,
  });

  @override

  String generateSmsPayload(Referral referral) {
    final patient = referral.patient;
    final sanitizedName = _sanitizePatientName(patient?.fullName);
    final age = patient?.age ?? 0;
    final token = referral.referralToken;
    final source = referral.sourceFacilityId;
    final dest = referral.destinationFacilityId;

    final payload = 'RelyCare Referral\n'
        'REF: $token\n'
        'PHC: $source\n'
        'PAT: $sanitizedName\n'
        'AGE: $age\n'
        'DST: $dest';

    AppLogger.info('Generated compact SMS payload:\n$payload', 'SmsService');
    return payload;
  }

  @override
  Future<SmsResult> sendReferralSms({
    required String recipientPhoneNumber,
    required Referral referral,
  }) async {
    final payload = generateSmsPayload(referral);

    if (shouldFail) {
      AppLogger.warning(
        'Mock SMS delivery failed to $recipientPhoneNumber for ${referral.referralToken}',
        'SmsService',
      );
      return SmsResult.failure(
        payload: payload,
        errorMessage: 'Mock SMS gateway transmission failed: Network/modem error',
      );
    }

    sentPayloads.add(payload);
    sentRecipients.add(recipientPhoneNumber);

    AppLogger.info(
      'Mock SMS successfully dispatched to $recipientPhoneNumber for ${referral.referralToken}',
      'SmsService',
    );

    return SmsResult.success(
      payload: payload,
      messageId: 'MOCK-SMS-${DateTime.now().millisecondsSinceEpoch}',
    );
  }

  /// Sanitizes full name to First Name + Initial for privacy (e.g. "Rahul Sharma" -> "Rahul S").
  static String _sanitizePatientName(String? fullName) {
    if (fullName == null || fullName.trim().isEmpty) {
      return 'UNKNOWN';
    }
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts.first;
    }
    final firstName = parts.first;
    final lastInitial = parts.last[0].toUpperCase();
    return '$firstName $lastInitial';
  }
}
