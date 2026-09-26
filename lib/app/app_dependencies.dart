import 'package:flutter/material.dart';
import '../services/local_storage/local_storage_service.dart';
import '../services/api/api_service.dart';
import '../services/connectivity/connectivity_service.dart';
import '../services/sms/sms_service.dart';
import '../services/matching/matching_service.dart';
import '../services/sync/sync_service.dart';
import '../services/security/auth_storage_service.dart';
import '../repositories/patient_repository.dart';
import '../repositories/referral_repository.dart';
import '../repositories/sync_repository.dart';
import '../providers/auth_provider.dart';
import '../providers/referral_provider.dart';
import '../providers/connectivity_provider.dart';
import '../providers/sync_provider.dart';
import '../providers/identity_matching_provider.dart';

/// Container for all application services, repositories, and state providers.
class AppDependencies {
  final LocalStorageService localStorage;
  final ApiService apiService;
  final ConnectivityService connectivityService;
  final SmsService smsService;
  final MatchingService matchingService;
  final AuthStorageService authStorageService;

  final PatientRepository patientRepository;
  final ReferralRepository referralRepository;
  final SyncRepository syncRepository;

  final AuthProvider authProvider;
  final ReferralProvider referralProvider;
  final ConnectivityProvider connectivityProvider;
  final SyncProvider syncProvider;
  final IdentityMatchingProvider identityMatchingProvider;

  factory AppDependencies({
    LocalStorageService? localStorage,
    ApiService? apiService,
    ConnectivityService? connectivityService,
    SmsService? smsService,
    MatchingService? matchingService,
    AuthStorageService? authStorageService,
    PatientRepository? patientRepository,
    ReferralRepository? referralRepository,
    SyncRepository? syncRepository,
    AuthProvider? authProvider,
    ReferralProvider? referralProvider,
    ConnectivityProvider? connectivityProvider,
    SyncProvider? syncProvider,
    IdentityMatchingProvider? identityMatchingProvider,
  }) {
    final storage = localStorage ?? LocalStorageServiceImpl();
    final api = apiService ??
        ApiServiceImpl(
          baseUrl: const String.fromEnvironment(
            'API_BASE_URL',
            defaultValue: 'http://localhost:8000/api/v1', 
          ),
        );
    final connectivity = connectivityService ?? ConnectivityServiceImpl();
    final sms = smsService ?? MockSmsService();
    final matching = matchingService ?? MatchingService();
    final authStorage = authStorageService ?? AuthStorageServiceImpl();

    final authProv = authProvider ??
        AuthProvider(
          apiService: api,
          authStorage: authStorage,
        );

    final patientRepo = patientRepository ??
        PatientRepository(
          localStorage: storage,
          apiService: api,
          connectivityService: connectivity,
        );

    final sync = SyncService(
      localStorage: storage,
      apiService: api,
      connectivityService: connectivity,
    );

    final referralRepo = referralRepository ??
        ReferralRepository(
          localStorage: storage,
          apiService: api,
          connectivityService: connectivity,
          smsService: sms,
          syncService: sync,
        );

    final syncRepo = syncRepository ??
        SyncRepository(
          localStorage: storage,
          syncService: sync,
        );

    final referralProv = referralProvider ??
        ReferralProvider(
          referralRepository: referralRepo,
        );

    final connectivityProv = connectivityProvider ??
        ConnectivityProvider(
          connectivityService: connectivity,
        );

    final syncProv = syncProvider ??
        SyncProvider(
          syncRepository: syncRepo,
          connectivityProvider: connectivityProv,
        );

    final matchingProv = identityMatchingProvider ??
        IdentityMatchingProvider(
          matchingService: matching,
        );

    return AppDependencies._(
      localStorage: storage,
      apiService: api,
      connectivityService: connectivity,
      smsService: sms,
      matchingService: matching,
      authStorageService: authStorage,
      patientRepository: patientRepo,
      referralRepository: referralRepo,
      syncRepository: syncRepo,
      authProvider: authProv,
      referralProvider: referralProv,
      connectivityProvider: connectivityProv,
      syncProvider: syncProv,
      identityMatchingProvider: matchingProv,
    );
  }

  const AppDependencies._({
    required this.localStorage,
    required this.apiService,
    required this.connectivityService,
    required this.smsService,
    required this.matchingService,
    required this.authStorageService,
    required this.patientRepository,
    required this.referralRepository,
    required this.syncRepository,
    required this.authProvider,
    required this.referralProvider,
    required this.connectivityProvider,
    required this.syncProvider,
    required this.identityMatchingProvider,
  });
}

/// InheritedWidget providing [AppDependencies] down the widget tree.
class RelyCareScope extends InheritedWidget {
  final AppDependencies dependencies;

  const RelyCareScope({
    super.key,
    required this.dependencies,
    required super.child,
  });

  static AppDependencies of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<RelyCareScope>();
    if (scope == null) {
      throw FlutterError('RelyCareScope was not found in the widget hierarchy.');
    }
    return scope.dependencies;
  }

  @override
  bool updateShouldNotify(RelyCareScope oldWidget) => dependencies != oldWidget.dependencies;
}

extension RelyCareContext on BuildContext {
  AppDependencies get dependencies => RelyCareScope.of(this);
  AuthProvider get authProvider => dependencies.authProvider;
  ReferralProvider get referralProvider => dependencies.referralProvider;
  ConnectivityProvider get connectivityProvider => dependencies.connectivityProvider;
  SyncProvider get syncProvider => dependencies.syncProvider;
  IdentityMatchingProvider get identityMatchingProvider => dependencies.identityMatchingProvider;
}
