/// Environment and Runtime Configuration for RelyCare.
enum AppEnvironment { development, staging, production }

class AppConfig {
  final AppEnvironment environment;
  final String apiBaseUrl;
  final bool enableOfflineMocking;
  final bool enableDebugLogs;

  const AppConfig({
    required this.environment,
    required this.apiBaseUrl,
    this.enableOfflineMocking = true,
    this.enableDebugLogs = true,
  });

  /// Default configuration for local development / hackathon demo
  static const AppConfig development = AppConfig(
    environment: AppEnvironment.development,
    apiBaseUrl: String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://localhost:8000/api/v1',
    ),
    enableOfflineMocking: true,
    enableDebugLogs: true,
  );

  // TODO: Add staging and production static presets when deployed.
}
