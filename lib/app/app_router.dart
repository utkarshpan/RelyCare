import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../screens/login/login_screen.dart';
import '../screens/phc_dashboard/phc_dashboard_screen.dart';
import '../screens/hospital_dashboard/hospital_dashboard_screen.dart';
import '../screens/create_referral/create_referral_screen.dart';
import '../screens/create_referral/create_referral_step2_screen.dart';
import '../screens/identity_matching/identity_matching_screen.dart';
import '../screens/referral_details/referral_details_screen.dart';
import '../screens/referrals/referrals_screen.dart';
import '../screens/sync/sync_status_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/user_tracking/user_tracking_screen.dart';
import '../screens/user_profile/user_profile_screen.dart';
import '../screens/referral_status/referral_status_screen.dart';
import '../screens/emergency/emergency_screen.dart';
import '../providers/auth_provider.dart';

/// Centralized GoRouter navigation configuration for RelyCare.
class AppRouter {
  static const String login = '/login';
  static const String phcDashboard = '/phc-dashboard';
  static const String hospitalDashboard = '/hospital-dashboard';
  static const String dashboard = '/dashboard';
  static const String createReferral = '/create-referral';
  static const String createReferralStep2 = '/create-referral-step2';
  static const String identityMatching = '/identity-matching';
  static const String referralDetails = '/referral-details';
  static const String referrals = '/referrals';
  static const String syncStatus = '/sync-status';
  static const String profile = '/profile';
  static const String userTracking = '/user-tracking';
  static const String userProfile = '/user-profile';
  static const String referralStatus = '/referral-status';
  static const String emergency = '/emergency';

  /// Routes that do NOT require authentication.
  static const _publicRoutes = {
    login,
    userTracking,
    userProfile,
    referralStatus,
    emergency,
  };

  /// Creates a [GoRouter] that re-evaluates the redirect whenever
  /// [authProvider] calls [notifyListeners].
  static GoRouter createRouter(AuthProvider authProvider) {
    return GoRouter(
      initialLocation: login,
      refreshListenable: authProvider,
      redirect: (BuildContext context, GoRouterState state) {
        final isAuthenticated = authProvider.isAuthenticated;
        final isPublic = _publicRoutes.contains(state.matchedLocation);

        // Unauthenticated user trying to reach a protected route → redirect to login.
        if (!isAuthenticated && !isPublic) {
          return login;
        }

        // Authenticated user landing on the login page → send to their dashboard.
        if (isAuthenticated && state.matchedLocation == login) {
          switch (authProvider.selectedRole) {
            case 'Hospital Staff':
              return hospitalDashboard;
            case 'Patient':
              return userTracking;
            default:
              return phcDashboard;
          }
        }

        // Note: selectedRole is used for UX routing only, not as a production security boundary.
        if (isAuthenticated && !isPublic) {
          final role = authProvider.currentRole;
          final path = state.matchedLocation;

          if (role == UserRole.patient && path != userTracking && path != profile) {
            return userTracking;
          }

          if (role == UserRole.hospitalStaff) {
            final allowedHospitalRoutes = {
              hospitalDashboard,
              identityMatching,
              referralDetails,
              referrals,
              syncStatus,
              profile,
            };
            if (!allowedHospitalRoutes.contains(path)) {
              return hospitalDashboard;
            }
          }

          if (role == UserRole.phcStaff) {
            final allowedPhcRoutes = {
              phcDashboard,
              dashboard,
              createReferral,
              createReferralStep2,
              referrals,
              referralDetails,
              syncStatus,
              profile,
            };
            if (!allowedPhcRoutes.contains(path)) {
              return phcDashboard;
            }
          }
        }

        // No redirect needed.
        return null;
      },
      routes: [
        GoRoute(
          path: login,
          name: 'login',
          builder: (BuildContext context, GoRouterState state) {
            return const LoginScreen();
          },
        ),
        GoRoute(
          path: phcDashboard,
          name: 'phcDashboard',
          builder: (BuildContext context, GoRouterState state) {
            return const PHCDashboardScreen();
          },
        ),
        GoRoute(
          path: hospitalDashboard,
          name: 'hospitalDashboard',
          builder: (BuildContext context, GoRouterState state) {
            return const HospitalDashboardScreen();
          },
        ),
        GoRoute(
          path: dashboard,
          name: 'dashboard',
          builder: (BuildContext context, GoRouterState state) {
            return const PHCDashboardScreen();
          },
        ),
        GoRoute(
          path: createReferral,
          name: 'createReferral',
          builder: (BuildContext context, GoRouterState state) {
            return const CreateReferralScreen();
          },
        ),
        GoRoute(
          path: createReferralStep2,
          name: 'createReferralStep2',
          builder: (BuildContext context, GoRouterState state) {
            final extra = state.extra as Map<String, dynamic>? ?? {};
            return CreateReferralStep2Screen(patientData: extra);
          },
        ),
        GoRoute(
          path: identityMatching,
          name: 'identityMatching',
          builder: (BuildContext context, GoRouterState state) {
            return const IdentityMatchingScreen();
          },
        ),
        GoRoute(
          path: referralDetails,
          name: 'referralDetails',
          builder: (BuildContext context, GoRouterState state) {
            return const ReferralDetailsScreen();
          },
        ),
        GoRoute(
          path: referrals,
          name: 'referrals',
          builder: (BuildContext context, GoRouterState state) {
            return const ReferralsScreen();
          },
        ),
        GoRoute(
          path: syncStatus,
          name: 'syncStatus',
          builder: (BuildContext context, GoRouterState state) {
            return const SyncStatusScreen();
          },
        ),
        GoRoute(
          path: profile,
          name: 'profile',
          builder: (BuildContext context, GoRouterState state) {
            return const ProfileScreen();
          },
        ),
        GoRoute(
          path: userTracking,
          name: 'userTracking',
          builder: (BuildContext context, GoRouterState state) {
            return const UserTrackingScreen();
          },
        ),
        GoRoute(
          path: userProfile,
          name: 'userProfile',
          builder: (BuildContext context, GoRouterState state) {
            return const UserProfileScreen();
          },
        ),
        GoRoute(
          path: referralStatus,
          name: 'referralStatus',
          builder: (BuildContext context, GoRouterState state) {
            return const ReferralStatusScreen();
          },
        ),
        GoRoute(
          path: emergency,
          name: 'emergency',
          builder: (BuildContext context, GoRouterState state) {
            return const EmergencyScreen();
          },
        ),
      ],
    );
  }
}
