/// Global application constants for RelayCare.
class AppConstants {
  // App Metadata
  static const String appName = 'RelyCare';
  static const String appVersion = '1.0.0';
  static const String appTagline = 'Offline-First Healthcare Referral Continuity';

  // Timeouts & Durations (in milliseconds)
  static const int connectTimeoutMs = 10000;
  static const int receiveTimeoutMs = 15000;
  static const int syncIntervalSeconds = 60;

  // Matching Thresholds
  static const double highConfidenceThreshold = 0.85;
  static const double mediumConfidenceThreshold = 0.60;

  // Sync & Retry Policy
  static const int maxSyncRetries = 3;

  // Referral Guardian Prototype Operational Time Windows
  static const Duration guardianAtRiskWindow = Duration(hours: 2);
  static const Duration guardianActionRequiredWindow = Duration(hours: 6);
}
