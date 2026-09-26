import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../core/theme/app_theme.dart';
import '../core/constants/app_constants.dart';
import '../providers/auth_provider.dart';
import '../providers/user_profile_provider.dart';
import '../providers/referral_journey_provider.dart';
import 'app_dependencies.dart';
import 'app_router.dart';

/// Root application widget for RelyCare with MultiProvider and GoRouter.
class RelyCareApp extends StatefulWidget {
  final AppDependencies? dependencies;

  const RelyCareApp({super.key, this.dependencies});

  @override
  State<RelyCareApp> createState() => _RelyCareAppState();
}

class _RelyCareAppState extends State<RelyCareApp> {
  late final AppDependencies _dependencies;
  late final AuthProvider _authProvider;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _dependencies = widget.dependencies ?? AppDependencies();
    _authProvider = _dependencies.authProvider;
    _router = AppRouter.createRouter(_authProvider);
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeDependencies = _dependencies;


    return RelyCareScope(
      dependencies: activeDependencies,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: _authProvider),
          ChangeNotifierProvider.value(value: activeDependencies.referralProvider),
          ChangeNotifierProvider.value(value: activeDependencies.connectivityProvider),
          ChangeNotifierProvider.value(value: activeDependencies.syncProvider),
          ChangeNotifierProvider.value(value: activeDependencies.identityMatchingProvider),
          ChangeNotifierProvider(create: (_) => UserProfileProvider()),
          ChangeNotifierProvider(create: (_) => ReferralJourneyProvider()),
        ],
        child: MaterialApp.router(
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          routerConfig: _router,
        ),
      ),
    );
  }
}

