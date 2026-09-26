/// API Endpoints and Network Configuration for FastAPI backend integration.
class ApiConstants {
  // Base URLs (Development & Local Mock)
  // TODO: Update with your actual FastAPI server IP/domain when hosting backend
  static const String defaultBaseUrl = 'http://10.0.2.2:8000/api/v1'; // For Android emulator
  static const String localhostBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000/api/v1',
  );

  // Referral Endpoints
  static const String referrals = '/referrals';
  static const String syncReferrals = '/referrals/sync';
  static const String referralDetails = '/referrals/{id}';
  static const String updateStatus = '/referrals/{id}/status';

  // Patient & Matching Endpoints
  static const String matchPatient = '/patients/match';
  static const String patients = '/patients';

  // Facility Endpoints
  static const String facilities = '/facilities';
  static const String authLogin = '/auth/login';

  // TODO: Add headers, API keys, or JWT token helper constants.
}
